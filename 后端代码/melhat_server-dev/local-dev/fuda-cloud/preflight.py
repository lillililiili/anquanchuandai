"""Read-only Linux cutover checks. Does not start services, change routes or migrate data."""
import argparse,errno,json,os,platform,shutil,socket,stat,subprocess
from pathlib import Path

BRIDGE='10.255.1.1'

def endpoints(production=False):
    if not production:return [('127.0.0.1',18089)]
    return [('127.0.0.1',p) for p in (18084,18086,18087,18088)]+[(BRIDGE,p) for p in (28086,28087,28088,28089)]

def probe(host,port):
    with socket.socket() as s:
        try:s.bind((host,port));return {'host':host,'port':port,'status':'free'}
        except OSError as error:
            return {'host':host,'port':port,'status':'occupied' if error.errno==errno.EADDRINUSE else 'unavailable'}

def bridge_present():
    try:
        r=subprocess.run(['ip','-j','-4','addr','show'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5,check=True)
        return any(a.get('local')==BRIDGE for interface in json.loads(r.stdout) for a in interface.get('addr_info',[]))
    except (OSError,ValueError,subprocess.SubprocessError):return False

def private_files(config_dir,production):
    role='production' if production else 'staging';directory=Path(config_dir)
    paths=[directory/('.env.'+role),directory/'.private'/role/'fuda-api.yml']
    if production:paths += [directory/'.private'/role/name for name in ('device-runtime.yml','helmet-gateway.json','belt-gateway.json')]
    issues=[]
    for path in paths:
        if path.is_symlink() or not path.is_file():issues.append({'file':path.name,'problem':'missing_or_not_regular'});continue
        st=path.stat()
        if os.name=='posix' and stat.S_IMODE(st.st_mode)!=0o600:issues.append({'file':path.name,'problem':'requires_mode_0600'})
        if os.name=='posix' and path.name.endswith('gateway.json') and st.st_uid!=1000:issues.append({'file':path.name,'problem':'requires_container_node_uid_1000'})
    return issues

def inspect(root,production=False,config_dir=None):
    root=Path(root).resolve();free=shutil.disk_usage(root).free;memory={}
    if Path('/proc/meminfo').exists():
        for line in Path('/proc/meminfo').read_text().splitlines():
            key,value=line.split(':',1);memory[key]=int(value.strip().split()[0])*1024
    ports=[probe(host,port) for host,port in endpoints(production)]
    bridge_ok=bridge_present() if production else None
    files=private_files(config_dir or Path(__file__).resolve().parent,production)
    linux=platform.system()=='Linux'
    return {'role':'production' if production else 'staging','linuxHost':linux,'cpuCount':os.cpu_count(),
        'availableMemoryBytes':memory.get('MemAvailable'),'freeDiskBytes':free,'endpoints':ports,
        'productionBridgePresent':bridge_ok,'privateFileIssues':files,'minimumSizingOnly':True,
        'ready':linux and all(p['status']=='free' for p in ports) and (not production or bridge_ok) and not files and free>=20*1024**3 and memory.get('MemAvailable',0)>=3*1024**3,
        'notes':['Production check belongs after the planned old-listener shutdown; occupied ports never authorize automatic termination.',
          'This cannot prove a remote old backend stopped writing; record that separately before cutover.',
          'Staging has only its query gateway port; its backend has no host port or external route.',
          'No migration, service startup, or route change was performed.']}

if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--root',default='.');a.add_argument('--production',action='store_true');a.add_argument('--config-dir',default=str(Path(__file__).resolve().parent));args=a.parse_args()
    result=inspect(args.root,args.production,args.config_dir);print(json.dumps(result,indent=2));raise SystemExit(0 if result['ready'] else 2)
