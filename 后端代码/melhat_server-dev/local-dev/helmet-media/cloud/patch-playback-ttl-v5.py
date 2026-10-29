#!/usr/bin/env python3
"""Update only the installed control service playback TTL; Python 3.6 compatible.

Preview is read-only. Apply requires the exact image/source hashes from preview.
Existing environment, mounts, host networking and security settings are retained.
Rollback restarts the retained predecessor using CURRENT media data, never a dump.
"""
from __future__ import print_function
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import time
import urllib.request

ROOT = Path('/opt/helmet-wear/helmet-media')
REVIEWED_CONTROL_IMAGES = {'helmet-media-control:1', 'helmet-media-control:protocol-20261026'}
OLD_TOKEN = "this.token('play', stream.streamId, 3600)"
NEW_TOKEN = "this.token('play', stream.streamId, 30)"
OLD_EXPIRY = 'expiresAt: new Date(Date.now() + 3600000).toISOString(), iceServers: this.iceServers()'
NEW_EXPIRY = 'expiresAt: new Date(Date.now() + 30000).toISOString(), iceServers: this.iceServers()'
MASKED_DEFAULTS = {'/proc/asound', '/proc/acpi', '/proc/interrupts', '/proc/kcore', '/proc/keys',
                   '/proc/latency_stats', '/proc/timer_list', '/proc/timer_stats', '/proc/sched_debug',
                   '/proc/scsi', '/sys/firmware', '/sys/devices/virtual/powercap'}
READONLY_DEFAULTS = {'/proc/bus', '/proc/fs', '/proc/irq', '/proc/sys', '/proc/sysrq-trigger'}
# Docker API/Compose may serialize these optional lists as null or []. Both
# mean no configured entries. Only these schema-known list fields and only
# genuinely empty values are equivalent; nonempty settings remain exact.
OPTIONAL_HOST_LISTS = {
    'BlkioDeviceReadBps', 'BlkioDeviceReadIOps', 'BlkioDeviceWriteBps',
    'BlkioDeviceWriteIOps', 'BlkioWeightDevice', 'Devices', 'Dns',
    'DnsOptions', 'DnsSearch', 'ExtraHosts', 'Ulimits',
}


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


@contextmanager
def mutation_lock():
    import fcntl
    private = ROOT / '.local'
    if private.is_symlink():
        raise RuntimeError('Private installation directory must not be a symbolic link')
    fd = os.open(str(private / 'playback-ttl-patch.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another media patch or rollback is already running') from None
        yield
    finally:
        os.close(fd)


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


def namespace_modes(previous):
    host = previous['HostConfig']
    ipc, cgroup = host.get('IpcMode'), host.get('CgroupnsMode')
    if ipc != 'private' or cgroup not in ('private', 'host'):
        raise RuntimeError('Unexpected namespaces: IpcMode={0!r}, CgroupnsMode={1!r}; '
                           'expected explicit IPC private and cgroup private/host; '
                           'no container was changed'.format(ipc, cgroup))
    return {'ipc': ipc, 'cgroup': cgroup}


def protected_paths(host, key):
    # Defaults vary with Docker versions. Equivalence is proved against the
    # stopped candidate, before stopping any running service.
    paths = host.get(key)
    if not isinstance(paths, list) or not paths:
        raise RuntimeError('Missing or empty system path protection: ' + key)
    for path in paths:
        if (not isinstance(path, str) or not path.startswith(('/proc/', '/sys/'))
                or any(ord(char) < 32 or ord(char) == 127 for char in path)
                or str(PurePosixPath(path)) != path or '..' in PurePosixPath(path).parts):
            raise RuntimeError('Invalid system path protection: ' + key)
    if len(set(paths)) != len(paths):
        raise RuntimeError('Duplicate system path protection: ' + key)
    return sorted(paths)


def host_identity(previous):
    config = previous['Config']
    values = {'Hostname': config.get('Hostname'), 'Domainname': config.get('Domainname', '')}
    for key, value in values.items():
        if (not isinstance(value, str) or (key == 'Hostname' and not value)
                or any(ord(char) < 32 or ord(char) == 127 for char in value)):
            raise RuntimeError('Cannot preserve explicit container host identity: ' + key)
    return values


def validate_configuration(previous):
    host = previous['HostConfig']
    issues = []
    if host['NetworkMode'] != 'host' or host.get('PortBindings'):
        issues.append('Expected existing host networking without published ports')
    for key in ('Privileged', 'ReadonlyRootfs', 'AutoRemove', 'PublishAllPorts', 'Dns', 'DnsOptions', 'DnsSearch',
                'CapAdd', 'Devices', 'DeviceRequests', 'Tmpfs', 'VolumesFrom', 'Links', 'Ulimits',
                'UsernsMode', 'PidMode', 'UTSMode', 'NanoCpus', 'CpuShares', 'CpusetCpus', 'CpusetMems',
                'OomKillDisable', 'Init', 'ExtraHosts', 'MemoryReservation', 'DeviceCgroupRules', 'StorageOpt',
                'CgroupParent', 'GroupAdd', 'OomScoreAdj', 'KernelMemory', 'KernelMemoryTCP', 'CpuPeriod',
                'CpuRealtimePeriod', 'CpuRealtimeRuntime', 'BlkioWeight', 'BlkioWeightDevice',
                'BlkioDeviceReadBps', 'BlkioDeviceWriteBps', 'BlkioDeviceReadIOps', 'BlkioDeviceWriteIOps',
                'ContainerIDFile'):
        if host.get(key):
            issues.append('Unreviewed control setting: ' + key)
    if host.get('CpuQuota') not in (None, 0, -1) or host.get('PidsLimit') not in (None, 0, -1):
        issues.append('Unexpected resource limits')
    try:
        namespace_modes(previous)
    except RuntimeError as error:
        issues.append(str(error))
    if host.get('Runtime') not in (None, '', 'runc') or host.get('Isolation') not in (None, '', 'default'):
        issues.append('Unexpected runtime or isolation')
    for key in ('MaskedPaths', 'ReadonlyPaths'):
        try:
            protected_paths(host, key)
        except RuntimeError as error:
            issues.append(str(error))
    log = host.get('LogConfig') or {}
    if log.get('Type') not in (None, '', 'json-file') or log.get('Config'):
        issues.append('Unexpected logging configuration')
    if set(host.get('CapDrop') or []) != {'ALL'} or set(host.get('SecurityOpt') or []) != {'no-new-privileges:true'}:
        issues.append('Expected existing control capability/security settings')
    mounts = previous.get('Mounts') or []
    if len(mounts) != 1 or mounts[0]['Type'] != 'bind' or mounts[0]['Destination'] != '/data' or not mounts[0]['RW']:
        issues.append('Expected one existing writable /data bind mount')
    if len(mounts) == 1:
        if Path(mounts[0]['Source']).resolve() != (ROOT / '.local/data').resolve():
            issues.append('Media data mount differs from the existing installation')
        if mounts[0].get('Propagation') not in (None, '', 'rprivate'):
            issues.append('Unexpected data mount propagation')
        expected_bind = mounts[0]['Source'] + ':/data'
        if host.get('Binds') not in (None, [], [expected_bind], [expected_bind + ':rw'],
                                     [expected_bind + ':rprivate'], [expected_bind + ':rw,rprivate']):
            issues.append('Unreviewed bind mount options')
    if host.get('Mounts'):
        issues.append('Structured mount options require an explicit preservation rule')
    config = previous['Config']
    if config.get('OpenStdin') or config.get('Tty') or config.get('StopTimeout') is not None:
        issues.append('Unexpected interactive or custom stop configuration')
    environment = dict(value.split('=', 1) for value in config.get('Env') or [] if '=' in value)
    if environment.get('MEDIA_PUBLIC_IP') != '39.106.212.138' or environment.get('MEDIA_PUBLIC_ORIGIN') != 'https://lingzhiaide.com':
        issues.append('Existing media configuration does not identify the authorized host/domain')
    try:
        host_identity(previous)
    except RuntimeError as error:
        issues.append(str(error))
    if config.get('Image') not in REVIEWED_CONTROL_IMAGES:
        issues.append('Expected the reviewed control image tag')
    try:
        environment_bytes(previous)
    except RuntimeError as error:
        issues.append(str(error))
    if issues:
        raise RuntimeError('Configuration checks failed; no container was changed:\n- ' + '\n- '.join(issues))


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
    issues = []
    try:
        validate_configuration(previous)
    except RuntimeError as error:
        issues.append(str(error))
    source, changed, summary = None, None, None
    try:
        source = docker('exec', previous['Id'], 'cat', '/app/service.mjs')
        try:
            changed = updated_source(source)
        except RuntimeError as error:
            issues.append(str(error))
        host_source = (ROOT / 'service.mjs').read_bytes()
        if host_source != source:
            issues.append('Installed source and running image source differ; review before patching')
    except (RuntimeError, OSError, UnicodeError) as error:
        issues.append('Source inspection failed (' + type(error).__name__ + ')')
    try:
        state = docker('exec', previous['Id'], 'cat', '/data/state.json')
        summary = state_summary(state)
        if summary['activeRecordings']:
            issues.append('Active platform recordings exist; finish them before a control restart')
    except (RuntimeError, ValueError, TypeError) as error:
        issues.append('Media state inspection failed (' + type(error).__name__ + ')')
    if issues:
        raise RuntimeError('Preflight checks failed; no container was changed:\n- ' + '\n- '.join(issues))
    result = {'container': previous['Name'].lstrip('/'), 'containerId': previous['Id'],
              'imageId': previous['Image'], 'sourceSha256': sha(source), 'newSourceSha256': sha(changed),
              'imageTag': previous['Config']['Image'], 'namespaces': namespace_modes(previous),
              'hostIdentityPreserved': True,
              'systemPathProtection': {key: protected_paths(previous['HostConfig'], key)
                                       for key in ('MaskedPaths', 'ReadonlyPaths')},
              'dataDirectory': str(ROOT / '.local/data'), 'state': summary,
              'changes': ['play token 3600 -> 30 seconds', 'expiresAt 3600000 -> 30000 milliseconds'],
              'cutoverGuard': 'create a stopped candidate; require matching protection before stopping the current service',
              'credentialsPrinted': False, 'networkChanged': False}
    return result, previous, source, changed


def environment_bytes(previous):
    values = previous['Config'].get('Env') or []
    keys = set()
    for value in values:
        if not isinstance(value, str) or '=' not in value or any(char in value for char in '\r\n\0'):
            raise RuntimeError('Opaque environment cannot be preserved using a private env file')
        key = value.split('=', 1)[0]
        if not key or key.strip() != key or key.startswith('#') or key in keys:
            raise RuntimeError('Opaque environment contains unsupported or duplicate keys')
        keys.add(key)
    return ('\n'.join(values) + '\n').encode('utf-8')


def run_args(previous, image, environment_file):
    host, config = previous['HostConfig'], previous['Config']
    namespaces = namespace_modes(previous)
    identity = host_identity(previous)
    args = ['run', '-d', '--name', previous['Name'].lstrip('/'), '--network', 'host']
    args += ['--ipc', namespaces['ipc'], '--cgroupns', namespaces['cgroup']]
    args += ['--hostname', identity['Hostname']]
    if identity['Domainname']:
        args += ['--domainname', identity['Domainname']]
    policy = host['RestartPolicy']
    restart = policy['Name'] or 'no'
    if restart == 'on-failure' and policy.get('MaximumRetryCount'):
        restart += ':' + str(policy['MaximumRetryCount'])
    args += ['--restart', restart, '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true']
    if host.get('Runtime'):
        args += ['--runtime', host['Runtime']]
    if host.get('LogConfig', {}).get('Type'):
        args += ['--log-driver', host['LogConfig']['Type']]
    for key, flag in [('PidsLimit', '--pids-limit'), ('CpuQuota', '--cpu-quota')]:
        if host.get(key) is not None:
            args += [flag, str(host[key])]
    for key, flag in [('Memory', '--memory'), ('MemorySwap', '--memory-swap'), ('ShmSize', '--shm-size')]:
        if host.get(key):
            args += [flag, str(host[key])]
    if host.get('MemorySwappiness') is not None:
        args += ['--memory-swappiness', str(host['MemorySwappiness'])]
    mount = previous['Mounts'][0]
    args += ['-v', (host.get('Binds') or [mount['Source'] + ':/data'])[0]]
    args += ['--env-file', str(environment_file)]
    for key, value in (config.get('Labels') or {}).items():
        args += ['--label', key + '=' + value]
    for key, flag in [('User', '--user'), ('WorkingDir', '--workdir'), ('StopSignal', '--stop-signal')]:
        if config.get(key):
            args += [flag, config[key]]
    return args + [image] + (config.get('Cmd') or [])


def same_empty_host_list(key, left, right):
    def empty(value):
        return value is None or (isinstance(value, list) and len(value) == 0)
    return key in OPTIONAL_HOST_LISTS and empty(left) and empty(right)


def value_shape(value):
    if value is None:
        return 'null'
    if isinstance(value, (list, dict)):
        return type(value).__name__ + '(' + str(len(value)) + ')'
    return type(value).__name__


def verify_configuration(previous, current):
    differences = []
    # Only the intended image and CLI stream attachment may differ.
    # Hostname and domain name are explicit and must remain unchanged.
    # Unknown configuration fields are compared rather than silently ignored.
    for key in sorted(set(previous['Config']) | set(current['Config'])):
        if key in ('Image', 'AttachStdout', 'AttachStderr'):
            continue
        a, b = previous['Config'].get(key), current['Config'].get(key)
        if key == 'Env':
            a, b = sorted(a or []), sorted(b or [])
        if a != b:
            differences.append('Config.' + key)
    for key in sorted(set(previous['HostConfig']) | set(current['HostConfig'])):
        if key in ('MaskedPaths', 'ReadonlyPaths'):
            continue
        left, right = previous['HostConfig'].get(key), current['HostConfig'].get(key)
        if same_empty_host_list(key, left, right):
            continue
        if left != right:
            differences.append('HostConfig.' + key + ' [' + value_shape(left) + ' -> ' + value_shape(right) + ']')
    for key in ('MaskedPaths', 'ReadonlyPaths'):
        if protected_paths(previous['HostConfig'], key) != protected_paths(current['HostConfig'], key):
            differences.append('HostConfig.' + key)
    for a, b in zip(previous['Mounts'], current['Mounts']):
        if a != b:
            differences.append('Mounts')
    if len(previous['Mounts']) != len(current['Mounts']):
        differences.append('MountCount')
    if differences:
        raise RuntimeError('Preserved container settings differ: ' + ', '.join(differences))


def create_args(previous, image, name, environment_file):
    args = ['create'] + run_args(previous, image, environment_file)[2:]
    args[args.index('--name') + 1] = name
    return args


def verify_stopped_candidate(previous, candidate, image, candidate_id):
    if (candidate['Id'] != candidate_id or candidate['Image'] != image
            or candidate['State'].get('Running') is not False
            or candidate['State'].get('Status') != 'created'):
        raise RuntimeError('Candidate identity/state changed; no live cutover attempted')
    verify_configuration(previous, candidate)


def prepare_candidate(previous, image, directory, record, expected_source):
    record.update(status='candidate-preparing',
                  candidateContainer=record['container'] + '-candidate-' + directory.name.rsplit('-', 1)[-1])
    private_write(directory / 'receipt.json', record)
    try:
        environment_file = directory / 'container.private.env'
        private_write(environment_file, environment_bytes(previous))
        candidate_id = docker(*create_args(previous, image, record['candidateContainer'], environment_file)).decode().strip()
        if len(candidate_id) != 64 or any(char not in '0123456789abcdef' for char in candidate_id):
            raise RuntimeError('Docker did not return an unambiguous candidate ID')
        record['candidateId'] = candidate_id
        private_write(directory / 'receipt.json', record)
        verify_stopped_candidate(previous, inspect(candidate_id), image, candidate_id)
        fresh, actual, _, _ = preview()
        if actual['Id'] != previous['Id'] or fresh['sourceSha256'] != expected_source:
            raise RuntimeError('Current service or source changed during preparation')
        verify_configuration(previous, actual)
        verify_stopped_candidate(previous, inspect(candidate_id), image, candidate_id)
        record['status'] = 'candidate-verified'
        private_write(directory / 'receipt.json', record)
        return candidate_id
    except Exception as error:
        record.update(status='candidate-rejected-live-unchanged', failureType=type(error).__name__)
        try:
            private_write(directory / 'receipt.json', record)
        except OSError:
            pass
        raise RuntimeError('Stopped candidate preflight failed; current service was not stopped. ' + str(error)) from None


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
        if current['Id'] != (record.get('candidateId') or record.get('currentContainerId')):
            raise RuntimeError('Current service identity changed; unrelated container was not stopped')
        if current['State']['Running']:
            docker('stop', '--time', '30', current['Id'])
        docker('rename', current['Id'], record['failedContainer'])
        current = None
    if current is None:
        if inspect(retained)['Id'] != previous['Id']:
            raise RuntimeError('Retained predecessor changed; media data was not restored')
        docker('rename', previous['Id'], name)
    docker('start', previous['Id'])
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
    record = dict(plan, status='prepared', imageId=new_image, oldImageId=previous['Image'], backupDirectory=str(directory),
                  retainedContainer=plan['container'] + '-before-' + stamp,
                  failedContainer=plan['container'] + '-failed-' + stamp, dataRestored=False)
    candidate_id = prepare_candidate(previous, new_image, directory, record, expected_source)
    verify_stopped_candidate(previous, inspect(candidate_id), new_image, candidate_id)
    if inspect(plan['container'])['Id'] != previous['Id']:
        raise RuntimeError('Current service identity changed before cutover; current service was not stopped')
    try:
        docker('stop', '--time', '30', previous['Id'])
        if inspect(previous['Id'])['State']['Running']:
            raise RuntimeError('Old control did not stop')
        state_path = ROOT / '.local/data/state.json'
        state = state_path.read_bytes()
        private_write(directory / 'state-before.private.json', state)
        if state_summary(state)['activeRecordings']:
            raise RuntimeError('Recording appeared before cutover; retaining predecessor')
        files = [{'path': str(path.relative_to(ROOT / '.local/data')), 'bytes': path.stat().st_size}
                 for path in (ROOT / '.local/data').rglob('*') if path.is_file()]
        private_write(directory / 'media-file-inventory.private.json', files)
        docker('rename', previous['Id'], record['retainedContainer'])
        docker('rename', candidate_id, plan['container'])
        docker('start', candidate_id)
        healthy()
        current = inspect(plan['container'])
        if (current['Id'] != candidate_id or current['Image'] != new_image
                or current['State'].get('Running') is not True
                or current['State'].get('Status') != 'running'):
            raise RuntimeError('Running service no longer matches the verified candidate')
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
            with mutation_lock():
                result = apply(args.expected_image, args.expected_source)
        else:
            if not args.backup_directory:
                raise RuntimeError('Rollback requires the backup directory printed by apply')
            with mutation_lock():
                result = rollback(args.backup_directory)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
