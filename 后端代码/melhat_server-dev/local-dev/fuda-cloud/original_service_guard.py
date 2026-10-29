"""Read-only baseline/comparison of existing containers, compatible with Python 3.6.

Only the exact fuda-wearables-staging project is excluded. This tool never starts,
stops, removes or modifies a container. It stores no Env, Cmd, names, addresses,
raw mount paths or credentials. Private evidence files are new, mode 0600 files.
"""
from __future__ import print_function
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

STAGING_PROJECT = 'fuda-wearables-staging'
FIELDS = ('startedAt', 'restartCount', 'running', 'status', 'health', 'oomKilled',
          'portConfigSha256', 'mountConfigSha256')


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')


def fingerprint(value):
    data = json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return hashlib.sha256(data).hexdigest()


def docker_read(args):
    # Fixed local daemon and only two supported read operations; no user-supplied Docker args.
    if args != ['ps', '-aq'] and not (args and args[0] == 'inspect'
            and len(args) > 1 and all(re.fullmatch(r'[0-9a-f]{12,64}', x) for x in args[1:])):
        raise ValueError('Unsupported Docker observation')
    env = dict(os.environ)
    for name in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
        env.pop(name, None)
    result = subprocess.run(['docker', '--host', 'unix:///var/run/docker.sock'] + args,
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if result.returncode:
        raise RuntimeError('Docker read-only observation failed; details suppressed')
    return result.stdout


def project(info):
    return ((info.get('Config') or {}).get('Labels') or {}).get('com.docker.compose.project')


def safe_container(info):
    identifier = info.get('Id', '')
    if not re.fullmatch(r'[0-9a-f]{64}', identifier):
        raise ValueError('Unexpected container identity')
    config, host, network, state = (info.get(key) or {} for key in ('Config', 'HostConfig', 'NetworkSettings', 'State'))
    # Hash effective and configured ports, including host-network selection. No raw values persist.
    ports = {'networkMode': host.get('NetworkMode'), 'published': network.get('Ports'),
             'bindings': host.get('PortBindings'), 'exposed': config.get('ExposedPorts'),
             'publishAllPorts': host.get('PublishAllPorts')}
    mounts = {'effective': sorted(info.get('Mounts') or [], key=lambda row: str(row.get('Destination', ''))),
              'binds': sorted(host.get('Binds') or []), 'configured': host.get('Mounts'),
              'tmpfs': host.get('Tmpfs'), 'volumesFrom': sorted(host.get('VolumesFrom') or [])}
    return {'id': identifier, 'startedAt': state.get('StartedAt'),
            'restartCount': info.get('RestartCount', 0), 'running': bool(state.get('Running')),
            'status': state.get('Status'), 'health': (state.get('Health') or {}).get('Status'),
            'oomKilled': bool(state.get('OOMKilled')),
            'portConfigSha256': fingerprint(ports), 'mountConfigSha256': fingerprint(mounts)}


def observe():
    ids = docker_read(['ps', '-aq']).decode('ascii').split()
    # Bound one request at a time for hosts with many containers; no mutation can occur here.
    rows = []
    for offset in range(0, len(ids), 64):
        rows.extend(json.loads(docker_read(['inspect'] + ids[offset:offset + 64]).decode('utf-8')))
    result, excluded = {}, 0
    for info in rows:
        if project(info) == STAGING_PROJECT:
            excluded += 1
            continue
        row = safe_container(info)
        if row['id'] in result:
            raise ValueError('Duplicate observed container identity')
        result[row['id']] = row
    return {'formatVersion': 1, 'kind': 'original-container-snapshot', 'observedAt': stamp(),
            'excludedProject': STAGING_PROJECT, 'excludedStagingCount': excluded, 'containers': result}


def validate_snapshot(value):
    if not isinstance(value, dict) or value.get('formatVersion') != 1 \
            or value.get('kind') != 'original-container-snapshot' \
            or value.get('excludedProject') != STAGING_PROJECT or not isinstance(value.get('containers'), dict):
        raise ValueError('Unsupported baseline evidence')
    for identifier, row in value['containers'].items():
        if not re.fullmatch(r'[0-9a-f]{64}', identifier) or not isinstance(row, dict) \
                or row.get('id') != identifier or any(key not in row for key in FIELDS):
            raise ValueError('Invalid baseline container evidence')
    return value


def compare(before, after):
    validate_snapshot(before)
    validate_snapshot(after)
    old, current = before['containers'], after['containers']
    removed, added = sorted(set(old) - set(current)), sorted(set(current) - set(old))
    changed = {}
    for identifier in sorted(set(old) & set(current)):
        differences = [key for key in FIELDS if old[identifier][key] != current[identifier][key]]
        if differences:
            changed[identifier] = differences
    # Even improvements are recorded as changes; do not claim original services were unchanged.
    summary = {'readOnly': True, 'unchanged': not (removed or added or changed),
               'baselineContainers': len(old), 'currentContainers': len(current),
               'removedCount': len(removed), 'addedCount': len(added), 'changedCount': len(changed),
               'excludedStagingCount': after.get('excludedStagingCount', 0)}
    return {'formatVersion': 1, 'kind': 'original-container-comparison', 'comparedAt': stamp(),
            'summary': summary, 'removedIds': removed, 'addedIds': added,
            'changedFields': changed, 'currentSnapshot': after}


def private_read(path):
    file = Path(path)
    if file.is_symlink() or not file.is_file():
        raise ValueError('Baseline must be a regular private file')
    if os.name == 'posix' and file.stat().st_mode & 0o077:
        raise ValueError('Baseline requires mode 0600')
    return json.loads(file.read_text(encoding='utf-8'))


def private_write_new(path, value):
    file = Path(path)
    file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with os.fdopen(os.open(str(file), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600),
                   'w', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=True, sort_keys=True, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command')
    sub.required = True
    snapshot = sub.add_parser('snapshot')
    snapshot.add_argument('--output', required=True)
    comparison = sub.add_parser('compare')
    comparison.add_argument('--baseline', required=True)
    comparison.add_argument('--output', required=True)
    args = parser.parse_args()
    # Fail before Docker reads when an evidence path would overwrite an earlier result.
    if os.path.lexists(args.output):
        raise ValueError('Output evidence already exists; choose a new file')
    if args.command == 'snapshot':
        current = observe()
        private_write_new(args.output, current)
        print(json.dumps({'event': 'original_baseline_saved', 'readOnly': True,
                          'originalContainers': len(current['containers']),
                          'excludedStagingCount': current['excludedStagingCount']}))
        return 0
    before = validate_snapshot(private_read(args.baseline))
    result = compare(before, observe())
    private_write_new(args.output, result)
    print(json.dumps(result['summary'], sort_keys=True))
    return 0 if result['summary']['unchanged'] else 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({'event': 'original_guard_error', 'errorType': type(error).__name__,
                          'detailsSuppressed': True, 'containersModified': False}), file=sys.stderr)
        sys.exit(2)
