#!/usr/bin/env python3
"""Add one fixed default_sni option above a verified applied belt alias.

Python 3.6 compatible. Both older transaction journals remain immutable.
Official behavior: https://caddyserver.com/docs/caddyfile/options#default-sni
"""
from __future__ import print_function

import argparse
import os
import re
import sys
from pathlib import Path

import deploy
import route_alias

KIND = 'belt-default-sni'
PREFIX = b'{\n    default_sni lingzhiaide.com\n}\n\n'


def candidate(data):
    if not data.startswith(b'{$DOMAIN} {\n') or re.search(rb'(?m)^\s*default_sni\b', data):
        raise deploy.DeployError('Expected the reviewed site-first Caddyfile without global default_sni.')
    return PREFIX + data


def script_hashes():
    return {name: deploy.digest(Path(module.__file__).read_bytes())
            for name, module in [('patch', sys.modules[__name__]), ('alias', route_alias), ('helper', deploy)]}


class Patch:
    def __init__(self, state, alias_state, deployment_state):
        route_alias.separate_states(state, alias_state)
        route_alias.separate_states(state, deployment_state)
        route_alias.separate_states(alias_state, deployment_state)
        self.state, self.alias_state, self.deployment_state = state, alias_state, deployment_state
        self.journal = state / 'patch-transaction.json'

    def chain_proof(self):
        alias_plan = route_alias.load_plan(self.alias_state, self.deployment_state, check_scripts=False)
        route_alias.check_protected(alias_plan, self.deployment_state)
        transaction = deploy.load_json(self.alias_state / 'patch-transaction.json')
        if (transaction.get('kind') != route_alias.KIND or transaction.get('status') != 'applied'
                or transaction.get('afterSha256') != alias_plan['afterSha256']):
            raise deploy.DeployError('The verified route-alias transaction must remain applied.')
        preview_bytes, _ = deploy.snapshot(self.alias_state / 'patch-preview.json')
        journal_bytes, _ = deploy.snapshot(self.alias_state / 'patch-transaction.json')
        proof = {'aliasPreviewSha256': deploy.digest(preview_bytes),
                 'aliasJournalSha256': deploy.digest(journal_bytes), 'protected': alias_plan['protected']}
        expected = dict(alias_plan['before'], sha256=alias_plan['afterSha256'])
        return proof, expected

    def check_protected(self, plan):
        proof, _ = self.chain_proof()
        if proof != plan['chain']:
            raise deploy.DeployError('An older transaction or protected SSH/account/key resource changed.')

    def load(self, check_scripts=True):
        plan = deploy.load_json(self.state / 'patch-preview.json')
        if (plan.get('version') != 1 or plan.get('kind') != KIND or plan.get('domain') != deploy.DOMAIN
                or plan.get('targetIp') != deploy.TARGET_IP
                or plan.get('aliasState') != str(self.alias_state.resolve())
                or plan.get('deploymentState') != str(self.deployment_state.resolve())):
            raise deploy.DeployError('Preview does not describe this default_sni patch chain.')
        if check_scripts and plan.get('scripts') != script_hashes():
            raise deploy.DeployError('Patch scripts changed after preview; use a new patch state.')
        before, _ = deploy.snapshot(self.state / 'before.Caddyfile')
        after, _ = deploy.snapshot(self.state / 'after.Caddyfile')
        if (deploy.digest(before) != plan['before']['sha256'] or deploy.digest(after) != plan['afterSha256']
                or candidate(before) != after):
            raise deploy.DeployError('Default_sni backups or candidate integrity check failed.')
        return plan

    def check_caddy(self, plan):
        return route_alias.check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})

    def preview(self):
        if (self.state / 'patch-preview.json').exists():
            plan = self.load()
            self.check_protected(plan)
            self.check_caddy(plan)
            print('PREVIEW ALREADY EXISTS: unchanged default_sni patch inputs; no resources changed.')
            return
        if self.state.exists() and any(self.state.iterdir()):
            raise deploy.DeployError('Use an empty private default_sni patch directory.')
        deploy.private_dir(self.state)
        proof, expected = self.chain_proof()
        before, meta = deploy.snapshot(deploy.CADDY)
        if meta != expected:
            raise deploy.DeployError('Caddy does not match the applied route-alias hash and metadata.')
        after = candidate(before)
        plan = {'version': 1, 'kind': KIND, 'domain': deploy.DOMAIN, 'targetIp': deploy.TARGET_IP,
                'aliasState': str(self.alias_state.resolve()), 'deploymentState': str(self.deployment_state.resolve()),
                'chain': proof, 'protected': proof['protected'], 'before': meta,
                'afterSha256': deploy.digest(after), 'scripts': script_hashes()}
        route_alias.ready(self.state, plan)
        route_alias.validate(self.state, after, 'default-sni-preview-validate')
        self.check_protected(plan)
        route_alias.check_caddy(plan, {meta['sha256']})
        deploy.private_write(self.state / 'before.Caddyfile', before)
        deploy.private_write(self.state / 'after.Caddyfile', after)
        deploy.save_json(self.state / 'patch-preview.json', plan)
        print('PREVIEW OK: only fixed default_sni added; active files and older journals untouched.')

    def restore(self, plan):
        _, meta = self.check_caddy(plan)
        if meta['sha256'] != plan['before']['sha256']:
            deploy.write_in_place(deploy.CADDY, plan['afterSha256'],
                                  (self.state / 'before.Caddyfile').read_bytes(), plan['before']['inode'])
        deploy.reload_caddy(self.state, 'default-sni-rollback-reload')
        deploy.website_healthy()

    def apply(self):
        plan = self.load()
        self.check_protected(plan)
        _, meta = self.check_caddy(plan)
        transaction = deploy.load_json(self.journal) if self.journal.exists() else None
        if transaction is not None:
            if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
                raise deploy.DeployError('Default_sni journal does not match its preview.')
            if transaction.get('status') == 'applied':
                if meta['sha256'] != plan['afterSha256']:
                    raise deploy.DeployError('Applied default_sni no longer matches active Caddy.')
                route_alias.ready(self.state, plan)
                print('APPLY ALREADY COMPLETE: exact default_sni candidate still active; no reload.')
                return
            if transaction.get('status') != 'prepared':
                raise deploy.DeployError('Patch ended or needs attention; rollback before a new preview.')
        elif meta['sha256'] != plan['before']['sha256']:
            raise deploy.DeployError('Caddy changed before the default_sni journal was created.')
        route_alias.ready(self.state, plan)
        after = (self.state / 'after.Caddyfile').read_bytes()
        route_alias.validate(self.state, after, 'default-sni-apply-validate')
        self.check_protected(plan)
        self.check_caddy(plan)
        transaction = {'kind': KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']}
        deploy.save_json(self.journal, transaction)
        try:
            _, meta = self.check_caddy(plan)
            if meta['sha256'] != plan['afterSha256']:
                deploy.write_in_place(deploy.CADDY, plan['before']['sha256'], after, plan['before']['inode'])
            deploy.reload_caddy(self.state, 'default-sni-apply-reload')
            deploy.website_healthy()
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
                raise deploy.DeployError('Default_sni apply failed; restoration needs attention. Preserve private state.')
            raise deploy.DeployError('Default_sni apply failed; original Caddy restored and reloaded.')
        print('APPLY OK: default_sni active; protocols, routes, SSH and older journals unchanged.')

    def rollback(self):
        plan = self.load(check_scripts=False)
        self.check_protected(plan)
        transaction = deploy.load_json(self.journal)
        if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
            raise deploy.DeployError('Default_sni journal does not match its preview.')
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
            raise deploy.DeployError('Default_sni rollback needs attention; later changes were not overwritten.')
        print('ROLLBACK OK: post-alias Caddy restored; older transactions remain applied.')


def main():
    parser = argparse.ArgumentParser(description='Add fixed default_sni above a verified applied belt alias.')
    parser.add_argument('action', choices=['preview', 'apply', 'rollback'])
    parser.add_argument('--state-dir', required=True, type=Path)
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
        patch = Patch(args.state_dir.absolute(), args.alias_state.absolute(), args.deployment_state.absolute())
        {'preview': patch.preview, 'apply': patch.apply, 'rollback': patch.rollback}[args.action]()


if __name__ == '__main__':
    try:
        main()
    except deploy.DeployError as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('ERROR: default_sni operation stopped; inspect private state without sharing credentials.', file=sys.stderr)
        sys.exit(1)
