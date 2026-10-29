"""Prepare only a new restricted tunnel public key and the two upload archives."""
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
from pathlib import Path

media=Path(__file__).resolve().parents[1]; base=media.parent
private=media/'.local'; wear=base/'wear-api-gateway/.local'
private.mkdir(parents=True,exist_ok=True);wear.mkdir(parents=True,exist_ok=True)
key=wear/'wear_api_tunnel_ed25519'
if not key.exists():
    tool=str(Path(os.environ.get('WINDIR','C:/Windows'))/'System32/OpenSSH/ssh-keygen.exe') if os.name=='nt' else 'ssh-keygen'
    subprocess.run([tool,'-t','ed25519','-N','','-C','wear-api-tunnel','-f',str(key)],check=True,stdout=subprocess.DEVNULL)
known=base/'device-gateway/.local/known_hosts'
if not (wear/'known_hosts').exists():
    if not known.is_file():raise RuntimeError('Trusted server host key file is missing; do not accept an unverified host key')
    shutil.copyfile(known,wear/'known_hosts')
(private/'cloud-settings.json').write_text(json.dumps({'publicKey':key.with_suffix('.pub').read_text().strip()}))
public=private/'helmet-media-source.tar.gz'; confidential=private/'helmet-media-private.tar.gz'
with tarfile.open(public,'w:gz') as out:
    for directory in [media,base/'wear-api-gateway']:
        for file in directory.rglob('*'):
            relative=file.relative_to(base)
            if not file.is_file() or any(p in ('.local','node_modules','__pycache__','.git') for p in relative.parts):continue
            if file.suffix in ('.pyc','.gz'):continue
            out.add(file,arcname=str(relative).replace('\\','/'),recursive=False)
with tarfile.open(confidential,'w:gz') as out:
    names=['secrets.json','media.env','srs.conf','turn.conf','cloud-settings.json']
    files=[private/name for name in names]+list((private/'freeswitch').rglob('*.xml'))
    for file in files:
        if not file.is_file():raise RuntimeError('Missing private deployment configuration')
        out.add(file,arcname=str(file.relative_to(base)).replace('\\','/'),recursive=False)
summary={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [public,confidential]}
(private/'package-manifest.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
print('SSH private key stays local. Private media archive must be uploaded only to the authorized server.')
