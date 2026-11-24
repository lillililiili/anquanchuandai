"""Preview, publish or roll back the isolated TURN relay on the original cloud host."""
from __future__ import print_function
import argparse
import base64
import fcntl
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile
import time

ROOT = Path('/opt/helmet-wear/helmet-media')
COMPOSE = ROOT / 'compose.yml'
WRAPPER = ROOT / 'turn-bridge.sh'
CONTAINER = 'helmet-media-turn-1'
BACKUPS = Path('/var/backups/helmet-turn-bridge')
IMAGE = 'coturn/coturn:4.6.3'
NETWORK = 'helmet-media_turn'
HERE = Path(__file__).resolve().parent


def require(value, why):
    if not value:
        raise RuntimeError(why)


def run(args, timeout=60, check=True, combined=False):
    result = subprocess.run([str(a) for a in args], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT if combined else subprocess.PIPE, timeout=timeout)
    if check and result.returncode:
        # Some docker commands handle a short-lived credential. Never echo argv.
        raise RuntimeError('Command failed: ' + str(args[0]) + ' (' + str(result.returncode) + ')')
    return result.stdout.decode('utf-8', 'replace')


def inspect():
    obj = json.loads(run(['docker','inspect',CONTAINER]))[0]
    labels = obj['Config']['Labels']
    require(labels['com.docker.compose.project'] == 'helmet-media' and
            labels['com.docker.compose.project.config_files'] == str(COMPOSE) and
            obj['Config']['Image'] == IMAGE, 'Unexpected TURN service')
    return obj


def configuration(path):
    raw = run(['docker','compose','--project-directory',ROOT,'-p','helmet-media','-f',path,'config','--format','json'])
    return json.loads(raw)


def candidate(data):
    match = re.search(r'(?ms)^  turn:\n.*?(?=^  [\w-]+:\n|^\S|\Z)', data)
    require(match is not None, 'No TURN section')
    block = match.group()
    edits = [
        ('    network_mode: host\n', '    networks: [turn]\n    ports:\n      - "3478:3478/udp"\n      - "3478:3478/tcp"\n      - "49160-49200:49160-49200/udp"\n'),
        ('    command: [-c, /etc/helmet-turn.conf]\n', '    entrypoint: [/bin/sh, /usr/local/bin/helmet-turn-bridge.sh]\n    command: []\n'),
        ('      - ./.local/turn.conf:/etc/helmet-turn.conf:ro\n', '      - ./.local/turn.conf:/etc/helmet-turn.conf:ro\n      - ./turn-bridge.sh:/usr/local/bin/helmet-turn-bridge.sh:ro\n    tmpfs:\n      - /run/helmet-turn:mode=0700\n'),
    ]
    for old, new in edits:
        require(block.count(old) == 1, 'Original TURN service differs from reviewed settings')
        block = block.replace(old,new)
    data = data[:match.start()] + block + data[match.end():]
    if re.search(r'(?m)^networks:\s*$',data):
        require(not re.search(r'(?ms)^networks:\n.*?^  turn:',data), 'Network name already present')
        return re.sub(r'(?m)^networks:\s*$', 'networks:\n  turn:\n    driver: bridge',data,count=1)
    return data.rstrip() + '\n\nnetworks:\n  turn:\n    driver: bridge\n'


def atomic(path, data, mode):
    fd, name = tempfile.mkstemp(dir=str(path.parent))
    try:
        with os.fdopen(fd,'wb') as f:
            f.write(data)
            os.fchmod(f.fileno(),mode)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name,str(path))
    finally:
        if os.path.exists(name):
            os.unlink(name)


def others():
    return run(['docker','ps','--filter','label=com.docker.compose.project=helmet-media',
                '--format','{{.Names}} {{.ID}}']).splitlines()


def helpers():
    return sorted(row for row in others() if not row.startswith(CONTAINER+' '))


def relay_sockets(obj):
    pid = int(obj['State']['Pid'])
    require(pid > 1,'TURN is not running')
    owned = set()
    for fd in (Path('/proc') / str(pid) / 'fd').iterdir():
        try:
            target = os.readlink(str(fd))
            if target.startswith('socket:['): owned.add(target[8:-1])
        except FileNotFoundError:
            pass
    count = 0
    for proto in ('udp','udp6','tcp','tcp6'):
        for line in (Path('/proc') / str(pid) / 'net' / proto).read_text().splitlines()[1:]:
            cols = line.split()
            if len(cols)>9 and cols[9] in owned and 49160<=int(cols[1].split(':')[1],16)<=49200:
                count += 1
    return count


def up():
    run(['docker','compose','-p','helmet-media','-f',COMPOSE,'up','-d','--no-build',
         '--no-deps','--pull','never','turn'],timeout=100)


def routes():
    conn = http.client.HTTPConnection('127.0.0.1',18088,timeout=4)
    try:
        conn.request('GET','/api/guardian/v1/mobile/identity')
        require(conn.getresponse().status==401,'Original mobile authentication failed')
    finally:
        conn.close()


def traffic(obj, key):
    net = json.loads(run(['docker','network','inspect',NETWORK]))[0]
    require(set(net['Containers']) == {obj['Id']},'TURN bridge must be dedicated')
    addr = obj['NetworkSettings']['Networks'][NETWORK]['IPAddress']
    require(addr and net['Driver']=='bridge','Missing isolated TURN address')
    for _ in range(30):
        if '0D96' in run(['docker','exec',CONTAINER,'cat','/proc/net/udp'],check=False): break
        time.sleep(.3)
    for label,opts in [('UDP',[]),('TCP',['-t'])]:
        user=str(int(time.time())+90)+':release-'+secrets.token_hex(5)
        password=base64.b64encode(hmac.new(key,user.encode(),hashlib.sha1).digest()).decode()
        log = run(['docker','run','--rm','--network',NETWORK,'--entrypoint','turnutils_uclient',IMAGE,
                   '-v','-c','-y','-m','2','-n','8','-l','192']+opts+['-u',user,'-w',password,addr],combined=True)
        totals = re.findall(r'tot_send_msgs=(\d+)\s*,\s*tot_recv_msgs=(\d+)',log)
        require(totals and int(totals[-1][0])>=8 and totals[-1][0]==totals[-1][1],label+' bidirectional media failed')
        print(label,'relay-to-relay sent/received',*totals[-1],flush=True)


def restore(folder):
    old=(folder/'compose.yml').read_bytes()
    record=json.loads((folder/'receipt.json').read_text())
    require(hashlib.sha256(old).hexdigest()==record['original'],'Backup integrity failed')
    require(hashlib.sha256(COMPOSE.read_bytes()).hexdigest()==record['candidate'],'Compose changed after release')
    atomic(COMPOSE,old,record['mode'])
    up()
    if WRAPPER.is_file() and hashlib.sha256(WRAPPER.read_bytes()).hexdigest()==record['wrapper']:
        WRAPPER.unlink()
    routes()
    print('ORIGINAL_TURN_RESTORED',flush=True)


def main():
    p=argparse.ArgumentParser()
    group=p.add_mutually_exclusive_group()
    group.add_argument('--apply',action='store_true')
    group.add_argument('--rollback',type=Path)
    args=p.parse_args()
    obj=inspect()
    config=ROOT/'.local/turn.conf'
    entries=config.read_text().splitlines()
    require('external-ip=39.106.212.138' in entries and 'realm=lingzhiaide.com' in entries and
            'denied-peer-ip=172.16.0.0-172.31.255.255' in entries and 'no-loopback-peers' in entries and
            'use-auth-secret' in entries and 'min-port=49160' in entries and 'max-port=49200' in entries,
            'Unexpected cloud relay identity or policy')
    routes()
    if args.rollback:
        folder=args.rollback.resolve()
        require(folder.parent==BACKUPS and folder.name.startswith('update-'),'Unexpected backup directory')
        restore(folder)
        return
    wrap=(HERE/'turn-bridge.sh').read_bytes()
    if obj['HostConfig']['NetworkMode']==NETWORK:
        require(WRAPPER.read_bytes()==wrap,'Installed wrapper differs')
        print('ALREADY_INSTALLED',flush=True)
        return
    require(obj['HostConfig']['NetworkMode']=='host' and not WRAPPER.exists(),'Unexpected original runtime')
    original=COMPOSE.read_bytes()
    new=candidate(original.decode()).encode()
    before=configuration(COMPOSE)
    with tempfile.TemporaryDirectory() as stage:
        reviewed=Path(stage)/'compose.yml'
        reviewed.write_bytes(new)
        after=configuration(reviewed)
    for name,service in before['services'].items():
        if name!='turn': require(service==after['services'][name], 'Unrelated service changed: '+name)
    require(set(before['services'])==set(after['services']), 'Unexpected service set')
    skip={'command','entrypoint','network_mode','networks','ports','volumes','tmpfs'}
    require({k:v for k,v in before['services']['turn'].items() if k not in skip}==
            {k:v for k,v in after['services']['turn'].items() if k not in skip}, 'Unexpected TURN changes')
    count=relay_sockets(obj)
    print('PREFLIGHT_OK active_relay_sockets='+str(count)+' public_ports=unchanged other_services=unchanged',flush=True)
    if not args.apply: return
    require(count==0,'Active relay allocation; retry when idle')
    require(not run(['docker','network','ls','--format','{{.Name}}']).splitlines().count(NETWORK) or
            not json.loads(run(['docker','network','inspect',NETWORK]))[0]['Containers'], 'Target bridge occupied')
    unchanged=helpers()
    mode=COMPOSE.stat().st_mode & 0o777
    BACKUPS.mkdir(mode=0o700,parents=True,exist_ok=True)
    folder=Path(tempfile.mkdtemp(prefix='update-',dir=str(BACKUPS)))
    shutil.copy2(str(COMPOSE),str(folder/'compose.yml'))
    record={'mode':mode,'original':hashlib.sha256(original).hexdigest(),'candidate':hashlib.sha256(new).hexdigest(),
            'wrapper':hashlib.sha256(wrap).hexdigest()}
    (folder/'receipt.json').write_text(json.dumps(record))
    require(COMPOSE.read_bytes()==original and relay_sockets(inspect())==0,'Source or call state changed')
    atomic(WRAPPER,wrap,0o644)
    atomic(COMPOSE,new,mode)
    try:
        up()
        fixed=inspect()
        require(set(fixed['NetworkSettings']['Networks'])=={NETWORK},'Relay shares another service network')
        key=next(x.split('=',1)[1].encode() for x in entries if x.startswith('static-auth-secret='))
        traffic(fixed,key)
        routes()
        require(helpers()==unchanged,'Companion service changed')
        print('PUBLISHED original_gateway=healthy helmet_services=healthy backup='+str(folder),flush=True)
    except BaseException:
        restore(folder)
        raise


if __name__=='__main__':
    with open('/var/lock/helmet-turn-bridge-release.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        main()
