#!/usr/bin/env python3
"""Bounded operations for this isolated Compose project; never prints configuration secrets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
COMPOSE = ['docker', 'compose', '--project-directory', str(ROOT), '--env-file', str(ROOT / '.env'), '-f', str(ROOT / 'compose.yml')]

def call(args, *, capture=False, timeout=120, env=None):
    return subprocess.run(args, cwd=ROOT, check=True, text=True, encoding='utf-8',
                          stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE,
                          timeout=timeout, env=env).stdout

def configuration(lab=False):
    private = ROOT / 'private'
    if (private / '.gateway-config.incomplete').exists():
        raise ValueError('Gateway configuration replacement is incomplete. Restore or reconcile the entire generation before starting services.')
    manifest = json.loads((private / 'gateway-manifest.json').read_text(encoding='utf-8'))
    generation = str(uuid.UUID(manifest['generation']))
    required = {'helmet-a.json', 'helmet-b.json', 'belt-a.json', 'belt-b.json', 'Caddy.devices'}
    if set(manifest.get('files', {})) != required:
        raise ValueError('Gateway configuration generation manifest is incomplete.')
    for name, digest in manifest['files'].items():
        path = private / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('Gateway configuration generation is mixed or modified; regenerate all paired files together.')
    os.environ['GATEWAY_CONFIG_GENERATION'] = generation
    config = json.loads(call(COMPOSE + ['config', '--format', 'json'], capture=True))
    services = config['services']
    apps = [services['app-a'], services['app-b']]
    identities = [app['environment'].get('MELHAT_CLUSTER_NODE_ID', '') for app in apps]
    if len(set(identities)) != 2 or any(not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', item) for item in identities):
        raise ValueError('Each application needs its own stable node identity.')
    for app in apps:
        env = app['environment']
        if env.get('MELHAT_DB_PRODUCT') not in ('dm8', 'mysql'):
            raise ValueError('MELHAT_DB_PRODUCT must be dm8 or mysql.')
        for key in ('MELHAT_DB_URL', 'MELHAT_DB_USERNAME', 'MELHAT_DB_PASSWORD', 'CLUSTER_REDIS_HOST',
                    'CLUSTER_REDIS_PASSWORD', 'JWT_SECRET', 'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY', 'MELHAT_FILES_STORE_ID'):
            if not env.get(key):
                raise ValueError('Backend private configuration has a missing required value.')
        if not re.fullmatch(r'[A-Za-z0-9_-]{43}', env.get('MELHAT_CLUSTER_ADMIN_TOKEN', '')):
            raise ValueError('Backend requires a private 32-byte cluster management token.')
    for service in ('app-a', 'app-b', 'helmet-a', 'helmet-b', 'belt-a', 'belt-b', 'ingress'):
        image = services[service]['image']
        if not lab and not re.search(r'(?:@|^)sha256:[0-9a-f]{64}$', image):
            raise ValueError('Production images must be pinned to a tested digest or immutable image ID.')
    for node in ('a', 'b'):
        for kind in ('helmet', 'belt'):
            gateway = json.loads((ROOT / 'private' / f'{kind}-{node}.json').read_text(encoding='utf-8'))
            if gateway['adminToken'] != apps[0]['environment']['MELHAT_CLUSTER_ADMIN_TOKEN']:
                raise ValueError('Backend and gateway management credentials must match.')
            if gateway['upstreamOrigin'] != f'http://app-{node}:18084':
                raise ValueError('Gateway is not paired to its own application.')
    sources = [next(v['source'] for v in app['volumes'] if v['target'] == '/shared') for app in apps]
    if sources[0] != sources[1] or not Path(sources[0]).is_absolute() or Path(sources[0]) == Path('/'):
        raise ValueError('Both nodes must mount the same dedicated absolute shared directory.')
    return config

def generation_window():
    current = os.environ['GATEWAY_CONFIG_GENERATION']
    running = call(COMPOSE + ['ps', '--services', '--filter', 'status=running'], capture=True).splitlines()
    changed = False
    evidence = False
    for service in ('helmet-a', 'helmet-b', 'belt-a', 'belt-b', 'ingress'):
        # Stopping a container must not erase evidence of its previous generation.
        container = call(COMPOSE + ['ps', '--all', '-q', service], capture=True).strip()
        if not container:
            continue
        evidence = True
        loaded = call(['docker', 'inspect', '--format', '{{index .Config.Labels "org.wearable.gateway-generation"}}', container], capture=True).strip()
        changed |= loaded != current
    if (changed or not evidence) and any(service in running for service in ('app-a', 'app-b', 'helmet-a', 'helmet-b', 'belt-a', 'belt-b')):
        raise ValueError('Gateway generation changed. Drain and stop both node groups before applying the complete generation, including ingress.')

def verify_loaded_generation():
    manifest = json.loads((ROOT / 'private' / 'gateway-manifest.json').read_text(encoding='utf-8'))
    for service in ('helmet-a', 'helmet-b', 'belt-a', 'belt-b', 'ingress'):
        container = call(COMPOSE + ['ps', '-q', service], capture=True).strip()
        loaded = call(['docker', 'inspect', '--format', '{{index .Config.Labels "org.wearable.gateway-generation"}}', container], capture=True).strip()
        if loaded != manifest['generation']:
            raise ValueError('A running gateway or ingress still has the previous configuration generation.')
        if service == 'ingress':
            actual = call(COMPOSE + ['exec', '-T', service, 'sha256sum', '/etc/caddy/Caddy.devices'], capture=True).split()[0]
            filename = 'Caddy.devices'
        else:
            filename = service + '.json'
            code = "console.log(require('node:crypto').createHash('sha256').update(require('node:fs').readFileSync(process.argv[1])).digest('hex'))"
            actual = call(COMPOSE + ['exec', '-T', service, 'node', '-e', code, '/run/private/' + filename], capture=True).strip()
        if actual != manifest['files'][filename]:
            raise ValueError('A running container has a stale configuration mount; do not reopen the device entry.')
    print('All four gateways and ingress loaded the same verified configuration generation.')

def preflight(config, lab):
    app = config['services']['app-a']
    source = next(v['source'] for v in app['volumes'] if v['target'] == '/shared')
    env = dict(os.environ, SHARED_FILES_DIR=str(Path(source) / 'files'),
               MELHAT_FILES_STORE_ID=app['environment']['MELHAT_FILES_STORE_ID'])
    call(['bash', str(ROOT / 'kylin-preflight.sh')] + (['--lab'] if lab else []), env=env)

# The private token stays inside the gateway container; never appears in argv or logs.
MANAGE = r"""
const fs=require('node:fs'); const config=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
const target=process.argv[2],method=process.argv[3],backend=process.argv[4]==='backend';
fetch((backend?config.upstreamOrigin:'http://127.0.0.1:8080')+target,{method,
 headers:{'X-Cluster-Admin-Token':config.adminToken},signal:AbortSignal.timeout(4000),redirect:'error'})
 .then(async r=>{if(!r.ok)throw Error();const body=await r.json();console.log(JSON.stringify({
  accepted:body.accepted===true,draining:body.draining===true,quiescent:body.quiescent===true,
  activeWrites:Number.isSafeInteger(body.activeWrites)?body.activeWrites:null}));})
 .catch(()=>{console.error('Management request failed.');process.exitCode=1;});
"""

def manage(node, target, method='GET', backend=True, kind='helmet'):
    service = f'{kind}-{node}'
    value = call(COMPOSE + ['exec', '-T', service, 'node', '-e', MANAGE,
                           f'/run/private/{service}.json', target, method, 'backend' if backend else 'gateway'],
                 capture=True, timeout=10)
    return json.loads(value)

def drain(node, timeout):
    result = manage(node, '/internal/cluster/drain', 'POST')
    if not result['draining']:
        raise ValueError('Backend did not confirm node drain.')
    # Health interval is two seconds. Existing requests finish under the backend permits.
    time.sleep(3)
    for kind in ('helmet', 'belt'):
        if not manage(node, '/internal/gateway/drain', 'POST', False, kind)['draining']:
            raise ValueError('Gateway did not confirm node drain.')
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = manage(node, '/internal/cluster/drain')
        if result['draining'] and result['quiescent']:
            print(f'Node {node}: drain complete; no unconfirmed work reported.')
            return
        time.sleep(1)
    raise ValueError('Drain did not become quiescent. Keep the node running and reconcile in-flight/unknown work; no forced stop was issued.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lab', action='store_true', help='Local validation only; never certifies Kylin/NFS')
    parser.add_argument('command', choices=['check', 'migrate', 'up', 'status', 'logs', 'drain', 'stop', 'restart'])
    parser.add_argument('--node', choices=['a', 'b'])
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    if not 10 <= args.timeout <= 300:
        parser.error('timeout must be between 10 and 300 seconds')
    if args.command in ('drain', 'stop', 'restart') and not args.node:
        parser.error('drain, stop and restart require one explicit --node')
    config = configuration(args.lab)
    if args.command in ('up', 'restart'):
        generation_window()
    if args.command in ('check', 'up', 'restart'):
        preflight(config, args.lab)
    if args.command == 'check':
        print('Configuration and host prerequisites passed; business acceptance is separate.')
    elif args.command == 'migrate':
        running = call(COMPOSE + ['ps', '--services', '--filter', 'status=running'], capture=True).splitlines()
        if any(name in running for name in ('app-a', 'app-b')):
            raise ValueError('Schema migration requires both application nodes stopped after drain.')
        call(COMPOSE + ['--profile', 'tools', 'run', '--rm', 'migrate'], timeout=300)
    elif args.command == 'up':
        call(COMPOSE + ['up', '-d', '--wait', '--wait-timeout', str(args.timeout)], timeout=args.timeout + 30)
        verify_loaded_generation()
    elif args.command == 'status':
        call(COMPOSE + ['ps'])
    elif args.command == 'logs':
        # Diagnostic logs may contain business data; output only on explicit request.
        call(COMPOSE + ['logs', '--no-color', '--tail', '100'] + ([f'app-{args.node}', f'helmet-{args.node}', f'belt-{args.node}'] if args.node else []))
    else:
        drain(args.node, args.timeout)
        if args.command in ('stop', 'restart'):
            services = [f'helmet-{args.node}', f'belt-{args.node}', f'app-{args.node}']
            call(COMPOSE + ['stop', '--timeout', '40'] + services, timeout=150)
            if args.command == 'restart':
                call(COMPOSE + ['up', '-d', '--wait', '--wait-timeout', str(args.timeout)] + services, timeout=args.timeout + 30)
                verify_loaded_generation()

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        # Docker/config/parser exceptions may embed environment secrets. Never print their text.
        if type(error) is ValueError:
            print(str(error), file=sys.stderr)
        else:
            print('Operation failed. Inspect the protected local logs/configuration; no destructive fallback was attempted.', file=sys.stderr)
        sys.exit(1)
