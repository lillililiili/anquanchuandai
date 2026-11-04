#!/usr/bin/env python3
"""Register existing isolated Docker dependencies; does not create or alter services."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

import ops


def register(database, redis):
    private = ops.ROOT / 'private' / 'lab'
    destination = private / 'isolation.json'
    if destination.exists() or destination.is_symlink():
        raise ValueError('Inventory already exists; preserve it and review changes before preparing another laboratory.')
    os.environ['GATEWAY_CONFIG_GENERATION'] = json.loads((private / 'gateway-manifest.json').read_text(encoding='utf-8'))['generation']
    config = json.loads(ops.call(['docker', 'compose', '--project-directory', str(ops.ROOT),
                                  '--env-file', str(ops.ROOT / '.lab.env'), '-f', str(ops.ROOT / 'compose.yml'),
                                  '-f', str(ops.ROOT / 'compose.lab.yml'), 'config', '--format', 'json'], capture=True))
    env = config['services']['app-a']['environment']
    network = config['networks']['cluster']['name']
    shared = next(v['source'] for v in config['services']['app-a']['volumes'] if v['target'] == '/shared')
    marker = Path(shared) / 'files' / '.wearable-store-id'
    if marker.is_symlink() or not marker.is_file() or marker.read_text(encoding='ascii').strip() != env['MELHAT_FILES_STORE_ID']:
        raise ValueError('Prepare and verify the independent shared store before registering it.')
    db = urlsplit(env['MELHAT_DB_URL'].removeprefix('jdbc:'))
    manifest = dict(version=1, project=config['name'], network=dict(name=network,
                    id=ops.call(['docker', 'network', 'inspect', '--format', '{{.Id}}', network], capture=True).strip()),
                    database=dict(containerId=ops.container_identity(database)['id'],
                                  schema=env['MELHAT_DB_USERNAME'] if env['MELHAT_DB_PRODUCT'] == 'dm8' else db.path.lstrip('/')),
                    redis=dict(containerId=ops.container_identity(redis)['id'], database=int(env.get('CLUSTER_REDIS_DATABASE', 0))),
                    sharedDirectory=str(Path(shared).resolve()), storeId=env['MELHAT_FILES_STORE_ID'],
                    backendEnvSha256=hashlib.sha256((private / 'backend.env').read_bytes()).hexdigest(),
                    entrySha256=hashlib.sha256((private / 'Caddy.lab').read_bytes()).hexdigest())
    # Same complete checks used for every subsequent operation; no inventory is published on failure.
    ops.configuration(True, inventory=manifest)
    fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
        json.dump(manifest, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database-container', required=True)
    parser.add_argument('--redis-container', required=True)
    args = parser.parse_args()
    try:
        register(args.database_container, args.redis_container)
        print('Registered verified laboratory dependency identities and configuration hashes. No services were changed.')
    except Exception:
        print('Laboratory registration failed; check isolated dependencies, private configuration and shared-store identity. No credentials printed.', file=sys.stderr)
        sys.exit(1)
