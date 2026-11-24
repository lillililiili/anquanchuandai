"""Run the real coturn image, two relay allocations and both client transports offline."""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import time
import uuid


IMAGE = 'coturn/coturn:4.6.3'
WRAPPER = Path(__file__).resolve().parents[1] / 'turn-bridge.sh'


def docker(*args, check=True, timeout=55):
    run = subprocess.run(['docker', *map(str, args)], stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, encoding='utf-8', errors='replace', timeout=timeout)
    if check and run.returncode:
        raise RuntimeError('Docker ' + str(args[0]) + ' failed: ' + run.stdout[-550:])
    return run


def traffic(network, address, secret, flags):
    username = str(int(time.time()) + 90) + ':pair-' + secrets.token_hex(6)
    password = base64.b64encode(hmac.new(secret.encode(), username.encode(), hashlib.sha1).digest()).decode()
    result = docker('run', '--rm', '--network', network, '--entrypoint', 'turnutils_uclient', IMAGE,
                    '-v', '-c', '-y', '-m', '2', '-n', '12', '-l', '192', *flags,
                    '-p', '3478', '-u', username, '-w', password, address, check=False)
    totals = re.findall(r'tot_send_msgs=(\d+)\s*,\s*tot_recv_msgs=(\d+)', result.stdout)
    sent, received = map(int, totals[-1]) if totals else (0, 0)
    return result.returncode, sent, received, 'Forbidden IP' in result.stdout


def main():
    network = 'wear-turn-qa-' + uuid.uuid4().hex[:12]
    server = network + '-server'
    secret = secrets.token_hex(32)
    config = [
        'listening-port=3478', 'listening-ip=0.0.0.0', 'external-ip=192.0.2.79',
        'min-port=49160', 'max-port=49200', 'realm=wear-qa.invalid', 'use-auth-secret',
        'static-auth-secret=' + secret, 'fingerprint', 'no-tls', 'no-dtls', 'no-cli',
        'no-multicast-peers', 'no-loopback-peers', 'denied-peer-ip=10.0.0.0-10.255.255.255',
        'denied-peer-ip=172.16.0.0-172.31.255.255', 'denied-peer-ip=192.168.0.0-192.168.255.255',
        'denied-peer-ip=127.0.0.0-127.255.255.255', 'denied-peer-ip=169.254.0.0-169.254.255.255',
        'user-quota=4', 'no-software-attribute',
    ]
    with tempfile.TemporaryDirectory() as folder:
        conf = Path(folder) / 'turn.conf'
        conf.write_bytes(('\n'.join(config) + '\n').encode())
        os.chmod(conf, 0o600)
        docker('network', 'create', '--internal', network)
        try:
            for fixed in (False, True):
                command = ['--entrypoint', 'turnserver', IMAGE, '-c', '/etc/helmet-turn.conf']
                if fixed:
                    command = ['--mount', 'type=bind,src=' + str(WRAPPER) + ',dst=/turn.sh,readonly',
                               '--tmpfs', '/run/helmet-turn:mode=0700', '--entrypoint', '/bin/sh', IMAGE, '/turn.sh']
                docker('run', '-d', '--name', server, '--network', network, '--user', '0:0',
                       '--cap-drop', 'ALL', '--cap-add', 'NET_BIND_SERVICE', '--security-opt', 'no-new-privileges',
                       '--mount', 'type=bind,src=' + str(conf) + ',dst=/etc/helmet-turn.conf,readonly', *command)
                try:
                    for _ in range(25):
                        if docker('exec', server, 'sh', '-c', "grep -qi ':0D96 ' /proc/net/udp", check=False).returncode == 0:
                            break
                        time.sleep(.25)
                    private = json.loads(docker('inspect', server).stdout)[0]['NetworkSettings']['Networks'][network]['IPAddress']
                    for label, flags in ([('original', [])] if not fixed else
                                         [('UDP', []), ('TCP', ['-t']), ('Send indication', ['-s'])]):
                        code, sent, received, forbidden = traffic(network, private, secret, flags)
                        print(label, 'exit', code, 'sent', sent, 'received', received, 'forbidden', forbidden, flush=True)
                        if fixed:
                            assert code == 0 and sent >= 12 and sent == received
                        else:
                            assert forbidden and received == 0
                finally:
                    docker('rm', '-f', server, check=False)
        finally:
            docker('network', 'rm', network)


if __name__ == '__main__':
    main()
