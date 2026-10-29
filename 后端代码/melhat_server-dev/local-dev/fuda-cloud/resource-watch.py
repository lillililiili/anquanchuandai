"""Linux/Python 3.6+ protection for a temporary, explicitly limited staging rehearsal.

--preflight is read-only and checks headroom before starting the stack.
--sample takes one read-only sample. --watch samples until --duration expires;
on a resource/health breach it stops only the four labelled staging services,
never removes containers/volumes, and never operates on an existing service.
Start the watcher BEFORE starting staging to capture the existing-service baseline.
Initially stopped, correctly owned/limited staging containers have 120 seconds to
start; after a container has run, an exit remains an immediate guard condition.
Swap I/O uses actual page size and monotonic sample intervals: combined swap-in
and swap-out must average at least 1 MiB/s continuously for 30 seconds to trigger.
When the watcher exits, ongoing protection ends; it is not a production monitor.
"""
from __future__ import print_function
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

PROJECT = 'fuda-wearables-staging'
LIMIT_LABEL = 'com.wearables.rehearsal-limited'
MIB = 1024 * 1024
CAPS = {'mysql': (384 * MIB, 0.3), 'backend': (640 * MIB, 0.5),
        'redis': (64 * MIB, 0.1), 'query-gateway': (64 * MIB, 0.1)}


def docker(args):
    # This guard runs on the Linux server and can never select a remote Docker context.
    env = dict(os.environ)
    for name in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
        env.pop(name, None)
    result = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock'] + list(args),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=30)
    if result.returncode:
        raise RuntimeError('Docker observation/action failed; private command output was suppressed')
    return result.stdout


def container_service(info):
    labels = info.get('Config', {}).get('Labels') or {}
    if labels.get('com.docker.compose.project') != PROJECT:
        return None
    return labels.get('com.docker.compose.service')


def owned(info):
    return (container_service(info) in CAPS and
            (info.get('Config', {}).get('Labels') or {}).get(LIMIT_LABEL) == 'true' and
            re.match(r'^[0-9a-f]{64}$', info.get('Id', '')) is not None)


def cap_issues(info):
    service = container_service(info)
    if service not in CAPS or not owned(info):
        return ['unrecognised_staging_container']
    memory, cpus = CAPS[service]
    config = info.get('HostConfig', {})
    issues = []
    actual = config.get('Memory', 0)
    if actual <= 0 or actual > memory:
        issues.append('memory_limit_missing_or_too_high')
    if config.get('MemorySwap') != actual:
        issues.append('swap_not_disabled')
    nano = config.get('NanoCpus', 0)
    quota, period = config.get('CpuQuota', 0), config.get('CpuPeriod', 0)
    actual_cpu = nano / 1000000000.0 if nano > 0 else (quota / float(period) if quota > 0 and period > 0 else 0)
    if actual_cpu <= 0 or actual_cpu > cpus + 0.000001:
        issues.append('cpu_limit_missing_or_too_high')
    if config.get('RestartPolicy', {}).get('Name') not in ('no', ''):
        issues.append('automatic_restart_enabled')
    return issues


def inspect_all():
    ids = docker(['ps', '-aq']).decode('ascii').split()
    if not ids:
        return []
    return json.loads(docker(['inspect'] + ids).decode('utf-8'))


def limit_capabilities():
    info = json.loads(docker(['info', '--format', '{{json .}}']).decode('utf-8'))
    return {'memoryLimitSupported': info.get('MemoryLimit') is True,
            'swapLimitSupported': info.get('SwapLimit') is True,
            'cpuQuotaSupported': info.get('CpuCfsQuota', info.get('CPUCfsQuota')) is True}


def host_state(root):
    values = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        values[key] = int(value.strip().split()[0]) * 1024
    swap = {}
    for line in Path('/proc/vmstat').read_text().splitlines():
        key, value = line.split()
        if key in ('pswpin', 'pswpout'):
            swap[key] = int(value)
    return {'availableMemoryBytes': values['MemAvailable'],
            'swapUsedBytes': values.get('SwapTotal', 0) - values.get('SwapFree', 0),
            'swapInPages': swap.get('pswpin', 0), 'swapOutPages': swap.get('pswpout', 0),
            'pageSizeBytes': os.sysconf('SC_PAGE_SIZE'),
            'freeDiskBytes': shutil.disk_usage(str(root)).free,
            'loadAverage': list(os.getloadavg())}


def observe(root):
    infos = inspect_all()
    staging, other = [], {}
    for info in infos:
        service = container_service(info)
        labels = info.get('Config', {}).get('Labels') or {}
        state = info.get('State') or {}
        safe = {'id': info['Id'], 'running': bool(state.get('Running')),
                'oomKilled': bool(state.get('OOMKilled')), 'status': state.get('Status'),
                'health': (state.get('Health') or {}).get('Status'),
                'restartCount': info.get('RestartCount', 0)}
        if labels.get('com.docker.compose.project') == PROJECT:
            safe.update(service=service, capIssues=cap_issues(info))
            staging.append(safe)
        else:
            other[info['Id']] = safe
    return {'host': host_state(root), 'staging': staging, 'other': other}


class Thresholds(object):
    def __init__(self, initial):
        self.swap_baseline = initial['host']['swapUsedBytes']
        self.original = {key: value for key, value in initial['other'].items() if value['running']}
        self.low_since = None
        self.swap_activity_since = None
        self.previous_swap_pages = (initial['host'].get('swapInPages', 0), initial['host'].get('swapOutPages', 0))
        self.page_size = initial['host']['pageSizeBytes']
        if not isinstance(self.page_size, int) or self.page_size <= 0:
            raise ValueError('A positive observed system page size is required')
        self.previous_swap_time = None
        self.last_swap_bytes_per_second = None
        self.seen_running = set(row['id'] for row in initial['staging'] if row['running'])
        # Only these exact pre-existing, stopped identities receive startup grace.
        # New failed containers, OOMs and ownership/limit mismatches are not exempt.
        self.initial_waiting = set(row['id'] for row in initial['staging']
            if not row['running'] and row['status'] == 'exited' and not row['oomKilled']
            and not row['capIssues'] and row.get('service') in CAPS
            and re.match(r'^[0-9a-f]{64}$', row['id']) is not None)
        self.startup_wait_started = None

    def evaluate(self, sample, now):
        reasons = []
        host = sample['host']
        available = host['availableMemoryBytes']
        if available < 256 * MIB:
            reasons.append('host_memory_below_256MiB')
        if available < 512 * MIB:
            if self.low_since is None:
                self.low_since = now
            if now - self.low_since >= 30:
                reasons.append('host_memory_below_512MiB_for_30s')
        else:
            self.low_since = None
        if host['swapUsedBytes'] - self.swap_baseline > 128 * MIB:
            reasons.append('host_swap_growth_above_128MiB')
        pages = (host.get('swapInPages', 0), host.get('swapOutPages', 0))
        elapsed = None if self.previous_swap_time is None else now - self.previous_swap_time
        self.last_swap_bytes_per_second = None
        if elapsed is not None and elapsed > 0:
            changed_pages = sum(max(0, current - previous) for current, previous in zip(pages, self.previous_swap_pages))
            self.last_swap_bytes_per_second = changed_pages * self.page_size / float(elapsed)
        if self.last_swap_bytes_per_second is not None and self.last_swap_bytes_per_second >= MIB:
            if self.swap_activity_since is None:
                self.swap_activity_since = self.previous_swap_time
            if now - self.swap_activity_since >= 30:
                reasons.append('host_swap_io_ge_1MiBps_for_30s')
        else:
            self.swap_activity_since = None
        self.previous_swap_pages = pages
        self.previous_swap_time = now
        if host['freeDiskBytes'] < 10 * 1024 ** 3:
            reasons.append('disk_free_below_10GiB')
        services = [row.get('service') for row in sample['staging'] if row['running']]
        if any(services.count(service) > 1 for service in CAPS):
            reasons.append('duplicate_staging_service_exceeds_rehearsal_scope')
        if self.startup_wait_started is None:
            self.startup_wait_started = now
        for row in sample['staging']:
            awaiting_initial_start = row['id'] in self.initial_waiting and row['id'] not in self.seen_running
            stale_stopped_health = awaiting_initial_start and not row['running'] and row['status'] == 'exited'
            if row['capIssues']:
                reasons.append('staging_limit_or_ownership_mismatch')
            if row['oomKilled']:
                reasons.append('staging_oom')
            # Docker can retain the previous health result after a normal stop.
            # Ignore only that exact initial stopped state, never running health.
            if row['health'] == 'unhealthy' and not stale_stopped_health:
                reasons.append('staging_unhealthy')
            if (row['status'] in ('dead', 'restarting')
                    or (row['status'] == 'exited' and not awaiting_initial_start)
                    or (row['id'] in self.seen_running and not row['running'])):
                reasons.append('staging_process_exited')
            if row['running']:
                self.seen_running.add(row['id'])
                self.initial_waiting.discard(row['id'])
        if self.initial_waiting and now - self.startup_wait_started >= 120:
            reasons.append('initial_staging_startup_timeout_120s')
        for key, before in self.original.items():
            current = sample['other'].get(key)
            if current is None or not current['running'] or current['restartCount'] > before['restartCount']:
                reasons.append('existing_service_stopped_or_restarted')
            elif before['health'] == 'healthy' and current['health'] == 'unhealthy':
                reasons.append('existing_service_health_degraded')
        return sorted(set(reasons))


def stop_owned():
    # Re-read ownership immediately before acting; immutable IDs prevent name-reuse races.
    infos = inspect_all()
    targets = [info['Id'] for info in infos if owned(info) and info.get('State', {}).get('Running')]
    if targets:
        docker(['stop', '--time', '8'] + targets)
    return [value[:12] for value in targets]


def public_sample(sample):
    # No container Env, args, mounts, passwords, database rows or original service names.
    rows = []
    for row in sample['staging']:
        safe = dict(row)
        safe['id'] = safe['id'][:12]
        rows.append(safe)
    return {'host': sample['host'], 'staging': rows,
            'existingRunningContainers': sum(1 for item in sample['other'].values() if item['running'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--preflight', '--baseline', dest='preflight', action='store_true',
                       help='Read-only pre-start headroom check and baseline JSON; does not start the watcher')
    modes.add_argument('--sample', action='store_true')
    modes.add_argument('--watch', action='store_true')
    parser.add_argument('--root', default=str(Path(__file__).resolve().parent))
    parser.add_argument('--interval', type=int, default=5)
    parser.add_argument('--duration', type=int, default=900)
    parser.add_argument('--save-private-report', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Linux' or not 1 <= args.interval <= 30 or not 1 <= args.duration <= 86400:
        raise ValueError('Linux host and valid bounded interval/duration required')
    root = Path(args.root).resolve()
    if not root.is_dir():
        raise ValueError('Root must be an existing directory')
    report = None
    if args.save_private_report:
        directory = Path(__file__).resolve().parent / '.private' / 'resource-watch'
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        name = datetime.datetime.now(datetime.timezone.utc).strftime('watch-%Y%m%dT%H%M%SZ-') + str(os.getpid()) + '.jsonl'
        report = os.fdopen(os.open(str(directory / name), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w')

    def emit(event):
        event['time'] = datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
        line = json.dumps(event, ensure_ascii=True, sort_keys=True)
        print(line, flush=True)
        if report:
            report.write(line + '\n')
            report.flush()

    initial = observe(root)
    if args.preflight:
        capabilities = limit_capabilities()
        required = sum(value[0] for value in CAPS.values()) + 512 * MIB
        issues = []
        if not all(capabilities.values()):
            issues.append('host_does_not_confirm_all_required_cgroup_limits')
        if initial['host']['availableMemoryBytes'] < required:
            issues.append('requires_1664MiB_available_before_start')
        if initial['host']['freeDiskBytes'] < 10 * 1024 ** 3:
            issues.append('requires_10GiB_free_disk')
        if any(row['capIssues'] for row in initial['staging']):
            issues.append('existing_staging_limits_or_ownership_mismatch')
        emit({'event': 'limited_rehearsal_preflight', 'productionApproval': False,
              'passed': not issues, 'issues': issues, 'limitCapabilities': capabilities,
              'sample': public_sample(initial)})
        return 0 if not issues else 2
    thresholds = Thresholds(initial)
    if args.sample:
        emit({'event': 'read_only_sample', 'sample': public_sample(initial),
              'issues': thresholds.evaluate(initial, time.monotonic())})
        return 0
    capabilities = limit_capabilities()
    if not all(capabilities.values()):
        stopped = stop_owned()
        emit({'event': 'guard_cgroup_limits_unsupported', 'limitCapabilities': capabilities,
              'stoppedIds': stopped, 'originalServicesModified': False, 'volumesDeleted': False})
        return 2
    started = time.monotonic()
    sample = initial
    emit({'event': 'watch_started', 'project': PROJECT, 'durationSeconds': args.duration,
          'swapIoThresholdBytesPerSecond': MIB, 'swapIoSustainedSeconds': 30,
          'initialStoppedStartupTimeoutSeconds': 120,
          'automaticAction': 'stop only owned limited staging on breach; never remove data'})
    while True:
        now = time.monotonic()
        reasons = thresholds.evaluate(sample, now)
        emit({'event': 'observation', 'elapsedSeconds': round(now - started, 1),
              'swapIoBytesPerSecond': thresholds.last_swap_bytes_per_second,
              'issues': reasons, 'sample': public_sample(sample)})
        if reasons:
            stopped = stop_owned()
            emit({'event': 'guard_stopped_staging', 'reasons': reasons, 'stoppedIds': stopped,
                  'originalServicesModified': False, 'volumesDeleted': False})
            return 2
        if now - started >= args.duration:
            emit({'event': 'watch_finished', 'healthyAtEnd': True, 'protectionContinues': False})
            return 0
        time.sleep(min(args.interval, args.duration - (now - started)))
        try:
            sample = observe(root)
        except (ValueError, RuntimeError, OSError, subprocess.SubprocessError):
            # Monitoring loss cannot silently leave a resource-limited trial unguarded.
            stopped = stop_owned()
            emit({'event': 'guard_observation_failed', 'stoppedIds': stopped,
                  'originalServicesModified': False, 'volumesDeleted': False})
            return 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(json.dumps({'event': 'watch_interrupted', 'protectionContinues': False,
                          'containersModifiedByInterrupt': False}))
        sys.exit(130)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({'event': 'watch_error', 'errorType': type(error).__name__,
                          'privateDetailsSuppressed': True}), file=sys.stderr)
        sys.exit(2)
