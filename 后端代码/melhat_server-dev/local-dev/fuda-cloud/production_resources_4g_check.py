"""Read-only 4 GiB dedicated-host configuration and trial-admission checks.

Never starts/stops containers, changes routes, writes files, or alters preflight.
Host-window inputs are observation evidence, not authorization to deploy.
"""
import argparse
import datetime
import json
import math
import os
from pathlib import Path
import platform
import shutil
import time

import production_resources_check as common

HERE = Path(__file__).resolve().parent
OVERLAY = 'compose.production-resources-dedicated-4g.yml'
PROFILE = 'production-dedicated-4g-v1'
CAPS_MIB = {'mysql': 448, 'redis': 128, 'backend': 896,
            'query-gateway': 64, 'helmet-gateway': 96, 'belt-gateway': 96,
            'phone-gateway': 96, 'private-relays': 64}
MYSQL_COMMAND = ['--character-set-server=utf8mb4', '--collation-server=utf8mb4_unicode_ci',
                 '--innodb-buffer-pool-size=96M', '--innodb-log-buffer-size=8M',
                 '--max-connections=30', '--table-open-cache=300']
REDIS_COMMAND = ['sh', '-c', 'exec redis-server --appendonly yes --appendfsync everysec '
                 '--no-appendfsync-on-rewrite no --maxmemory 48mb '
                 '--maxmemory-policy noeviction --requirepass "$$REDIS_PASSWORD"']
MIN_AVAILABLE_MIB = 2400
MIN_DISK_GIB = 20
MIN_WINDOW_SECONDS = 300
MAX_SAMPLE_GAP_SECONDS = 15
MAX_SUSTAINED_SWAP_BYTES_PER_SECOND = 1024 ** 2
MAX_SUSTAINED_SWAP_SECONDS = 30


def validate_config(baseline, candidate):
    # Do not silently discard pre-existing JVM options or introduce competing
    # option sources. The currently inspected local runtime has none of these.
    env = baseline.get('services', {}).get('backend', {}).get('environment', {})
    common.require(not any(env.get(k) for k in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')),
                   'Existing JVM options require explicit review before the 4 GiB overlay')
    result = common.validate(baseline, candidate, caps_mib=CAPS_MIB, profile=PROFILE,
                             mysql_command=MYSQL_COMMAND, redis_command=REDIS_COMMAND, host_memory_gib=4)
    result.update(trialOnly=True, productionReady=False,
                  additionalAvailableMemoryReserveMiB=MIN_AVAILABLE_MIB - sum(CAPS_MIB.values()),
                  redisAofFsync='everysec', hostStabilityValidated=False)
    return result


def sample_host(root):
    """One numeric-only Linux observation; does not contact Docker or bind ports."""
    common.require(platform.system() == 'Linux', 'Host samples must be collected on the Linux target')
    mem = {line.split(':', 1)[0]: int(line.split(':', 1)[1].split()[0]) * 1024
           for line in Path('/proc/meminfo').read_text().splitlines()}
    vm = dict(line.split() for line in Path('/proc/vmstat').read_text().splitlines())
    return {'observedUtc': datetime.datetime.utcnow().isoformat() + 'Z',
            'monotonicSeconds': time.monotonic(), 'linuxHost': True,
            'cpuCount': os.cpu_count(), 'totalMemoryBytes': mem['MemTotal'],
            'availableMemoryBytes': mem['MemAvailable'], 'freeDiskBytes': shutil.disk_usage(root).free,
            'swapUsedBytes': mem['SwapTotal'] - mem['SwapFree'],
            'swapInPages': int(vm['pswpin']), 'swapOutPages': int(vm['pswpout']),
            'pageSizeBytes': os.sysconf('SC_PAGE_SIZE')}


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def evaluate_host_window(samples):
    """Require five minutes of genuine observations, not a single free-memory value."""
    common.require(isinstance(samples, list) and 2 <= len(samples) <= 10000, 'Expected a bounded host-sample list')
    required = ('monotonicSeconds', 'cpuCount', 'availableMemoryBytes', 'freeDiskBytes',
                'swapUsedBytes', 'swapInPages', 'swapOutPages', 'pageSizeBytes')
    common.require(all(isinstance(s, dict) and all(finite_number(s.get(k)) and s[k] >= 0 for k in required)
                       for s in samples), 'Invalid numeric host observation')
    common.require(all(s['pageSizeBytes'] > 0 for s in samples), 'Invalid host page size')
    gaps = [b['monotonicSeconds'] - a['monotonicSeconds'] for a, b in zip(samples, samples[1:])]
    common.require(all(g > 0 for g in gaps), 'Host observation times must increase')
    rates = []
    sustained = 0.0
    longest = 0.0
    for a, b, gap in zip(samples, samples[1:], gaps):
        common.require(a['pageSizeBytes'] == b['pageSizeBytes'] and b['swapInPages'] >= a['swapInPages']
                       and b['swapOutPages'] >= a['swapOutPages'], 'Host counter reset or page-size change')
        rate = ((b['swapInPages'] - a['swapInPages']) + (b['swapOutPages'] - a['swapOutPages'])) * b['pageSizeBytes'] / gap
        rates.append(rate)
        sustained = sustained + gap if rate >= MAX_SUSTAINED_SWAP_BYTES_PER_SECOND else 0.0
        longest = max(longest, sustained)
    duration = samples[-1]['monotonicSeconds'] - samples[0]['monotonicSeconds']
    checks = {'linuxTarget': all(s.get('linuxHost') is True for s in samples),
              'atLeastTwoCpus': all(s['cpuCount'] >= 2 for s in samples),
              'fiveMinuteWindow': duration >= MIN_WINDOW_SECONDS,
              'samplingGapsWithinLimit': max(gaps) <= MAX_SAMPLE_GAP_SECONDS,
              'availableMemoryAtLeast2400MiB': min(s['availableMemoryBytes'] for s in samples) >= MIN_AVAILABLE_MIB * 1024 ** 2,
              'freeDiskAtLeast20GiB': min(s['freeDiskBytes'] for s in samples) >= MIN_DISK_GIB * 1024 ** 3,
              'noSustainedSwapPressure': longest < MAX_SUSTAINED_SWAP_SECONDS}
    return {'trialHostAdmissionPassed': all(checks.values()), 'checks': checks,
            'samples': len(samples), 'durationSeconds': round(duration, 3),
            'minimumAvailableMiB': round(min(s['availableMemoryBytes'] for s in samples) / 1024 ** 2, 2),
            'minimumFreeDiskGiB': round(min(s['freeDiskBytes'] for s in samples) / 1024 ** 3, 2),
            'maximumSwapUsedMiB': round(max(s['swapUsedBytes'] for s in samples) / 1024 ** 2, 2),
            'maximumSwapRateMiBPerSecond': round(max(rates) / 1024 ** 2, 3),
            'longestHighSwapSeconds': round(longest, 3),
            'productionReady': False, 'runtimeValidated': False,
            'existingDefaultPreflightUnchanged': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, default=HERE / '.env.production')
    parser.add_argument('--docker', default='docker')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--sample-host', action='store_true', help='Print one numeric Linux host sample only')
    group.add_argument('--host-window', type=Path, help='Validate a saved JSON list of at least five minutes of samples')
    parser.add_argument('--host-root', type=Path, default=HERE)
    args = parser.parse_args()
    if args.sample_host:
        print(json.dumps(sample_host(args.host_root)))
        return 0
    if args.host_window:
        result = evaluate_host_window(json.loads(args.host_window.read_text()))
        print(json.dumps(result, indent=2))
        return 0 if result['trialHostAdmissionPassed'] else 2
    baseline = common.parse_config(['compose.yml', 'compose.production.yml'], args.env_file, args.docker)
    candidate = common.parse_config(['compose.yml', 'compose.production.yml', OVERLAY], args.env_file, args.docker)
    print(json.dumps(validate_config(baseline, candidate), indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('4 GiB trial check failed: ' + (str(error) if isinstance(error, common.ResourceValidationError) else type(error).__name__))
        raise SystemExit(2)
