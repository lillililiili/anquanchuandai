#!/usr/bin/env python3
"""Add one exact cleartext belt WebSocket route after verified TLS patches.

Python 3.6 compatible. All older transaction journals remain immutable.
Only the existing public TCP 80 listener is used; no port mappings are added.
"""
from __future__ import print_function

import argparse
import http.client
import os
import re
import sys
from pathlib import Path

import deploy
import route_alias
import default_sni

KIND = 'belt-legacy-ws'
BEGIN = b'# BEGIN BELT LEGACY WS\n'
END = b'# END BELT LEGACY WS\n'


def candidate(data):
    if (not data.startswith(default_sni.PREFIX) or BEGIN in data or END in data
            or deploy.TARGET_IP.encode('ascii') in data):
        raise deploy.DeployError('Expected reviewed post-default_sni Caddy without a legacy IP site.')
    if data.count(route_alias.BEGIN) != 1 or data.count(route_alias.END) != 1:
        raise deploy.DeployError('Expected exactly one known belt route block.')
    match = route_alias.BLOCK.search(data)
    if match is None or not match.group('alias'):
        raise deploy.DeployError('Expected the applied exact belt configuration alias.')
    token = match.group('token').decode('ascii')
    deploy.validate_token(token)
    addition = ('\n# BEGIN BELT LEGACY WS\n'
                'http://39.106.212.138 {\n'
                '    @belt_legacy_ws path /%s/wsHat\n'
                '    handle @belt_legacy_ws {\n'
                '        reverse_proxy 10.255.1.1:28087\n'
                '    }\n'
                '    handle {\n'
                '        respond 404\n'
                '    }\n'
                '}\n'
                '# END BELT LEGACY WS\n') % token
    return data + addition.encode('ascii')


def script_hashes():
    return {name: deploy.digest(Path(module.__file__).read_bytes())
            for name, module in [('patch', sys.modules[__name__]), ('sni', default_sni), ('alias', route_alias), ('helper', deploy)]}


def http_site_healthy():
    """Check the new IP site rejects a credential-free path, without device traffic."""
    conn = None
    try:
        conn = http.client.HTTPConnection('127.0.0.1', 80, timeout=12)
        conn.request('GET', '/belt-legacy-ws-probe-no-credential',
                     headers={'Host': deploy.TARGET_IP, 'Connection': 'close'})
        if conn.getresponse().status != 404:
            raise ValueError()
    except Exception:
        raise deploy.DeployError('The exact HTTP IP site did not reject an unrelated path with 404.')
    finally:
        if conn is not None:
            conn.close()


class Patch:
    def __init__(self, state, sni_state, alias_state, deployment_state):
        for other in [state, alias_state, deployment_state]:
            route_alias.separate_states(sni_state, other)
        self.sni_state = sni_state
        route_alias.separate_states(state, alias_state)
        route_alias.separate_states(state, deployment_state)
        route_alias.separate_states(alias_state, deployment_state)
        self.state, self.alias_state, self.deployment_state = state, alias_state, deployment_state
        self.journal = state / 'patch-transaction.json'

    def chain_proof(self):
        previous = default_sni.Patch(self.sni_state, self.alias_state, self.deployment_state)
        sni_plan = previous.load(check_scripts=False)
        previous.check_protected(sni_plan)
        transaction = deploy.load_json(self.sni_state / 'patch-transaction.json')
        if (transaction.get('kind') != default_sni.KIND or transaction.get('status') != 'applied'
                or transaction.get('afterSha256') != sni_plan['afterSha256']):
            raise deploy.DeployError('The verified default_sni transaction must remain applied.')
        preview_bytes, _ = deploy.snapshot(self.sni_state / 'patch-preview.json')
        journal_bytes, _ = deploy.snapshot(self.sni_state / 'patch-transaction.json')
        proof = {'sniPreviewSha256': deploy.digest(preview_bytes),
                 'sniJournalSha256': deploy.digest(journal_bytes),
                 'previousChain': sni_plan['chain'], 'protected': sni_plan['protected']}
        expected = dict(sni_plan['before'], sha256=sni_plan['afterSha256'])
        return proof, expected

    def check_protected(self, plan):
        proof, _ = self.chain_proof()
        if proof != plan['chain']:
            raise deploy.DeployError('An older transaction or protected SSH/account/key resource changed.')

    def load(self, check_scripts=True):
        plan = deploy.load_json(self.state / 'patch-preview.json')
        if (plan.get('version') != 1 or plan.get('kind') != KIND or plan.get('domain') != deploy.DOMAIN
                or plan.get('targetIp') != deploy.TARGET_IP
                or plan.get('sniState') != str(self.sni_state.resolve())
                or plan.get('aliasState') != str(self.alias_state.resolve())
                or plan.get('deploymentState') != str(self.deployment_state.resolve())):
            raise deploy.DeployError('Preview does not describe this legacy WebSocket patch chain.')
        if check_scripts and plan.get('scripts') != script_hashes():
            raise deploy.DeployError('Patch scripts changed after preview; use a new patch state.')
        before, _ = deploy.snapshot(self.state / 'before.Caddyfile')
        after, _ = deploy.snapshot(self.state / 'after.Caddyfile')
        if (deploy.digest(before) != plan['before']['sha256'] or deploy.digest(after) != plan['afterSha256']
                or candidate(before) != after):
            raise deploy.DeployError('Legacy WebSocket backups or candidate integrity check failed.')
        return plan

    def check_caddy(self, plan):
        return route_alias.check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})

    def preview(self):
        if (self.state / 'patch-preview.json').exists():
            plan = self.load()
            self.check_protected(plan)
            self.check_caddy(plan)
            print('PREVIEW ALREADY EXISTS: unchanged legacy WebSocket patch inputs; no resources changed.')
            return
        if self.state.exists() and any(self.state.iterdir()):
            raise deploy.DeployError('Use an empty private legacy WebSocket patch directory.')
        deploy.private_dir(self.state)
        proof, expected = self.chain_proof()
        before, meta = deploy.snapshot(deploy.CADDY)
        if meta != expected:
            raise deploy.DeployError('Caddy does not match the applied default_sni hash and metadata.')
        after = candidate(before)
        plan = {'version': 1, 'kind': KIND, 'domain': deploy.DOMAIN, 'targetIp': deploy.TARGET_IP,
                'sniState': str(self.sni_state.resolve()), 'aliasState': str(self.alias_state.resolve()),
                'deploymentState': str(self.deployment_state.resolve()),
                'chain': proof, 'protected': proof['protected'], 'before': meta,
                'afterSha256': deploy.digest(after), 'scripts': script_hashes()}
        route_alias.ready(self.state, plan)
        route_alias.validate(self.state, after, 'legacy-ws-preview-validate')
        self.check_protected(plan)
        route_alias.check_caddy(plan, {meta['sha256']})
        deploy.private_write(self.state / 'before.Caddyfile', before)
        deploy.private_write(self.state / 'after.Caddyfile', after)
        deploy.save_json(self.state / 'patch-preview.json', plan)
        print('PREVIEW OK: only one exact cleartext WebSocket route added; active files and older journals untouched.')

    def restore(self, plan):
        _, meta = self.check_caddy(plan)
        if meta['sha256'] != plan['before']['sha256']:
            deploy.write_in_place(deploy.CADDY, plan['afterSha256'],
                                  (self.state / 'before.Caddyfile').read_bytes(), plan['before']['inode'])
        deploy.reload_caddy(self.state, 'legacy-ws-rollback-reload')
        deploy.website_healthy()

    def apply(self):
        plan = self.load()
        self.check_protected(plan)
        _, meta = self.check_caddy(plan)
        transaction = deploy.load_json(self.journal) if self.journal.exists() else None
        if transaction is not None:
            if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
                raise deploy.DeployError('Legacy WebSocket journal does not match its preview.')
            if transaction.get('status') == 'applied':
                if meta['sha256'] != plan['afterSha256']:
                    raise deploy.DeployError('Applied legacy WebSocket route no longer matches active Caddy.')
                route_alias.ready(self.state, plan)
                print('APPLY ALREADY COMPLETE: exact legacy WebSocket candidate still active; no reload.')
                return
            if transaction.get('status') != 'prepared':
                raise deploy.DeployError('Patch ended or needs attention; rollback before a new preview.')
        elif meta['sha256'] != plan['before']['sha256']:
            raise deploy.DeployError('Caddy changed before the legacy WebSocket journal was created.')
        route_alias.ready(self.state, plan)
        after = (self.state / 'after.Caddyfile').read_bytes()
        route_alias.validate(self.state, after, 'legacy-ws-apply-validate')
        self.check_protected(plan)
        self.check_caddy(plan)
        transaction = {'kind': KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']}
        deploy.save_json(self.journal, transaction)
        try:
            _, meta = self.check_caddy(plan)
            if meta['sha256'] != plan['afterSha256']:
                deploy.write_in_place(deploy.CADDY, plan['before']['sha256'], after, plan['before']['inode'])
            deploy.reload_caddy(self.state, 'legacy-ws-apply-reload')
            deploy.website_healthy()
            http_site_healthy()
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
                raise deploy.DeployError('Legacy WebSocket apply failed; restoration needs attention. Preserve private state.')
            raise deploy.DeployError('Legacy WebSocket apply failed; original Caddy restored and reloaded.')
        print('APPLY OK: exact HTTP IP WebSocket route active; prior HTTPS, SSH and journals unchanged.')

    def rollback(self):
        plan = self.load(check_scripts=False)
        self.check_protected(plan)
        transaction = deploy.load_json(self.journal)
        if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
            raise deploy.DeployError('Legacy WebSocket journal does not match its preview.')
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
            raise deploy.DeployError('Legacy WebSocket rollback needs attention; later changes were not overwritten.')
        print('ROLLBACK OK: post-default_sni Caddy restored; older transactions remain applied.')


def main():
    parser = argparse.ArgumentParser(description='Add one exact HTTP IP WebSocket route after verified TLS patches.')
    parser.add_argument('action', choices=['preview', 'apply', 'rollback'])
    parser.add_argument('--state-dir', required=True, type=Path)
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
        patch = Patch(args.state_dir.absolute(), args.sni_state.absolute(), args.alias_state.absolute(), args.deployment_state.absolute())
        {'preview': patch.preview, 'apply': patch.apply, 'rollback': patch.rollback}[args.action]()


if __name__ == '__main__':
    try:
        main()
    except deploy.DeployError as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('ERROR: legacy WebSocket operation stopped; inspect private state without sharing credentials.', file=sys.stderr)
        sys.exit(1)
