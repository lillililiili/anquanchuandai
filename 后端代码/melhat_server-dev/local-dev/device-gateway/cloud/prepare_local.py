#!/usr/bin/env python3
"""Prepare private deployment inputs locally; does not read the SSH private key."""
from __future__ import print_function

import argparse
import json
from pathlib import Path

from deploy import DeployError, private_write, validate_public_key, validate_token


def main():
    parser = argparse.ArgumentParser(description='Prepare the ignored cloud settings; no connection or service startup.')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    local = Path(__file__).resolve().parents[1] / '.local'
    destination = args.output or local / 'cloud-settings.json'
    if destination.exists():
        raise DeployError('Output already exists; refusing to overwrite it.')
    try:
        configuration = json.loads((local / 'config.json').read_text(encoding='utf-8'))
        token = validate_token(configuration['pathToken'])
        public_key = validate_public_key((local / 'helmet_tunnel_ed25519.pub').read_text(encoding='ascii'))
    except Exception:
        raise DeployError('Cannot validate the existing local path credential and public key.')
    private_write(destination, json.dumps({'pathToken': token, 'publicKey': public_key}, indent=2) + '\n')
    print('Prepared private cloud settings. No key, credential or device URL was printed; no connection was made.')


if __name__ == '__main__':
    try:
        main()
    except DeployError as exc:
        raise SystemExit('ERROR: ' + str(exc))
