#!/usr/bin/env python3
"""Python 3.6 compatible, explicit preview/apply/rollback for one belt entry."""
from __future__ import print_function

import argparse
import base64
import hashlib
import http.client
import json
import os
import re
import socket
import ssl
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

try:
    import fcntl
    import grp
    import pwd
except ImportError:  # Importable for isolated Windows unit tests; CLI requires Linux.
    fcntl = grp = pwd = None

TARGET_IP = '39.106.212.138'
DOMAIN = 'lingzhiaide.com'
CONTAINER = 'knowledge-base-gateway-1'
CADDY = Path('/home/admin/knowledge-base/Caddyfile')
SSHD = Path('/etc/ssh/sshd_config')
USER = 'belt-tunnel'
HOME = Path('/var/lib/belt-tunnel')
BRIDGE = '10.255.1.1'
PORT = 28087
PLACEHOLDER_TOKEN = base64.urlsafe_b64encode(b'preview-only-not-a-real-secret!!').decode('ascii').rstrip('=')
MARKER = 'BELT DEVICE GATEWAY'
HELMET_MARKER = 'HELMET DEVICE GATEWAY'
# Deliberately recognize only the already-reviewed helmet deployment, not arbitrary
# Caddy syntax. The matched bytes and every following site remain untouched.
HELMET_BASELINE = re.compile(
    r'\A\{\$DOMAIN\} \{\n    encode zstd gzip\n'
    r'    # BEGIN HELMET DEVICE GATEWAY\n'
    r'    @helmet_device path /(?P<helmet_token>[A-Za-z0-9_-]{43})/api/index\.php '
    r'/(?P=helmet_token)/wsHat\n'
    r'    handle @helmet_device \{\n        reverse_proxy 10\.255\.1\.1:28086\n    \}\n'
    r'    # END HELMET DEVICE GATEWAY\n'
    r'(?P<fallback>    handle \{\n        reverse_proxy nginx:80\n    \}\n\}\n)')
SSH_BLOCK = '''\n# BEGIN BELT DEVICE GATEWAY
Match User belt-tunnel
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    GatewayPorts clientspecified
    AllowTcpForwarding remote
    PermitListen 10.255.1.1:28087
    AllowStreamLocalForwarding no
    PermitTunnel no
    MaxSessions 0
    ClientAliveInterval 30
    ClientAliveCountMax 3
# END BELT DEVICE GATEWAY
'''
EXPECTED_SSH = {
    'authenticationmethods': 'publickey', 'passwordauthentication': 'no',
    'kbdinteractiveauthentication': 'no', 'gatewayports': 'clientspecified',
    'allowtcpforwarding': 'remote', 'permitlisten': '10.255.1.1:28087',
    'allowstreamlocalforwarding': 'no', 'permittunnel': 'no', 'maxsessions': '0',
    'clientaliveinterval': '30', 'clientalivecountmax': '3',
}


class DeployError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def private_dir(path):
    if path.is_symlink():
        raise DeployError('Refusing a symlink state directory.')
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(str(path), 0o700)


def private_write(path, data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(str(path), flags, 0o600)
    with os.fdopen(fd, 'wb') as out:
        os.fchmod(out.fileno(), 0o600) if hasattr(os, 'fchmod') else None
        out.write(data)
        out.flush()
        os.fsync(out.fileno())


def save_json(path, value):
    # Transaction journals may replace their inode. Keep the previous complete
    # journal until the next one is durable; active Caddy/SSHD files still use
    # write_in_place below because Caddy holds a single-file bind mount.
    if path.is_symlink():
        raise DeployError('Refusing a symlink JSON state file.')
    data = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode('utf-8')
    temporary = None
    try:
        fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', suffix='.tmp', dir=str(path.parent))
        with os.fdopen(fd, 'wb') as out:
            os.fchmod(out.fileno(), 0o600) if hasattr(os, 'fchmod') else None
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, str(path))
        temporary = None
        if os.name == 'posix':
            directory_fd = os.open(str(path.parent), os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
    except Exception:
        raise DeployError('Private JSON state could not be saved atomically.')
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def load_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        raise DeployError('Cannot read the private JSON input/state file.')


def snapshot(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise DeployError('An active configuration is not a regular file.')
    data = path.read_bytes()
    return data, {'sha256': digest(data), 'inode': info.st_ino,
                  'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid,
                  'gid': info.st_gid}


def validate_token(token):
    if not isinstance(token, str) or not re.match(r'^[A-Za-z0-9_-]{43}$', token):
        raise DeployError('Invalid private path credential.')
    raw = base64.urlsafe_b64decode(token + '=')
    if len(raw) != 32 or base64.urlsafe_b64encode(raw).decode('ascii').rstrip('=') != token:
        raise DeployError('Invalid private path credential.')
    return token


def validate_public_key(value):
    if not isinstance(value, str) or '\n' in value.strip() or '\r' in value.strip():
        raise DeployError('An Ed25519 public key is required.')
    parts = value.strip().split()
    if len(parts) < 2 or parts[0] != 'ssh-ed25519':
        raise DeployError('An Ed25519 public key is required.')
    try:
        blob = base64.b64decode(parts[1], validate=True)
        algorithm_size = struct.unpack('>I', blob[:4])[0]
        offset = 4 + algorithm_size
        key_size = struct.unpack('>I', blob[offset:offset + 4])[0]
        if blob[4:offset] != b'ssh-ed25519' or key_size != 32 or len(blob) != offset + 4 + key_size:
            raise ValueError()
    except Exception:
        raise DeployError('Invalid Ed25519 public key encoding.')
    return parts[0] + ' ' + parts[1]


def settings(path):
    value = load_json(path)
    if not isinstance(value, dict) or set(value) != {'pathToken', 'publicKey'}:
        raise DeployError('Private settings must contain only pathToken and publicKey.')
    return validate_token(value['pathToken']), validate_public_key(value['publicKey'])


def candidates(caddy_data, ssh_data, token):
    validate_token(token)
    try:
        caddy_text = caddy_data.decode('utf-8')
        ssh_text = ssh_data.decode('utf-8')
    except UnicodeError:
        raise DeployError('Configuration encoding is not UTF-8.')
    baseline = HELMET_BASELINE.match(caddy_text)
    if (baseline is None or MARKER in caddy_text or MARKER in ssh_text
            or caddy_text.count('# BEGIN ' + HELMET_MARKER) != 1
            or caddy_text.count('# END ' + HELMET_MARKER) != 1):
        raise DeployError('Existing configuration does not match the reviewed baseline.')
    if token == baseline.group('helmet_token'):
        raise DeployError('Belt and helmet path credentials must be independent.')
    addition = '''    # BEGIN BELT DEVICE GATEWAY
    @belt_device path /%s/api/belt/index.php /%s/api/belt/config/index.php /%s/wsBelt
    handle @belt_device {
        reverse_proxy 10.255.1.1:28087
    }
    # END BELT DEVICE GATEWAY
''' % (token, token, token)
    insertion = baseline.start('fallback')
    return ((caddy_text[:insertion] + addition + caddy_text[insertion:]).encode('utf-8'),
            (ssh_text + ('' if ssh_text.endswith('\n') else '\n') + SSH_BLOCK).encode('utf-8'))


def run(state, label, args, input_data=None, required=True):
    # Never echo command output: Caddy diagnostics can contain the secret route.
    try:
        result = subprocess.run(args, input=input_data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=45, check=False)
    except Exception:
        raise DeployError('Command could not complete: ' + label)
    diagnostics = result.stdout + b'\n' + result.stderr
    diagnostics = re.sub(rb'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])',
                         b'[REDACTED-PATH-CREDENTIAL]', diagnostics)
    private_write(state / (label + '.log'), diagnostics)
    if required and result.returncode != 0:
        raise DeployError('Command failed: ' + label + ' (private diagnostic log saved).')
    return result


def require_absent_user():
    try:
        pwd.getpwnam(USER)
    except KeyError:
        pass
    else:
        raise DeployError('The dedicated username already exists; refusing to adopt it.')
    try:
        grp.getgrnam(USER)
    except KeyError:
        pass
    else:
        raise DeployError('The dedicated group already exists; refusing to adopt it.')
    if HOME.exists() or HOME.is_symlink():
        raise DeployError('The dedicated home path already exists.')


def port_available():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        # Bind only, never listen. Also verifies the specified bridge exists.
        probe.bind((BRIDGE, PORT))
    except OSError:
        raise DeployError('The bridge address is absent or the dedicated port is occupied.')
    finally:
        probe.close()


def website_healthy():
    conn = None
    sock = None
    try:
        sock = socket.create_connection(('127.0.0.1', 443), timeout=12)
        wrapped = ssl.create_default_context().wrap_socket(sock, server_hostname=DOMAIN)
        conn = http.client.HTTPConnection(DOMAIN, timeout=12)
        conn.sock = wrapped
        conn.request('GET', '/', headers={'Host': DOMAIN, 'Connection': 'close'})
        status_code = conn.getresponse().status
        if status_code < 200 or status_code >= 400:
            raise ValueError()
    except Exception:
        raise DeployError('The existing HTTPS website did not pass its local TLS/HTTP check.')
    finally:
        if conn is not None:
            conn.close()
        elif sock is not None:
            sock.close()


def server_ready(state):
    running = run(state, 'container-running', ['docker', 'inspect', '--format', '{{.State.Running}}', CONTAINER])
    if running.stdout.strip() != b'true':
        raise DeployError('The existing Caddy container is not running.')
    mounts = run(state, 'container-mounts', ['docker', 'inspect', '--format', '{{json .Mounts}}', CONTAINER])
    try:
        correct = any(item.get('Type') == 'bind' and item.get('Source') == str(CADDY)
                      and item.get('Destination') == '/etc/caddy/Caddyfile'
                      for item in json.loads(mounts.stdout.decode('utf-8')))
    except Exception:
        correct = False
    if not correct:
        raise DeployError('The reviewed single-file Caddy mount was not found.')
    inode = run(state, 'container-config-inode', ['docker', 'exec', CONTAINER,
                'stat', '-c', '%i', '/etc/caddy/Caddyfile'])
    if inode.stdout.strip() != str(CADDY.stat().st_ino).encode('ascii'):
        raise DeployError('Caddy is bound to a different inode; refusing to modify the active configuration.')
    website_healthy()
    for service in ['sshd.service', 'ssh.service']:
        result = run(state, 'service-' + service, ['systemctl', 'is-active', '--quiet', service], required=False)
        if result.returncode == 0:
            return service
    raise DeployError('No supported active SSH systemd service was found.')


def effective_ssh(state, label, config_path, username):
    return run(state, label, ['/usr/sbin/sshd', '-T', '-f', str(config_path), '-C',
               'user=' + username + ',host=localhost,addr=127.0.0.1,laddr=127.0.0.1,lport=22']).stdout


def validate_candidates(state, caddy_candidate, ssh_candidate, phase):
    run(state, phase + '-caddy-validate', ['docker', 'exec', '-i', CONTAINER, 'caddy', 'validate',
        '--config', '/dev/stdin', '--adapter', 'caddyfile'], input_data=caddy_candidate)
    path = state / (phase + '.sshd_config')
    private_write(path, ssh_candidate)
    run(state, phase + '-sshd-syntax', ['/usr/sbin/sshd', '-t', '-f', str(path)])
    effective = effective_ssh(state, phase + '-sshd-effective', path, USER)
    actual = dict(line.split(' ', 1) for line in effective.decode('utf-8').splitlines() if ' ' in line)
    if any(actual.get(key) != value for key, value in EXPECTED_SSH.items()):
        raise DeployError('The effective dedicated-user SSH restrictions differ from the reviewed policy.')
    if actual.get('usepam') != 'yes':
        raise DeployError('This locked system-account setup requires an existing UsePAM yes policy.')
    for username in ['root', 'admin', 'helmet-tunnel']:
        before = effective_ssh(state, phase + '-before-' + username, SSHD, username)
        after = effective_ssh(state, phase + '-after-' + username, path, username)
        if before != after:
            raise DeployError('Candidate changes an existing administrator or helmet SSH policy.')


def preview(state):
    private_dir(state)
    if (state / 'preview.json').exists() or (state / 'deployment.json').exists():
        raise DeployError('Use a new private state directory for each preview.')
    require_absent_user()
    port_available()
    service = server_ready(state)
    caddy_data, caddy_meta = snapshot(CADDY)
    ssh_data, ssh_meta = snapshot(SSHD)
    caddy_candidate, ssh_candidate = candidates(caddy_data, ssh_data, PLACEHOLDER_TOKEN)
    private_write(state / 'preview.Caddyfile', caddy_candidate)
    validate_candidates(state, caddy_candidate, ssh_candidate, 'preview')
    private_write(state / 'original.Caddyfile', caddy_data)
    private_write(state / 'original.sshd_config', ssh_data)
    plan = {'version': 1, 'deploymentKind': 'belt-device-gateway',
            'dedicatedUser': USER, 'listenPort': PORT,
            'targetIp': TARGET_IP, 'domain': DOMAIN, 'service': service,
            'scriptSha256': digest(Path(__file__).read_bytes()),
            'original': {'caddy': caddy_meta, 'sshd': ssh_meta},
            'createdAtUtc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    save_json(state / 'preview.json', plan)
    print('PREVIEW OK: candidate syntax and existing website verified; no active configuration or account changed.')
    print('Target: ' + TARGET_IP + '; existing domain: ' + DOMAIN + '; private state: ' + str(state))


def require_plan_identity(plan):
    if (plan.get('version') != 1 or plan.get('targetIp') != TARGET_IP or plan.get('domain') != DOMAIN
            or plan.get('deploymentKind') != 'belt-device-gateway'
            or plan.get('dedicatedUser') != USER or plan.get('listenPort') != PORT
            or plan.get('service') not in ('sshd.service', 'ssh.service')):
        raise DeployError('Preview target does not match this deployment.')


def check_baseline(plan, state):
    require_plan_identity(plan)
    if plan.get('scriptSha256') != digest(Path(__file__).read_bytes()):
        raise DeployError('Deployment script changed after preview; preview again in a new directory.')
    for name, path, backup in [('caddy', CADDY, 'original.Caddyfile'), ('sshd', SSHD, 'original.sshd_config')]:
        data, meta = snapshot(path)
        if meta != plan['original'][name] or digest((state / backup).read_bytes()) != digest(data):
            raise DeployError('An active configuration or its metadata changed after preview.')


def write_in_place(path, expected_hash, data, expected_inode=None):
    # Keep the bind-mounted inode. If an incomplete write fails, restore on this fd.
    fd = os.open(str(path), os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(fd, 'r+b') as out:
        if fcntl is not None:
            fcntl.flock(out.fileno(), fcntl.LOCK_EX)
        if expected_inode is not None and os.fstat(out.fileno()).st_ino != expected_inode:
            raise DeployError('Concurrent inode replacement detected before writing.')
        original = out.read()
        if digest(original) != expected_hash:
            raise DeployError('Concurrent configuration change detected before writing.')
        try:
            out.seek(0)
            out.write(data)
            out.truncate()
            out.flush()
            os.fsync(out.fileno())
        except Exception:
            out.seek(0)
            out.write(original)
            out.truncate()
            out.flush()
            os.fsync(out.fileno())
            raise DeployError('Configuration write failed; original bytes restored in place.')


def reload_caddy(state, label):
    run(state, label, ['docker', 'exec', CONTAINER, 'caddy', 'reload', '--config',
                     '/etc/caddy/Caddyfile', '--adapter', 'caddyfile'])


def archive_originals(state):
    archive = state / 'original-configurations.tar.gz'
    if archive.exists():
        raise DeployError('Backup archive already exists; refusing to overwrite it.')
    with tarfile.open(str(archive), 'w:gz') as out:
        for name in ['original.Caddyfile', 'original.sshd_config', 'preview.json']:
            out.add(str(state / name), arcname=name, recursive=False)
    os.chmod(str(archive), 0o600)


def apply(state, settings_path):
    plan = load_json(state / 'preview.json')
    if (state / 'deployment.json').exists():
        raise DeployError('This state directory already has a deployment transaction.')
    token, public_key = settings(settings_path)
    check_baseline(plan, state)
    require_absent_user()
    port_available()
    if server_ready(state) != plan['service']:
        raise DeployError('The active SSH service changed after preview.')
    caddy_candidate, ssh_candidate = candidates((state / 'original.Caddyfile').read_bytes(),
                                                (state / 'original.sshd_config').read_bytes(), token)
    private_write(state / 'apply.Caddyfile', caddy_candidate)
    validate_candidates(state, caddy_candidate, ssh_candidate, 'apply')
    check_baseline(plan, state)
    archive_originals(state)
    key_data = ('restrict,port-forwarding,permitlisten="10.255.1.1:28087",command="/bin/false" '
                + public_key + '\n').encode('ascii')
    transaction = {'status': 'prepared', 'accountUid': None, 'accountGid': None,
                   'keySha256': digest(key_data), 'service': plan['service'],
                   'deployed': {'caddy': digest(caddy_candidate), 'sshd': digest(ssh_candidate)}}
    save_json(state / 'deployment.json', transaction)
    try:
        run(state, 'create-dedicated-user', ['useradd', '--system', '--user-group', '--no-create-home',
            '--home-dir', str(HOME), '--shell', '/bin/sh', USER])
        account = pwd.getpwnam(USER)
        transaction['accountUid'] = account.pw_uid
        transaction['accountGid'] = account.pw_gid
        transaction['status'] = 'account-created'
        save_json(state / 'deployment.json', transaction)
        if account.pw_dir != str(HOME) or HOME.exists() or HOME.is_symlink():
            raise DeployError('Unexpected newly created account home.')
        HOME.mkdir(mode=0o700)
        os.chown(str(HOME), account.pw_uid, account.pw_gid)
        ssh_dir = HOME / '.ssh'
        ssh_dir.mkdir(mode=0o700)
        os.chown(str(ssh_dir), account.pw_uid, account.pw_gid)
        # Account/group now exist: evaluate Match rules again before any reload.
        validate_candidates(state, caddy_candidate, ssh_candidate, 'account')
        write_in_place(SSHD, plan['original']['sshd']['sha256'], ssh_candidate, plan['original']['sshd']['inode'])
        run(state, 'reload-sshd', ['systemctl', 'reload', plan['service']])
        # Enable this key only after the remote-only restrictions are active.
        private_write(ssh_dir / 'authorized_keys', key_data)
        os.chown(str(ssh_dir / 'authorized_keys'), account.pw_uid, account.pw_gid)
        write_in_place(CADDY, plan['original']['caddy']['sha256'], caddy_candidate, plan['original']['caddy']['inode'])
        reload_caddy(state, 'reload-caddy')
        website_healthy()
        transaction['status'] = 'applied'
        save_json(state / 'deployment.json', transaction)
    except Exception:
        try:
            rollback(state)
        except Exception:
            raise DeployError('Apply failed; rollback needs attention. Private state and backups retained.')
        raise DeployError('Apply failed; this deployment was rolled back. Private diagnostics retained.')
    print('APPLY OK: dedicated account and exact device routes installed; existing website healthy.')
    print('No tunnel was started and no firewall, existing account, application container or backend was changed.')


def rollback(state):
    plan = load_json(state / 'preview.json')
    # Never consume the adjacent helmet deployment's backups/transaction by mistake.
    require_plan_identity(plan)
    transaction = load_json(state / 'deployment.json')
    if transaction.get('service') != plan['service']:
        raise DeployError('Deployment transaction does not match its preview.')
    errors = []
    uid = transaction.get('accountUid')
    account = None
    cleanup_allowed = True
    if uid is None:
        try:
            require_absent_user()
        except Exception:
            errors.append('untracked partial account creation; inspect before cleanup')
    else:
        try:
            try:
                account = pwd.getpwnam(USER)
            except KeyError:
                pass
            if account is not None and (account.pw_uid != uid or account.pw_gid != transaction['accountGid'] or account.pw_dir != str(HOME)):
                raise DeployError('Dedicated account identity changed.')
            key_path = HOME / '.ssh' / 'authorized_keys'
            if HOME.is_symlink() or (HOME / '.ssh').is_symlink() or key_path.is_symlink():
                raise DeployError('Dedicated account path became a symlink.')
            if key_path.exists():
                if digest(key_path.read_bytes()) != transaction['keySha256']:
                    raise DeployError('Dedicated public key changed.')
                key_path.unlink()
            if account is not None:
                result = run(state, 'stop-dedicated-processes', ['pkill', '-TERM', '-u', str(uid)], required=False)
                if result.returncode not in (0, 1):
                    raise DeployError('Cannot stop the dedicated account processes.')
            if HOME.exists() and set(item.name for item in HOME.iterdir()) - {'.ssh'}:
                raise DeployError('Dedicated home has later additions.')
            if (HOME / '.ssh').exists() and any((HOME / '.ssh').iterdir()):
                raise DeployError('Dedicated SSH directory has later additions.')
        except Exception:
            cleanup_allowed = False
            errors.append('dedicated account revocation')
    restored = []
    for name, path, backup in [('caddy', CADDY, 'original.Caddyfile'), ('sshd', SSHD, 'original.sshd_config')]:
        if name == 'sshd' and not cleanup_allowed:
            errors.append('sshd restrictions retained pending account revocation')
            continue
        try:
            data, meta = snapshot(path)
            original = (state / backup).read_bytes()
            if digest(original) != plan['original'][name]['sha256']:
                raise DeployError('Backup integrity mismatch.')
            if meta['inode'] != plan['original'][name]['inode']:
                raise DeployError('Later configuration change detected; refusing to overwrite it.')
            if meta['sha256'] != digest(original):
                if meta['sha256'] != transaction['deployed'][name]:
                    raise DeployError('Later configuration change detected; refusing to overwrite it.')
                write_in_place(path, meta['sha256'], original, plan['original'][name]['inode'])
            # A previous rollback may have restored bytes but failed its reload.
            restored.append(name)
        except Exception:
            errors.append(name + ' restore')
    for name in restored:
        try:
            if name == 'caddy':
                reload_caddy(state, 'rollback-caddy-reload')
            else:
                run(state, 'rollback-sshd-syntax', ['/usr/sbin/sshd', '-t'])
                run(state, 'rollback-sshd-reload', ['systemctl', 'reload', transaction['service']])
        except Exception:
            errors.append(name + ' reload')
    if uid is not None and cleanup_allowed:
        try:
            # No recursive deletion: preserve any later additions to the home.
            ssh_dir = HOME / '.ssh'
            if HOME.exists():
                if set(item.name for item in HOME.iterdir()) - {'.ssh'}:
                    raise DeployError('Dedicated home has later additions; preserving them.')
                if ssh_dir.exists() and any(ssh_dir.iterdir()):
                    raise DeployError('Dedicated SSH directory has later additions; preserving them.')
            if account is not None:
                run(state, 'remove-dedicated-user', ['userdel', USER])
            if ssh_dir.exists():
                ssh_dir.rmdir()
            if HOME.exists():
                HOME.rmdir()
            try:
                group = grp.getgrnam(USER)
            except KeyError:
                group = None
            if group is not None:
                if group.gr_gid != transaction['accountGid'] or group.gr_mem or any(
                        entry.pw_gid == group.gr_gid for entry in pwd.getpwall()):
                    raise DeployError('Dedicated group changed; refusing to remove it.')
                run(state, 'remove-dedicated-group', ['groupdel', USER])
        except Exception:
            errors.append('dedicated account cleanup')
    transaction['status'] = 'rollback-needs-attention' if errors else 'rolled-back'
    transaction['rollbackErrors'] = errors
    save_json(state / 'deployment.json', transaction)
    if errors:
        raise DeployError('Rollback incomplete: ' + ', '.join(errors) + '. Later changes were preserved.')
    print('ROLLBACK OK: original configuration restored in place; owned dedicated resources removed.')


def main():
    parser = argparse.ArgumentParser(description='Preview or apply the reviewed single-belt cloud entry.')
    parser.add_argument('action', choices=['preview', 'apply', 'rollback'])
    parser.add_argument('--state-dir', required=True, type=Path)
    parser.add_argument('--settings', type=Path, help='Private JSON file; required only for apply.')
    args = parser.parse_args()
    if os.name != 'posix' or pwd is None or os.geteuid() != 0:
        raise DeployError('Run this server-side script as root on Linux; local tests do not require root.')
    os.umask(0o077)
    state = args.state_dir.absolute()
    # Serialize this deployment even when two callers choose different state dirs.
    lock_path = '/var/lock/belt-device-gateway-deploy.lock'
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'a+b') as control:
        try:
            fcntl.flock(control.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise DeployError('Another belt cloud deployment operation is in progress.')
        if args.action == 'preview':
            preview(state)
        elif args.action == 'apply':
            if args.settings is None:
                raise DeployError('Apply requires a private --settings JSON file.')
            apply(state, args.settings)
        else:
            rollback(state)


if __name__ == '__main__':
    try:
        main()
    except DeployError as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('ERROR: operation stopped; inspect private state without sharing credentials.', file=sys.stderr)
        sys.exit(1)
