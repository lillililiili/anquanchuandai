"""Read-only cloud identity/resource/port checks. Does not print environment/configuration."""
import json
import os
import socket
import subprocess
from pathlib import Path
from cloud_identity import authorized_public_ip

EXPECTED = '39.106.212.138'
def run(args):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    if p.returncode: raise RuntimeError('Prerequisite command failed: ' + args[0])
    return p.stdout.decode('utf-8').strip()

def check():
    if os.name != 'posix' or os.geteuid() != 0: raise RuntimeError('Linux root required')
    actual = authorized_public_ip()
    if actual != EXPECTED: raise RuntimeError('Public IP does not match the authorized server')
    mem = dict(line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())
    available = int(mem['MemAvailable'].strip().split()[0]) // 1024
    swap_free = int(mem['SwapFree'].strip().split()[0]) // 1024
    disk = os.statvfs('/home/admin'); free_gb = disk.f_bavail*disk.f_frsize/1024**3
    conflicts=[]
    for port in [1935,3478,5060,5066,8021,1985,8080,18190,18192,28088]:
        with socket.socket() as sock:
            try: sock.bind(('0.0.0.0',port))
            except OSError: conflicts.append(port)
    udp_conflicts=[]
    for port in [3478,8000]+list(range(16384,16584))+list(range(49160,49201)):
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
            try:sock.bind(('0.0.0.0',port))
            except OSError:udp_conflicts.append(port)
    inventory=run(['docker','ps','--format','{{.Names}} | {{.Image}} | {{.Ports}}']).splitlines()
    print(json.dumps({'publicIp':actual,'availableMemoryMiB':available,'freeSwapMiB':swap_free,'freeDiskGiB':round(free_gb,1),
      'tcpPortConflicts':conflicts,'udpPortConflicts':udp_conflicts,'containers':inventory,'compose':run(['docker','compose','version','--short'])},ensure_ascii=False))
    if conflicts or udp_conflicts: raise RuntimeError('Reviewed media/business ports are in use; do not take over another service')
    if available < 1800 or swap_free < 1024 or free_gb < 16: raise RuntimeError('Insufficient headroom for single-helmet media build/runtime; preserve existing services')
if __name__=='__main__': check()
