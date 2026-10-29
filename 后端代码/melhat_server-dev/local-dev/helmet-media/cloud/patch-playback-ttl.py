#!/usr/bin/env python3
"""Update only the installed control service playback TTL; Python 3.6 compatible.

Preview is read-only. Apply requires the exact image/source hashes from preview.
Existing environment, mounts, host networking and security settings are retained.
Rollback restarts the retained predecessor using CURRENT media data, never a dump.
"""
from __future__ import print_function
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

ROOT = Path('/opt/helmet-wear/helmet-media')
OLD_TOKEN = "this.token('play', stream.streamId, 3600)"
NEW_TOKEN = "this.token('play', stream.streamId, 30)"
OLD_EXPIRY = 'expiresAt: new Date(Date.now() + 3600000).toISOString(), iceServers: this.iceServers()'
NEW_EXPIRY = 'expiresAt: new Date(Date.now() + 30000).toISOString(), iceServers: this.iceServers()'
MASKED_DEFAULTS = {'/proc/asound', '/proc/acpi', '/proc/interrupts', '/proc/kcore', '/proc/keys',
                   '/proc/latency_stats', '/proc/timer_list', '/proc/timer_stats', '/proc/sched_debug',
                   '/proc/scsi', '/sys/firmware', '/sys/devices/virtual/powercap'}
READONLY_DEFAULTS = {'/proc/bus', '/proc/fs', '/proc/irq', '/proc/sys', '/proc/sysrq-trigger'}


def docker(*args, **kwargs):
    try:
        value = subprocess.run(['docker'] + list(args), input=kwargs.get('data'),
                               stdout=kwargs.get('output') or subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=kwargs.get('timeout', 120))
    except subprocess.TimeoutExpired:
        raise RuntimeError('Docker timed out: ' + args[0]) from None
    if value.returncode:
        raise RuntimeError('Docker failed: ' + args[0])
    return value.stdout


def sha(data):
    return hashlib.sha256(data).hexdigest()


def private_write(path, data):
    if not isinstance(data, bytes):
        data = json.dumps(data, indent=2, sort_keys=True).encode('utf-8')
    fd = os.open(str(path), os.O_CREAT | os.O_TRUNC | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def inspect(name):
    return json.loads(docker('inspect', name))[0]


def current_control():
    names = docker('ps', '-q', '--filter', 'label=com.docker.compose.project=helmet-media',
                   '--filter', 'label=com.docker.compose.service=control').decode().split()
    if len(names) != 1:
        raise RuntimeError('Expected exactly one running helmet-media control container')
    return inspect(names[0])


def updated_source(source):
    text = source.decode('utf-8')
    if text.count(OLD_TOKEN) != 1 or text.count(OLD_EXPIRY) != 1:
        raise RuntimeError('Source is not the exact expected old playback TTL implementation')
    return text.replace(OLD_TOKEN, NEW_TOKEN).replace(OLD_EXPIRY, NEW_EXPIRY).encode('utf-8')


def validate_configuration(previous):
    host = previous['HostConfig']
    if host['NetworkMode'] != 'host' or host.get('PortBindings'):
        raise RuntimeError('Expected existing host networking without published ports')
    for key in ('Privileged', 'ReadonlyRootfs', 'AutoRemove', 'PublishAllPorts', 'Dns', 'DnsOptions', 'DnsSearch',
                'CapAdd', 'Devices', 'DeviceRequests', 'Tmpfs', 'VolumesFrom', 'Links', 'Ulimits',
                'UsernsMode', 'PidMode', 'UTSMode', 'NanoCpus', 'CpuShares', 'CpusetCpus', 'CpusetMems',
                'OomKillDisable', 'Init', 'ExtraHosts', 'MemoryReservation', 'DeviceCgroupRules', 'StorageOpt',
                'CgroupParent', 'GroupAdd', 'OomScoreAdj', 'KernelMemory', 'KernelMemoryTCP', 'CpuPeriod',
                'CpuRealtimePeriod', 'CpuRealtimeRuntime', 'BlkioWeight', 'BlkioWeightDevice',
                'BlkioDeviceReadBps', 'BlkioDeviceWriteBps', 'BlkioDeviceReadIOps', 'BlkioDeviceWriteIOps',
                'ContainerIDFile'):
        if host.get(key):
            raise RuntimeError('Unreviewed control setting: ' + key)
    if host.get('CpuQuota') not in (None, 0, -1) or host.get('PidsLimit') not in (None, 0, -1):
        raise RuntimeError('Unexpected resource limits')
    if host.get('IpcMode') not in (None, '', 'private') or host.get('CgroupnsMode') not in (None, '', 'private'):
        raise RuntimeError('Unexpected namespaces')
    if host.get('Runtime') not in (None, '', 'runc') or host.get('Isolation') not in (None, '', 'default'):
        raise RuntimeError('Unexpected runtime or isolation')
    masked = set(host.get('MaskedPaths') or [])
    if masked not in (MASKED_DEFAULTS, MASKED_DEFAULTS - {'/sys/devices/virtual/powercap'}):
        raise RuntimeError('Unexpected masked system paths')
    if set(host.get('ReadonlyPaths') or []) != READONLY_DEFAULTS:
        raise RuntimeError('Unexpected read-only system paths')
    log = host.get('LogConfig') or {}
    if log.get('Type') not in (None, '', 'json-file') or log.get('Config'):
        raise RuntimeError('Unexpected logging configuration')
    if set(host.get('CapDrop') or []) != {'ALL'} or set(host.get('SecurityOpt') or []) != {'no-new-privileges:true'}:
        raise RuntimeError('Expected existing control capability/security settings')
    mounts = previous.get('Mounts') or []
    if len(mounts) != 1 or mounts[0]['Type'] != 'bind' or mounts[0]['Destination'] != '/data' or not mounts[0]['RW']:
        raise RuntimeError('Expected one existing writable /data bind mount')
    if Path(mounts[0]['Source']).resolve() != (ROOT / '.local/data').resolve():
        raise RuntimeError('Media data mount differs from the existing installation')
    if mounts[0].get('Propagation') not in (None, '', 'rprivate'):
        raise RuntimeError('Unexpected data mount propagation')
    config = previous['Config']
    if config.get('OpenStdin') or config.get('Tty') or config.get('StopTimeout') is not None:
        raise RuntimeError('Unexpected interactive or custom stop configuration')
    environment = dict(value.split('=', 1) for value in config.get('Env') or [] if '=' in value)
    if environment.get('MEDIA_PUBLIC_IP') != '39.106.212.138' or environment.get('MEDIA_PUBLIC_ORIGIN') != 'https://lingzhiaide.com':
        raise RuntimeError('Existing media configuration does not identify the authorized host/domain')
    if config.get('Hostname') != previous['Id'][:12] or config.get('Domainname'):
        raise RuntimeError('Unexpected custom host identity')
    if config.get('Image') != 'helmet-media-control:1':
        raise RuntimeError('Expected the reviewed control image tag')


def state_summary(data):
    value = json.loads(data)
    return {'sequence': value.get('sequence', 0),
            'assets': len(value.get('assets', {})), 'events': len(value.get('events', [])),
            'activeRecordings': sum(1 for row in value.get('recordings', {}).values()
                                    if row.get('status') in ('starting', 'recording', 'finalizing'))}


def preview():
    if (ROOT / 'service.mjs').is_symlink() or (ROOT / '.local').is_symlink():
        raise RuntimeError('Installation source/private directory must not be symbolic links')
    previous = current_control()
    validate_configuration(previous)
    source = docker('exec', previous['Id'], 'cat', '/app/service.mjs')
    changed = updated_source(source)
    host_source = (ROOT / 'service.mjs').read_bytes()
    if host_source != source:
        raise RuntimeError('Installed source and running image source differ; review before patching')
    state = docker('exec', previous['Id'], 'cat', '/data/state.json')
    summary = state_summary(state)
    if summary['activeRecordings']:
        raise RuntimeError('Active platform recordings exist; finish them before a control restart')
    result = {'container': previous['Name'].lstrip('/'), 'containerId': previous['Id'],
              'imageId': previous['Image'], 'sourceSha256': sha(source), 'newSourceSha256': sha(changed),
              'dataDirectory': str(ROOT / '.local/data'), 'state': summary,
              'changes': ['play token 3600 -> 30 seconds', 'expiresAt 3600000 -> 30000 milliseconds'],
              'credentialsPrinted': False, 'networkChanged': False}
    return result, previous, source, changed


def run_args(previous, image):
    host, config = previous['HostConfig'], previous['Config']
    args = ['run', '-d', '--name', previous['Name'].lstrip('/'), '--network', 'host']
    policy = host['RestartPolicy']
    restart = policy['Name'] or 'no'
    if restart == 'on-failure' and policy.get('MaximumRetryCount'):
        restart += ':' + str(policy['MaximumRetryCount'])
    args += ['--restart', restart, '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true']
    if host.get('Runtime'):
        args += ['--runtime', host['Runtime']]
    for key, flag in [('Memory', '--memory'), ('MemorySwap', '--memory-swap'), ('ShmSize', '--shm-size')]:
        if host.get(key):
            args += [flag, str(host[key])]
    if host.get('MemorySwappiness') is not None:
        args += ['--memory-swappiness', str(host['MemorySwappiness'])]
    mount = previous['Mounts'][0]
    args += ['-v', mount['Source'] + ':/data']
    for value in config.get('Env') or []:
        args += ['-e', value]
    for key, value in (config.get('Labels') or {}).items():
        args += ['--label', key + '=' + value]
    for key, flag in [('User', '--user'), ('WorkingDir', '--workdir'), ('StopSignal', '--stop-signal')]:
        if config.get(key):
            args += [flag, config[key]]
    return args + [image] + (config.get('Cmd') or [])


def verify_configuration(previous, current):
    for key in ('Env', 'Cmd', 'Entrypoint', 'Labels', 'User', 'WorkingDir', 'StopSignal',
                'Healthcheck', 'StopTimeout', 'OpenStdin', 'Tty'):
        a, b = previous['Config'].get(key), current['Config'].get(key)
        if key == 'Env':
            a, b = sorted(a or []), sorted(b or [])
        if a != b:
            raise RuntimeError('Preserved opaque container configuration changed: ' + key)
    for key in ('NetworkMode', 'RestartPolicy', 'PortBindings', 'SecurityOpt', 'CapDrop',
                'Memory', 'MemorySwap', 'ShmSize', 'MemorySwappiness', 'Runtime', 'MaskedPaths',
                'ReadonlyPaths', 'DeviceCgroupRules', 'StorageOpt'):
        if previous['HostConfig'].get(key) != current['HostConfig'].get(key):
            raise RuntimeError('Preserved container setting changed: ' + key)
    fields = ('Type', 'Source', 'Destination', 'RW', 'Propagation')
    for a, b in zip(previous['Mounts'], current['Mounts']):
        if any(a.get(key) != b.get(key) for key in fields):
            raise RuntimeError('Preserved data mount changed')
    if len(previous['Mounts']) != len(current['Mounts']):
        raise RuntimeError('Preserved mount count changed')


def healthy():
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:18190/healthz', timeout=3) as response:
                if response.status == 200 and json.load(response).get('status') == 'running':
                    return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError('Control anonymous health did not pass')


def restore(previous, directory, record):
    name, retained = record['container'], record['retainedContainer']
    try:
        current = inspect(name)
    except RuntimeError:
        current = None
    if current and current['Id'] != previous['Id']:
        docker('stop', '--time', '30', name)
        docker('rename', name, record['failedContainer'])
        current = None
    if current is None:
        if inspect(retained)['Id'] != previous['Id']:
            raise RuntimeError('Retained predecessor changed; media data was not restored')
        docker('rename', retained, name)
    docker('start', name)
    healthy()
    # The retained container already has the old source in its image. Disk-full
    # failures restoring host source/tag must never prevent service recovery.
    try:
        docker('tag', previous['Image'], previous['Config']['Image'])
        record['recoveryImageTagRestored'] = True
    except RuntimeError:
        record['recoveryImageTagRestored'] = False
    try:
        # Restore code only. state.json/assets are intentionally never restored.
        (ROOT / 'service.mjs').write_bytes((directory / 'service-before.mjs').read_bytes())
        record['recoverySourceRestored'] = True
    except OSError:
        record['recoverySourceRestored'] = False


def apply(expected_image, expected_source):
    plan, previous, source, changed = preview()
    if plan['imageId'] != expected_image or plan['sourceSha256'] != expected_source:
        raise RuntimeError('Preview hashes changed; obtain a new preview')
    stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()).lower()
    directory = ROOT / '.local' / ('playback-ttl-patch-' + stamp)
    directory.mkdir(mode=0o700)
    private_write(directory / 'deployment.private.json', previous)
    private_write(directory / 'service-before.mjs', source)
    private_write(directory / 'service.mjs', changed)
    baseline_tag = 'helmet-media-control:before-ttl-' + stamp
    candidate = 'helmet-media-control:ttl30-' + stamp
    docker('tag', previous['Image'], baseline_tag)
    private_write(directory / 'Dockerfile', ('FROM ' + baseline_tag + '\nCOPY service.mjs /app/service.mjs\n').encode())
    private_write(directory / '.dockerignore', b'*\n!Dockerfile\n!service.mjs\n')
    with (directory / 'build.log').open('wb') as output:
        docker('build', '--network', 'none', '--pull=false', '-t', candidate, str(directory), output=output, timeout=600)
    new_image = inspect(candidate)['Id']
    inherited = inspect(new_image)['Config']
    for key in ('Entrypoint', 'Healthcheck'):
        if previous['Config'].get(key) != inherited.get(key):
            raise RuntimeError('Custom image setting cannot be preserved: ' + key)
    check = "import {MediaService} from './service.mjs'; const calls=[]; const urls=MediaService.prototype.streamUrls.call({config:{publicIp:'127.0.0.1',publicOrigin:'https://example.invalid'},token:(...a)=>{calls.push(a);return 'test';},iceServers:()=>[]},{streamId:'isolated'}); if(calls[0][2]!==30||calls[1][2]!==14400||Math.abs(Date.parse(urls.expiresAt)-Date.now()-30000)>1000) process.exit(1); console.log('TTL_ASSERTIONS_PASSED');"
    docker('run', '--rm', '--network', 'none', '--entrypoint', 'node', new_image, '--input-type=module', '-e', check)
    fresh, actual, _, _ = preview()
    if actual['Id'] != previous['Id'] or fresh['sourceSha256'] != expected_source:
        raise RuntimeError('Current control changed while building; no live restart attempted')
    record = dict(plan, status='prepared', imageId=new_image, oldImageId=previous['Image'], backupDirectory=str(directory),
                  retainedContainer=plan['container'] + '-before-' + stamp,
                  failedContainer=plan['container'] + '-failed-' + stamp, dataRestored=False)
    private_write(directory / 'receipt.json', record)
    try:
        docker('stop', '--time', '30', plan['container'])
        if inspect(plan['container'])['State']['Running']:
            raise RuntimeError('Old control did not stop')
        state_path = ROOT / '.local/data/state.json'
        state = state_path.read_bytes()
        private_write(directory / 'state-before.private.json', state)
        if state_summary(state)['activeRecordings']:
            raise RuntimeError('Recording appeared before cutover; retaining predecessor')
        files = [{'path': str(path.relative_to(ROOT / '.local/data')), 'bytes': path.stat().st_size}
                 for path in (ROOT / '.local/data').rglob('*') if path.is_file()]
        private_write(directory / 'media-file-inventory.private.json', files)
        docker('rename', plan['container'], record['retainedContainer'])
        docker(*run_args(previous, new_image))
        healthy()
        current = inspect(plan['container'])
        verify_configuration(previous, current)
        if sha(docker('exec', current['Id'], 'cat', '/app/service.mjs')) != sha(changed):
            raise RuntimeError('Running source hash differs from tested candidate')
        after = state_summary(state_path.read_bytes())
        before = state_summary(state)
        if after['sequence'] < before['sequence'] or after['assets'] < before['assets']:
            raise RuntimeError('Media state decreased')
        (ROOT / 'service.mjs').write_bytes(changed)
        docker('tag', new_image, previous['Config']['Image'])
        record.update(status='deployed', currentContainerId=current['Id'], before=before, after=after)
        private_write(directory / 'receipt.json', record)
    except Exception:
        # Recovery must not depend on writing a receipt when the backup disk is full.
        try:
            restore(previous, directory, record)
        except Exception:
            record['status'] = 'compatible-recovery-incomplete'
            try:
                private_write(directory / 'receipt.json', record)
            except OSError:
                pass
            raise RuntimeError('Patch and compatible recovery did not complete; current media data was not restored or deleted. Inspect the retained containers before proceeding.') from None
        record['status'] = 'compatible-predecessor-restored'
        try:
            private_write(directory / 'receipt.json', record)
        except OSError:
            pass
        raise RuntimeError('Patch failed; compatible predecessor restored against current data') from None
    return record


def rollback(directory):
    directory = Path(directory).resolve()
    if directory.parent != (ROOT / '.local').resolve() or not directory.name.startswith('playback-ttl-patch-'):
        raise RuntimeError('Expected an existing patch backup directory')
    previous = json.loads((directory / 'deployment.private.json').read_text())
    record = json.loads((directory / 'receipt.json').read_text())
    current = inspect(record['container'])
    if current['Id'] != record.get('currentContainerId') or current['Image'] != record['imageId']:
        raise RuntimeError('Current control changed since this patch')
    summary = state_summary(docker('exec', current['Id'], 'cat', '/data/state.json'))
    if summary['activeRecordings']:
        raise RuntimeError('Finish current platform recordings before rollback')
    restore(previous, directory, record)
    record['status'] = 'rolled-back-preserving-current-data'
    private_write(directory / 'receipt.json', record)
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['preview', 'apply', 'rollback'])
    parser.add_argument('--expected-image')
    parser.add_argument('--expected-source')
    parser.add_argument('--backup-directory')
    args = parser.parse_args()
    try:
        if os.name != 'posix' or os.geteuid() != 0:
            raise RuntimeError('Run with sudo on the existing Linux media host')
        if args.action == 'preview':
            result = preview()[0]
        elif args.action == 'apply':
            if not args.expected_image or not args.expected_source:
                raise RuntimeError('Apply requires both exact hashes from preview')
            result = apply(args.expected_image, args.expected_source)
        else:
            if not args.backup_directory:
                raise RuntimeError('Rollback requires the backup directory printed by apply')
            result = rollback(args.backup_directory)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
