#!/usr/bin/env python3
"""Bounded operations for this isolated Compose project; never prints configuration secrets."""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import tempfile
import uuid
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
COMPOSE = ['docker', 'compose', '--project-directory', str(ROOT), '--env-file', str(ROOT / '.env'), '-f', str(ROOT / 'compose.yml')]
PRIVATE = ROOT / 'private'
SHARED_ENTRY_SERVICES = ('wear-api', 'fuda-api', 'backend-router', 'ingress')
ENTRY_SERVICES = ('helmet-a', 'helmet-b', 'belt-a', 'belt-b', *SHARED_ENTRY_SERVICES)

def validate_entry(services):
    for service in ('app-a', 'app-b', *ENTRY_SERVICES[:-1]):
        if services[service].get('ports'):
            raise ValueError('Only ingress may publish a host port; backend and gateways must remain private.')
    for key in ('PC_STATIC_UPSTREAM', 'MEDIA_UPSTREAM', 'SIP_UPSTREAM'):
        value = services['ingress']['environment'].get(key, '')
        match = re.fullmatch(r'([a-zA-Z0-9.-]+):([0-9]{1,5})', value)
        if not match or not 1 <= int(match[2]) <= 65535:
            raise ValueError('Entry dependencies require explicit private host:port values.')
        host = match[1].lower()
        try:
            private = ipaddress.ip_address(host).is_private
        except ValueError:
            private = bool(re.fullmatch(r'[a-z][a-z0-9-]{0,62}', host))
        if not private or host in {'backend', 'backend-router', 'app-a', 'app-b', 'wear-api', 'fuda-api', 'ingress', 'localhost'}:
            raise ValueError('Static/media/SIP entries require their independent private services, never an application/router fallback.')

def call(args, *, capture=False, timeout=120, env=None):
    return subprocess.run(args, cwd=ROOT, check=True, text=True, encoding='utf-8',
                          stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE,
                          timeout=timeout, env=env).stdout

def configuration(lab=False, *, inventory=None):
    global COMPOSE, PRIVATE
    COMPOSE = ['docker', 'compose', '--project-directory', str(ROOT), '--env-file', str(ROOT / ('.lab.env' if lab else '.env')), '-f', str(ROOT / 'compose.yml')]
    if lab:
        COMPOSE.extend(['-f', str(ROOT / 'compose.lab.yml')])
    PRIVATE = ROOT / 'private' / 'lab' if lab else ROOT / 'private'
    private = PRIVATE
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
    validate_entry(services)
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
    for service in ('app-a', 'app-b', *ENTRY_SERVICES):
        image = services[service]['image']
        if not lab and not re.search(r'(?:@|^)sha256:[0-9a-f]{64}$', image):
            raise ValueError('Production images must be pinned to a tested digest or immutable image ID.')
    for node in ('a', 'b'):
        for kind in ('helmet', 'belt'):
            gateway = json.loads((private / f'{kind}-{node}.json').read_text(encoding='utf-8'))
            if gateway['adminToken'] != apps[0]['environment']['MELHAT_CLUSTER_ADMIN_TOKEN']:
                raise ValueError('Backend and gateway management credentials must match.')
            if gateway['upstreamOrigin'] != f'http://app-{node}:18084':
                raise ValueError('Gateway is not paired to its own application.')
    sources = [next(v['source'] for v in app['volumes'] if v['target'] == '/shared') for app in apps]
    if sources[0] != sources[1] or not Path(sources[0]).is_absolute() or Path(sources[0]) == Path('/'):
        raise ValueError('Both nodes must mount the same dedicated absolute shared directory.')
    if lab:
        validate_lab_dependencies(config, private, inventory)
    return config

def container_identity(container):
    # Only identity/network metadata, never Config.Env or credentials.
    template = '{"id":{{json .Id}},"name":{{json .Name}},"networks":{{json .NetworkSettings.Networks}}}'
    return json.loads(call(['docker', 'inspect', '--format', template, container], capture=True))

def validate_lab_dependencies(config, private, inventory=None):
    manifest = inventory if inventory is not None else json.loads((private / 'isolation.json').read_text(encoding='utf-8'))
    project = config['name']
    network = config['networks']['cluster']['name']
    if not re.fullmatch(r'wearable-lab-[a-z0-9-]+', project) or not re.fullmatch(r'wearable-lab-[a-z0-9-]+', network):
        raise ValueError('Laboratory mode requires independent wearable-lab-* project and network names.')
    if manifest['project'] != project or manifest['network']['name'] != network:
        raise ValueError('Laboratory project/network do not match the independently prepared inventory.')
    network_id = call(['docker', 'network', 'inspect', '--format', '{{.Id}}', network], capture=True).strip()
    if network_id != manifest['network']['id']:
        raise ValueError('Laboratory network identity changed.')
    env = config['services']['app-a']['environment']
    if hashlib.sha256((private / 'backend.env').read_bytes()).hexdigest() != manifest['backendEnvSha256']:
        raise ValueError('Laboratory backend configuration differs from its verified inventory.')
    if hashlib.sha256((private / 'Caddy.lab').read_bytes()).hexdigest() != manifest['entrySha256']:
        raise ValueError('Laboratory entry differs from its verified inventory.')
    db = urlsplit(env['MELHAT_DB_URL'].removeprefix('jdbc:'))
    schema = env['MELHAT_DB_USERNAME'] if env['MELHAT_DB_PRODUCT'] == 'dm8' else db.path.lstrip('/')
    if db.scheme != ('dm' if env['MELHAT_DB_PRODUCT'] == 'dm8' else 'mysql') or schema != manifest['database']['schema']:
        raise ValueError('Laboratory database/schema differs from the verified inventory.')
    dependencies = {}
    for kind, host in [('database', db.hostname), ('redis', env['CLUSTER_REDIS_HOST'])]:
        expected = manifest[kind]['containerId']
        if not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('Laboratory inventory requires immutable dependency container IDs.')
        actual = container_identity(expected)
        name = actual['name'].lstrip('/')
        if actual['id'] != expected or not (name.startswith('wearable-lab-') or name.startswith('wearable-') and name.endswith('-lab')):
            raise ValueError('Laboratory dependency is not the designated isolated container.')
        attachment = actual['networks'].get(network)
        if not attachment or attachment['NetworkID'] != network_id:
            raise ValueError('Laboratory dependency is outside the verified network.')
        hosts = {name, attachment.get('IPAddress'), *(attachment.get('Aliases') or []), *(attachment.get('DNSNames') or [])}
        if host not in hosts:
            raise ValueError('Backend host resolves outside the designated laboratory dependency.')
        dependencies[kind] = actual
    if int(env.get('CLUSTER_REDIS_DATABASE', 0)) != manifest['redis']['database']:
        raise ValueError('Laboratory Redis database differs from its inventory.')
    shared = next(v['source'] for v in config['services']['app-a']['volumes'] if v['target'] == '/shared')
    if str(Path(shared).resolve()) != str(Path(manifest['sharedDirectory']).resolve()) or env['MELHAT_FILES_STORE_ID'] != manifest['storeId']:
        raise ValueError('Laboratory shared storage differs from its inventory.')
    # If a normal deployment is configured here, compare actual dependencies as well as names.
    if (ROOT / '.env').exists() or (ROOT / 'private' / 'backend.env').exists():
        production = json.loads(call(['docker', 'compose', '--project-directory', str(ROOT), '--env-file', str(ROOT / '.env'),
                                     '-f', str(ROOT / 'compose.yml'), 'config', '--format', 'json'], capture=True))
        normal = production['services']['app-a']
        normal_env = normal['environment']
        normal_shared = next(v['source'] for v in normal['volumes'] if v['target'] == '/shared')
        normal_db = urlsplit(normal_env['MELHAT_DB_URL'].removeprefix('jdbc:'))
        normal_hosts = [normal_db.hostname, normal_env['CLUSTER_REDIS_HOST']]
        for kind, host in zip(('database', 'redis'), normal_hosts):
            actual = dependencies[kind]
            aliases = {actual['name'].lstrip('/')}
            for attachment in actual['networks'].values():
                aliases.update(attachment.get('Aliases') or [])
                aliases.update(attachment.get('DNSNames') or [])
                aliases.add(attachment.get('IPAddress'))
            if host in aliases:
                raise ValueError('Laboratory cannot share the normal database or Redis container, even through another alias.')
        if production['name'] == project or production['networks']['cluster']['name'] == network \
                or Path(normal_shared).resolve() == Path(shared).resolve() \
                or normal_env['MELHAT_FILES_STORE_ID'] == env['MELHAT_FILES_STORE_ID']:
            raise ValueError('Laboratory cannot reuse normal project/network/shared storage identities.')

def generation_window():
    current = os.environ['GATEWAY_CONFIG_GENERATION']
    running = call(COMPOSE + ['ps', '--services', '--filter', 'status=running'], capture=True).splitlines()
    changed = False
    evidence = False
    for service in ENTRY_SERVICES:
        # Stopping a container must not erase evidence of its previous generation.
        container = call(COMPOSE + ['ps', '--all', '-q', service], capture=True).strip()
        if not container:
            continue
        evidence = True
        loaded = call(['docker', 'inspect', '--format', '{{index .Config.Labels "org.wearable.gateway-generation"}}', container], capture=True).strip()
        changed |= loaded != current
    if (changed or not evidence) and any(service in running for service in ('app-a', 'app-b', 'helmet-a', 'helmet-b', 'belt-a', 'belt-b')):
        raise ValueError('Gateway generation changed. Drain and stop both node groups before applying the complete generation, including ingress.')

def verify_loaded_generation(restart_node=None):
    manifest = json.loads((PRIVATE / 'gateway-manifest.json').read_text(encoding='utf-8'))
    # Only the other node's device gateways may be stopped during a targeted start or restart.
    peer = {'a': 'b', 'b': 'a'}.get(restart_node)
    optional = (f'helmet-{peer}', f'belt-{peer}') if peer else ()
    for service in ENTRY_SERVICES:
        container = call(COMPOSE + ['ps', '-q', service], capture=True).strip()
        if not container:
            if service in optional:
                continue
            raise ValueError(f'Required gateway or entry service is not running: {service}.')
        loaded = call(['docker', 'inspect', '--format', '{{index .Config.Labels "org.wearable.gateway-generation"}}', container], capture=True).strip()
        if loaded != manifest['generation']:
            raise ValueError('A running gateway or ingress still has the previous configuration generation.')
        if service in ('wear-api', 'fuda-api'):
            continue  # Fixed image entrypoint; no per-device configuration mount.
        if service in ('backend-router', 'ingress'):
            source = ROOT / 'Caddy.backend' if service == 'backend-router' else (PRIVATE / 'Caddy.lab' if PRIVATE.name == 'lab' else ROOT / 'Caddyfile')
            actual_config = call(COMPOSE + ['exec', '-T', service, 'sha256sum', '/etc/caddy/Caddyfile'], capture=True).split()[0]
            if actual_config != hashlib.sha256(source.read_bytes()).hexdigest():
                raise ValueError('The running entry/router has a stale configuration mount. Recreate it in the maintenance window.')
            if service == 'backend-router':
                continue
        if service == 'ingress':
            actual = call(COMPOSE + ['exec', '-T', service, 'sha256sum', '/etc/caddy/Caddy.devices'], capture=True).split()[0]
            filename = 'Caddy.devices'
        else:
            filename = service + '.json'
            code = "console.log(require('node:crypto').createHash('sha256').update(require('node:fs').readFileSync(process.argv[1])).digest('hex'))"
            actual = call(COMPOSE + ['exec', '-T', service, 'node', '-e', code, '/run/private/' + filename], capture=True).strip()
        if actual != manifest['files'][filename]:
            raise ValueError('A running container has a stale configuration mount; do not reopen the device entry.')
    print('Running device gateways, API gateways, private router and ingress loaded the verified generation and configuration mounts.')

def local_shared_probe(root, store_id):
    root = Path(root)
    if not root.is_absolute() or root == Path(root.anchor) or not root.is_dir() or root.is_symlink() or getattr(root, 'is_junction', lambda: False)():
        raise ValueError('Laboratory shared directory must be an existing dedicated directory, not a link.')
    marker = root / '.wearable-store-id'
    if str(uuid.UUID(store_id)) != store_id or marker.is_symlink() or not marker.is_file() or marker.read_bytes() != (store_id + '\n').encode('ascii'):
        raise ValueError('Laboratory shared store identity is missing or differs.')
    source = target = None
    try:
        fd, source = tempfile.mkstemp(prefix='.wearable-preflight-', dir=root)
        data = os.urandom(4096)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        target = root / ('.wearable-preflight-' + uuid.uuid4().hex)
        os.replace(source, target)
        if target.read_bytes() != data:
            raise ValueError('Laboratory shared file readback differs.')
    finally:
        for file in (source, target):
            if file is not None:
                Path(file).unlink(missing_ok=True)

def preflight(config, lab):
    app = config['services']['app-a']
    source = next(v['source'] for v in app['volumes'] if v['target'] == '/shared')
    if os.name == 'nt':
        if not lab:
            raise ValueError('Production preflight requires the actual Kylin Linux host.')
        info = json.loads(call(['docker', 'info', '--format', '{"os":{{json .OSType}},"arch":{{json .Architecture}}}'], capture=True))
        if info != {'os': 'linux', 'arch': 'x86_64'}:
            raise ValueError('Laboratory containers require Linux x86_64.')
        call(['docker', 'compose', 'version'])
        local_shared_probe(Path(source) / 'files', app['environment']['MELHAT_FILES_STORE_ID'])
        print('PASS: Windows laboratory file create/flush/rename/readback. Application UID access is checked by readiness; Kylin/NFS remain pending.')
        return
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
    parser.add_argument('--node', choices=['a', 'b'], help='For up, start one node group and the shared entry without starting its peer.')
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
        # Applications need JVM startup time; existing unready edge containers must
        # not make Compose abort before their dependencies have become healthy.
        up = COMPOSE + ['up', '-d', '--wait', '--wait-timeout', str(args.timeout)]
        if args.node:
            # Explicit targets and --no-deps keep a stopped peer out of both stages.
            up += ['--no-deps']
            apps = [f'app-{args.node}']
            entry = [f'helmet-{args.node}', f'belt-{args.node}', *SHARED_ENTRY_SERVICES]
        else:
            apps = ['app-a', 'app-b']
            entry = []
        call(up + apps, timeout=args.timeout + 30)
        call(up + entry, timeout=args.timeout + 30)
        verify_loaded_generation(restart_node=args.node)
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
                verify_loaded_generation(restart_node=args.node)

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
