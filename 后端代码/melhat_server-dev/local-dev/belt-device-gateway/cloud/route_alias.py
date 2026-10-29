#!/usr/bin/env python3
"""Add only the belt configuration alias to a verified existing deployment.

Python 3.6 compatible. The original deployment journal is never modified.
Rollback this patch before rolling back the original belt deployment.
"""
from __future__ import print_function

import argparse
import os
import re
import sys
from pathlib import Path

import deploy

KIND = 'belt-bootstrap-route-alias'
BEGIN = b'    # BEGIN BELT DEVICE GATEWAY\n'
END = b'    # END BELT DEVICE GATEWAY\n'
BLOCK = re.compile(
    re.escape(BEGIN)
    + rb'    @belt_device path /(?P<token>[A-Za-z0-9_-]{43})/api/belt/index\.php '
    + rb'(?P<alias>/(?P=token)/api/belt/config/index\.php )?/(?P=token)/wsBelt\n'
    + rb'    handle @belt_device \{\n        reverse_proxy 10\.255\.1\.1:28087\n    \}\n'
    + re.escape(END))


def route_candidate(data):
    if data.count(BEGIN) != 1 or data.count(END) != 1:
        raise deploy.DeployError('Expected exactly one known belt route block.')
    match = BLOCK.search(data)
    if match is None:
        raise deploy.DeployError('Existing belt routes differ from the reviewed layout.')
    deploy.validate_token(match.group('token').decode('ascii'))
    if match.group('alias'):
        return data
    old = match.group(0)
    needle = b'/' + match.group('token') + b'/wsBelt\n'
    replacement = b'/' + match.group('token') + b'/api/belt/config/index.php ' + needle
    return data[:match.start()] + old.replace(needle, replacement, 1) + data[match.end():]


def separate_states(state, deployment_state):
    if state.is_symlink() or deployment_state.is_symlink():
        raise deploy.DeployError('State directories cannot be symlinks.')
    left, right = state.resolve(), deployment_state.resolve()
    if left == right or left in right.parents or right in left.parents:
        raise deploy.DeployError('Use a separate sibling patch state directory.')


def script_hashes():
    return {'patch': deploy.digest(Path(__file__).read_bytes()),
            'helper': deploy.digest(Path(deploy.__file__).read_bytes())}


def deployment_proof(deployment_state):
    """Read the immutable deployment and protected resources; never write them."""
    preview_bytes, _ = deploy.snapshot(deployment_state / 'preview.json')
    transaction_bytes, _ = deploy.snapshot(deployment_state / 'deployment.json')
    plan = deploy.load_json(deployment_state / 'preview.json')
    transaction = deploy.load_json(deployment_state / 'deployment.json')
    deploy.require_plan_identity(plan)
    if transaction.get('status') != 'applied' or transaction.get('service') != plan['service']:
        raise deploy.DeployError('The original belt deployment must remain applied.')
    ssh_bytes, ssh_meta = deploy.snapshot(deploy.SSHD)
    expected_ssh = dict(plan['original']['sshd'], sha256=transaction['deployed']['sshd'])
    if ssh_meta != expected_ssh:
        raise deploy.DeployError('The deployed SSH configuration or metadata changed.')
    if deploy.HOME.is_symlink() or (deploy.HOME / '.ssh').is_symlink():
        raise deploy.DeployError('The dedicated key directory changed.')
    account = deploy.pwd.getpwnam(deploy.USER)
    if (account.pw_uid != transaction.get('accountUid') or account.pw_gid != transaction.get('accountGid')
            or account.pw_dir != str(deploy.HOME)):
        raise deploy.DeployError('The dedicated account identity changed.')
    _, key_meta = deploy.snapshot(deploy.HOME / '.ssh' / 'authorized_keys')
    if key_meta['sha256'] != transaction.get('keySha256'):
        raise deploy.DeployError('The dedicated public key changed.')
    proof = {'previewSha256': deploy.digest(preview_bytes), 'transactionSha256': deploy.digest(transaction_bytes),
             'sshd': ssh_meta, 'key': key_meta, 'uid': account.pw_uid, 'gid': account.pw_gid,
             'service': plan['service']}
    expected_caddy = dict(plan['original']['caddy'], sha256=transaction['deployed']['caddy'])
    return proof, expected_caddy


def check_protected(plan, deployment_state):
    proof, _ = deployment_proof(deployment_state)
    if proof != plan['protected']:
        raise deploy.DeployError('Protected deployment, SSH, account or public key changed after preview.')


def check_caddy(plan, hashes):
    data, meta = deploy.snapshot(deploy.CADDY)
    if (meta['sha256'] not in hashes
            or any(meta[key] != plan['before'][key] for key in ['inode', 'mode', 'uid', 'gid'])):
        raise deploy.DeployError('Caddy changed outside this patch; refusing to overwrite it.')
    return data, meta


def load_plan(state, deployment_state, check_scripts=True):
    separate_states(state, deployment_state)
    plan = deploy.load_json(state / 'patch-preview.json')
    if (plan.get('version') != 1 or plan.get('kind') != KIND or plan.get('domain') != deploy.DOMAIN
            or plan.get('targetIp') != deploy.TARGET_IP
            or plan.get('deploymentState') != str(deployment_state.resolve())):
        raise deploy.DeployError('This preview does not describe the requested belt route patch.')
    if check_scripts and plan.get('scripts') != script_hashes():
        raise deploy.DeployError('Patch scripts changed after preview; use a new patch state directory.')
    before, _ = deploy.snapshot(state / 'before.Caddyfile')
    after, _ = deploy.snapshot(state / 'after.Caddyfile')
    if (deploy.digest(before) != plan['before']['sha256'] or deploy.digest(after) != plan['afterSha256']
            or route_candidate(before) != after):
        raise deploy.DeployError('Patch backups or candidate integrity check failed.')
    return plan


def validate(state, candidate, label):
    deploy.run(state, label, ['docker', 'exec', '-i', deploy.CONTAINER, 'caddy', 'validate',
               '--config', '/dev/stdin', '--adapter', 'caddyfile'], input_data=candidate)


def ready(state, plan):
    if deploy.server_ready(state) != plan['protected']['service']:
        raise deploy.DeployError('The active service differs from the reviewed deployment.')


def preview(state, deployment_state):
    separate_states(state, deployment_state)
    if (state / 'patch-preview.json').exists():
        plan = load_plan(state, deployment_state)
        check_protected(plan, deployment_state)
        check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})
        print('PREVIEW ALREADY EXISTS: verified unchanged patch inputs; no resources changed.')
        return
    if state.exists() and any(state.iterdir()):
        raise deploy.DeployError('Use an empty private patch state directory.')
    deploy.private_dir(state)
    proof, expected_caddy = deployment_proof(deployment_state)
    before, meta = deploy.snapshot(deploy.CADDY)
    if meta != expected_caddy:
        raise deploy.DeployError('Active Caddy does not match the original applied transaction.')
    after = route_candidate(before)
    plan = {'version': 1, 'kind': KIND, 'domain': deploy.DOMAIN, 'targetIp': deploy.TARGET_IP,
            'deploymentState': str(deployment_state.resolve()), 'protected': proof,
            'scripts': script_hashes(), 'before': meta, 'afterSha256': deploy.digest(after)}
    ready(state, plan)
    validate(state, after, 'alias-preview-validate')
    check_protected(plan, deployment_state)
    check_caddy(plan, {meta['sha256']})
    deploy.private_write(state / 'before.Caddyfile', before)
    deploy.private_write(state / 'after.Caddyfile', after)
    deploy.save_json(state / 'patch-preview.json', plan)
    print('PREVIEW OK: one exact belt configuration alias; original transaction and active files untouched.')


def restore(state, plan):
    """Restore only our Caddy bytes, keeping inode and all unrelated resources."""
    _, meta = check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})
    if meta['sha256'] != plan['before']['sha256']:
        deploy.write_in_place(deploy.CADDY, plan['afterSha256'], (state / 'before.Caddyfile').read_bytes(), plan['before']['inode'])
    # Also retry reload when a previous attempt restored bytes but reload failed.
    deploy.reload_caddy(state, 'alias-rollback-reload')
    deploy.website_healthy()


def apply(state, deployment_state):
    plan = load_plan(state, deployment_state)
    check_protected(plan, deployment_state)
    _, meta = check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})
    journal = state / 'patch-transaction.json'
    transaction = deploy.load_json(journal) if journal.exists() else None
    if transaction is not None:
        if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
            raise deploy.DeployError('Patch journal does not match its preview.')
        if transaction.get('status') == 'applied':
            if meta['sha256'] != plan['afterSha256']:
                raise deploy.DeployError('Applied patch no longer matches active Caddy.')
            ready(state, plan)
            print('APPLY ALREADY COMPLETE: exact candidate still active; no reload or resource changes.')
            return
        if transaction.get('status') != 'prepared':
            raise deploy.DeployError('This patch ended or needs attention; rollback before a new preview.')
    elif meta['sha256'] != plan['before']['sha256']:
        raise deploy.DeployError('Caddy changed before a patch journal was created.')
    ready(state, plan)
    candidate = (state / 'after.Caddyfile').read_bytes()
    validate(state, candidate, 'alias-apply-validate')
    check_protected(plan, deployment_state)
    check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})
    transaction = {'kind': KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']}
    deploy.save_json(journal, transaction)
    try:
        _, meta = check_caddy(plan, {plan['before']['sha256'], plan['afterSha256']})
        if meta['sha256'] != plan['afterSha256']:
            deploy.write_in_place(deploy.CADDY, plan['before']['sha256'], candidate, plan['before']['inode'])
        if plan['before']['sha256'] != plan['afterSha256']:
            deploy.reload_caddy(state, 'alias-apply-reload')
        deploy.website_healthy()
        check_protected(plan, deployment_state)
        check_caddy(plan, {plan['afterSha256']})
        transaction['status'] = 'applied'
        deploy.save_json(journal, transaction)
    except Exception:
        try:
            restore(state, plan)
            transaction['status'] = 'rolled-back'
            deploy.save_json(journal, transaction)
        except Exception:
            transaction['status'] = 'rollback-needs-attention'
            try:
                deploy.save_json(journal, transaction)
            except Exception:
                pass
            raise deploy.DeployError('Alias apply failed; restoration needs attention. Preserve private state.')
        raise deploy.DeployError('Alias apply failed; original Caddy restored and reloaded.')
    print('APPLY OK: exact belt alias active; original deployment journal, SSH and accounts untouched.')


def rollback(state, deployment_state):
    # Do not couple recovery to a later harmless script edit.
    plan = load_plan(state, deployment_state, check_scripts=False)
    check_protected(plan, deployment_state)
    journal = state / 'patch-transaction.json'
    transaction = deploy.load_json(journal)
    if transaction.get('kind') != KIND or transaction.get('afterSha256') != plan['afterSha256']:
        raise deploy.DeployError('Patch journal does not match its preview.')
    try:
        restore(state, plan)
        transaction['status'] = 'rolled-back'
        deploy.save_json(journal, transaction)
    except Exception:
        transaction['status'] = 'rollback-needs-attention'
        try:
            deploy.save_json(journal, transaction)
        except Exception:
            pass
        raise deploy.DeployError('Alias rollback needs attention; later changes were not overwritten.')
    print('ROLLBACK OK: pre-alias Caddy restored; original belt deployment can now be rolled back separately.')


def main():
    parser = argparse.ArgumentParser(description='Patch only the exact belt bootstrap alias on an applied deployment.')
    parser.add_argument('action', choices=['preview', 'apply', 'rollback'])
    parser.add_argument('--state-dir', required=True, type=Path)
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
        {'preview': preview, 'apply': apply, 'rollback': rollback}[args.action](
            args.state_dir.absolute(), args.deployment_state.absolute())


if __name__ == '__main__':
    try:
        main()
    except deploy.DeployError as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('ERROR: alias operation stopped; inspect private state without sharing credentials.', file=sys.stderr)
        sys.exit(1)
