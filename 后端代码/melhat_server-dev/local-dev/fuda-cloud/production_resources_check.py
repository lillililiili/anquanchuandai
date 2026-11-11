"""Read-only Compose resource-draft check. Never contacts a Docker daemon.

Only parses the fixed production files, compares the resource overlay to the
baseline, and prints redacted results. This is NOT deployment authorization,
host capacity/preflight, private-file validation, or runtime acceptance.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
PROJECT = 'fuda-wearables-production'
OVERLAY = 'compose.production-resources-8g.yml'
LABEL = 'com.wearables.resource-profile'
PROFILE = 'production-8g-v1'
MIB = 1024 ** 2
CAPS_MIB = {'mysql': 512, 'redis': 128, 'backend': 1024,
            'query-gateway': 64, 'helmet-gateway': 96, 'belt-gateway': 96,
            'phone-gateway': 96, 'private-relays': 64}
JAVA_OPTIONS = '-Xms256m -Xmx512m -XX:+ExitOnOutOfMemoryError'
LOGGING = {'driver': 'json-file', 'options': {'max-size': '10m', 'max-file': '3'}}
MYSQL_COMMAND = ['--character-set-server=utf8mb4', '--collation-server=utf8mb4_unicode_ci',
                 '--innodb-buffer-pool-size=128M', '--innodb-log-buffer-size=8M',
                 '--max-connections=40', '--table-open-cache=400']
REDIS_COMMAND = ['sh', '-c', 'exec redis-server --appendonly yes --appendfsync always '
                 '--no-appendfsync-on-rewrite no --maxmemory 48mb '
                 '--maxmemory-policy noeviction --requirepass "$$REDIS_PASSWORD"']


class ResourceValidationError(ValueError):
    pass


def require(value, message):
    if not value:
        raise ResourceValidationError(message)


def parse_config(files, env_file, docker='docker'):
    """`compose config` only; stdout/stderr may contain secrets, never print them."""
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('COMPOSE_') or key.startswith('DOCKER_'):
            env.pop(key, None)
    command = [docker, 'compose', '--env-file', str(env_file)]
    for filename in files:
        command += ['-f', filename]
    command += ['--profile', 'production-device-cutover', 'config',
                '--no-env-resolution', '--format', 'json']
    process = subprocess.run(command, cwd=str(HERE), env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=30)
    require(process.returncode == 0, 'Compose parsing failed; raw output suppressed')
    return json.loads(process.stdout.decode('utf-8'))


def ports(service):
    return [(p.get('host_ip'), str(p.get('published')), p.get('target'))
            for p in service.get('ports', [])]


def normalized(model):
    # Compose versions may retain $$ in their JSON or render the container's $.
    result = copy.deepcopy(model)
    for service in result.get('services', {}).values():
        for field in ('mem_limit', 'memswap_limit'):
            value = service.get(field)
            if isinstance(value, str) and value.lstrip('-').isdigit():
                service[field] = int(value)
    command = result.get('services', {}).get('redis', {}).get('command')
    if isinstance(command, list):
        result['services']['redis']['command'] = [s.replace('$$', '$') for s in command]
    return result


def validate(baseline, candidate, caps_mib=CAPS_MIB, profile=PROFILE,
             mysql_command=MYSQL_COMMAND, redis_command=REDIS_COMMAND, host_memory_gib=8):
    for model in (baseline, candidate):
        require(model.get('name') == PROJECT, 'Only the fixed production project is accepted')
        services = model.get('services', {})
        require(set(services) == set(caps_mib), 'Expected all eight production services')
        for name in ('mysql', 'backend'):
            require(services[name].get('labels', {}).get('com.wearables.deployment-role') == 'production',
                    'Production override/role is missing')
        require(services['backend'].get('command') == [], 'Production backend command must be unchanged')
        require(ports(services['backend']) == [('127.0.0.1', '18084', 18084)], 'Unexpected backend exposure')
        require(ports(services['query-gateway']) == [('10.255.1.1', '28089', 8080)], 'Unexpected query exposure')
        require(model.get('networks', {}).get('private', {}).get('internal') is True, 'Private network is required')
        require(set(services['backend'].get('networks', {})) == {'private', 'egress'}, 'Unexpected backend networks')
        require(set(services['query-gateway'].get('networks', {})) == {'private', 'frontend'}, 'Unexpected query networks')
        for name in ('mysql', 'redis'):
            require(not services[name].get('ports') and services[name].get('network_mode') != 'host'
                    and set(services[name].get('networks', {})) == {'private'}, 'Database must remain private')
        for name in ('helmet-gateway', 'belt-gateway', 'phone-gateway', 'private-relays'):
            require(services[name].get('profiles') == ['production-device-cutover'], 'Cutover profile is required')
            require(services[name].get('network_mode') == 'host' and not services[name].get('ports'),
                    'Unexpected production gateway networking')
        for name in ('fuda-api.yml', 'device-runtime.yml'):
            mounts = [v for v in services['backend'].get('volumes', []) if v.get('target') == '/run/secrets/' + name]
            require(len(mounts) == 1 and mounts[0].get('read_only') is True and
                    '/.private/production/' in mounts[0].get('source', '').replace('\\', '/'),
                    'Production private runtime mount is required')
        for service in services.values():
            require(service.get('restart') == 'unless-stopped', 'Production restart policy is required')

    # An exact allowed-difference comparison also protects credentials, paths,
    # business profile/switches, volumes, images, build targets and routes.
    expected = copy.deepcopy(baseline)
    for name, limit in caps_mib.items():
        service = expected['services'][name]
        service['mem_limit'] = limit * MIB
        service['memswap_limit'] = limit * MIB
        service['logging'] = copy.deepcopy(LOGGING)
        service.setdefault('labels', {})[LABEL] = profile
    expected['services']['backend'].setdefault('environment', {})['JAVA_TOOL_OPTIONS'] = JAVA_OPTIONS
    expected['services']['mysql']['command'] = mysql_command
    expected['services']['redis']['command'] = redis_command
    require(normalized(expected) == normalized(candidate), 'Resource overlay changes fields outside its reviewed budget')
    return {'configurationPassed': True, 'project': PROJECT, 'resourceProfile': profile,
            'memoryLimitsMiB': caps_mib, 'totalMemoryLimitMiB': sum(caps_mib.values()),
            'cpuQuotasAdded': False, 'businessSettingsPreserved': True,
            'networkAndPortExposureUnchanged': True, 'runtimeValidated': False,
            'productionPreflightStillRequired': True, 'draftForHostMemoryGiB': host_memory_gib}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, default=HERE / '.env.production')
    parser.add_argument('--docker', default='docker')
    args = parser.parse_args()
    baseline = parse_config(['compose.yml', 'compose.production.yml'], args.env_file, args.docker)
    candidate = parse_config(['compose.yml', 'compose.production.yml', OVERLAY], args.env_file, args.docker)
    result = validate(baseline, candidate)
    result['templateEnvironment'] = args.env_file.name == '.env.example'
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Resource draft check failed: ' + (str(error) if isinstance(error, ResourceValidationError) else type(error).__name__))
        raise SystemExit(2)
