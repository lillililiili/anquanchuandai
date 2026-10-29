#!/usr/bin/env python3
"""Add one exact short belt WS alias to a verified legacy WS transaction.

Python 3.6 compatible. Prior scripts and transaction journals remain immutable.
"""
from __future__ import print_function

import argparse
import os
import re
import sys
from pathlib import Path

import deploy
import route_alias
import default_sni
import legacy_ws

KIND = 'belt-short-ws'
BLOCK = re.compile(
    re.escape(legacy_ws.BEGIN)
    + rb'http://39\.106\.212\.138 \{\n'
    + rb'    @belt_legacy_ws path /(?P<token>[A-Za-z0-9_-]{43})/wsHat\n'
    + rb'    handle @belt_legacy_ws \{\n        reverse_proxy 10\.255\.1\.1:28087\n    \}\n'
    + rb'    handle \{\n        respond 404\n    \}\n\}\n'
    + re.escape(legacy_ws.END))


def candidate(data):
    if (not data.startswith(default_sni.PREFIX)
            or data.count(legacy_ws.BEGIN) != 1 or data.count(legacy_ws.END) != 1
            or data.count(route_alias.BEGIN) != 1 or data.count(route_alias.END) != 1):
        raise deploy.DeployError('Expected one applied legacy WS block and verified belt route block.')
    match = BLOCK.search(data)
    tls = route_alias.BLOCK.search(data)
    if match is None or tls is None or not tls.group('alias') or match.group('token') != tls.group('token'):
        raise deploy.DeployError('Existing legacy WS routes differ from the reviewed exact layout.')
    token = match.group('token')
    deploy.validate_token(token.decode('ascii'))
    needle = b'    @belt_legacy_ws path /' + token + b'/wsHat\n'
    replacement = needle[:-1] + b' /' + token[:24] + b'/wsHat\n'
    patched = match.group(0).replace(needle, replacement, 1)
    return data[:match.start()] + patched + data[match.end():]


def script_hashes():
    return {name: deploy.digest(Path(module.__file__).read_bytes())
            for name, module in [('patch', sys.modules[__name__]), ('legacy', legacy_ws),
                                 ('sni', default_sni), ('alias', route_alias), ('helper', deploy)]}


class Patch:
    def __init__(self, state, legacy_state, sni_state, alias_state, deployment_state):
        states = [state, legacy_state, sni_state, alias_state, deployment_state]
        for index, left in enumerate(states):
            for right in states[index + 1:]:
                route_alias.separate_states(left, right)
        self.state, self.legacy_state, self.sni_state = state, legacy_state, sni_state
        self.alias_state, self.deployment_state = alias_state, deployment_state
        self.journal = state / 'patch-transaction.json'

    def chain_proof(self):
        previous = legacy_ws.Patch(self.legacy_state, self.sni_state, self.alias_state, self.deployment_state)
        old = previous.load(check_scripts=False)
        previous.check_protected(old)
        transaction = deploy.load_json(self.legacy_state / 'patch-transaction.json')
        if (transaction.get('kind') != legacy_ws.KIND or transaction.get('status') != 'applied'
                or transaction.get('afterSha256') != old['afterSha256']):
            raise deploy.DeployError('The verified legacy WS transaction must remain applied.')
        preview, _ = deploy.snapshot(self.legacy_state / 'patch-preview.json')
        journal, _ = deploy.snapshot(self.legacy_state / 'patch-transaction.json')
        proof = {'legacyPreviewSha256': deploy.digest(preview), 'legacyJournalSha256': deploy.digest(journal),
                 'previousChain': old['chain'], 'protected': old['protected']}
        return proof, dict(old['before'], sha256=old['afterSha256'])

    def check_protected(self, plan):
        proof, _ = self.chain_proof()
        if proof != plan['chain']:
            raise deploy.DeployError('An older transaction or protected SSH/account/key resource changed.')

    def load(self, check_scripts=True):
        plan = deploy.load_json(self.state / 'patch-preview.json')
        expected_states = {'legacyState': self.legacy_state, 'sniState': self.sni_state,
                           'aliasState': self.alias_state, 'deploymentState': self.deployment_state}
        if (plan.get('version') != 1 or plan.get('kind') != KIND or plan.get('domain') != deploy.DOMAIN
                or plan.get('targetIp') != deploy.TARGET_IP
                or any(plan.get(key) != str(value.resolve()) for key, value in expected_states.items())):
            raise deploy.DeployError('Preview does not describe this short WS patch chain.')
        if check_scripts and plan.get('scripts') != script_hashes():
            raise deploy.DeployError('Patch scripts changed after preview; use a new patch state.')
        before, _ = deploy.snapshot(self.state / 'before.Caddyfile')
        after, _ = deploy.snapshot(self.state / 'after.Caddyfile')
        if (deploy.digest(before) != plan['before']['sha256'] or deploy.digest(after) != plan['afterSha256']
                or candidate(before) != after):
            raise deploy.DeployError('Short WS backups or candidate integrity check failed.')
        return plan

    def check_caddy(self, plan):
        return route_alias.check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})

    def preview(self):
        if (self.state / 'patch-preview.json').exists():
            plan = self.load()
            self.check_protected(plan)
            self.check_caddy(plan)
            print('PREVIEW ALREADY EXISTS: unchanged short WS inputs; no resources changed.')
            return
        if self.state.exists() and any(self.state.iterdir()):
            raise deploy.DeployError('Use an empty private short WS patch directory.')
        deploy.private_dir(self.state)
        proof, expected = self.chain_proof()
        before, meta = deploy.snapshot(deploy.CADDY)
        if meta != expected:
            raise deploy.DeployError('Caddy does not match the applied legacy WS hash and metadata.')
        after = candidate(before)
        plan = {'version': 1, 'kind': KIND, 'domain': deploy.DOMAIN, 'targetIp': deploy.TARGET_IP,
                'legacyState': str(self.legacy_state.resolve()), 'sniState': str(self.sni_state.resolve()),
                'aliasState': str(self.alias_state.resolve()), 'deploymentState': str(self.deployment_state.resolve()),
                'chain': proof, 'protected': proof['protected'], 'before': meta,
                'afterSha256': deploy.digest(after), 'scripts': script_hashes()}
        route_alias.ready(self.state, plan)
        route_alias.validate(self.state, after, 'short-ws-preview-validate')
        self.check_protected(plan)
        route_alias.check_caddy(plan, {meta['sha256']})
        deploy.private_write(self.state / 'before.Caddyfile', before)
        deploy.private_write(self.state / 'after.Caddyfile', after)
        deploy.save_json(self.state / 'patch-preview.json', plan)
        print('PREVIEW OK: one exact short WS alias; active files and older journals untouched.')

    def restore(self, plan):
        _, meta = self.check_caddy(plan)
        if meta['sha256'] != plan['before']['sha256']:
            deploy.write_in_place(deploy.CADDY, plan['afterSha256'],
                                  (self.state / 'before.Caddyfile').read_bytes(), plan['before']['inode'])
        deploy.reload_caddy(self.state, 'short-ws-rollback-reload')
        deploy.website_healthy()
        legacy_ws.http_site_healthy()

    def apply(self):
        plan = self.load()
        self.check_protected(plan)
        _, meta = self.check_caddy(plan)
        transaction = deploy.load_json(self.journal) if self.journal.exists() else None
        if transaction is not None:
            if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
                raise deploy.DeployError('Short WS journal does not match its preview.')
            if transaction.get('status') == 'applied':
                if meta['sha256'] != plan['afterSha256']:
                    raise deploy.DeployError('Applied short WS route no longer matches active Caddy.')
                route_alias.ready(self.state, plan)
                print('APPLY ALREADY COMPLETE: exact short WS candidate still active; no reload.')
                return
            if transaction.get('status') != 'prepared':
                raise deploy.DeployError('Patch ended or needs attention; rollback before a new preview.')
        elif meta['sha256'] != plan['before']['sha256']:
            raise deploy.DeployError('Caddy changed before the short WS journal was created.')
        route_alias.ready(self.state, plan)
        after = (self.state / 'after.Caddyfile').read_bytes()
        route_alias.validate(self.state, after, 'short-ws-apply-validate')
        self.check_protected(plan)
        self.check_caddy(plan)
        transaction = {'kind': KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']}
        deploy.save_json(self.journal, transaction)
        try:
            _, meta = self.check_caddy(plan)
            if meta['sha256'] != plan['afterSha256']:
                deploy.write_in_place(deploy.CADDY, plan['before']['sha256'], after, plan['before']['inode'])
            deploy.reload_caddy(self.state, 'short-ws-apply-reload')
            deploy.website_healthy()
            legacy_ws.http_site_healthy()
            self.check_protected(plan)
            route_alias.check_caddy(plan, {plan['afterSha256']})
            transaction['status'] = 'applied'
            deploy.save_json(self.journal, transaction)
        except Exception:
            try:
                self.restore(plan)
                transaction['status'] = 'rolled-back'
                deploy.save_json(self.journal, transaction)
            except Exception:
                transaction['status'] = 'rollback-needs-attention'
                try:
                    deploy.save_json(self.journal, transaction)
                except Exception:
                    pass
                raise deploy.DeployError('Short WS apply failed; restoration needs attention. Preserve private state.')
            raise deploy.DeployError('Short WS apply failed; original Caddy restored and reloaded.')
        print('APPLY OK: exact short WS alias active; old routes, SSH and journals unchanged.')

    def rollback(self):
        plan = self.load(check_scripts=False)
        self.check_protected(plan)
        transaction = deploy.load_json(self.journal)
        if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
            raise deploy.DeployError('Short WS journal does not match its preview.')
        try:
            self.restore(plan)
            transaction['status'] = 'rolled-back'
            deploy.save_json(self.journal, transaction)
        except Exception:
            transaction['status'] = 'rollback-needs-attention'
            try:
                deploy.save_json(self.journal, transaction)
            except Exception:
                pass
            raise deploy.DeployError('Short WS rollback needs attention; later changes were not overwritten.')
        print('ROLLBACK OK: prior legacy WS Caddy restored; older transactions remain applied.')


def main():
    parser = argparse.ArgumentParser(description='Add one exact short alias to the verified legacy WS site.')
    parser.add_argument('action', choices=['preview', 'apply', 'rollback'])
    parser.add_argument('--state-dir', required=True, type=Path)
    parser.add_argument('--legacy-state', required=True, type=Path)
    parser.add_argument('--sni-state', required=True, type=Path)
    parser.add_argument('--alias-state', required=True, type=Path)
    parser.add_argument('--deployment-state', required=True, type=Path)
    args = parser.parse_args()
    if os.name != 'posix' or deploy.pwd is None or os.geteuid() != 0:
        raise deploy.DeployError('Run server-side as root on Linux; isolated tests do not require root.')
    os.umask(0o077)
    fd = os.open('/var/lock/belt-device-gateway-deploy.lock',
                 os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'a+b') as control:
        try:
            deploy.fcntl.flock(control.fileno(), deploy.fcntl.LOCK_EX | deploy.fcntl.LOCK_NB)
        except OSError:
            raise deploy.DeployError('Another belt cloud operation is in progress.')
        patch = Patch(args.state_dir.absolute(), args.legacy_state.absolute(), args.sni_state.absolute(),
                      args.alias_state.absolute(), args.deployment_state.absolute())
        {'preview': patch.preview, 'apply': patch.apply, 'rollback': patch.rollback}[args.action]()


if __name__ == '__main__':
    try:
        main()
    except deploy.DeployError as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('ERROR: short WS operation stopped; inspect private state without sharing credentials.', file=sys.stderr)
        sys.exit(1)
