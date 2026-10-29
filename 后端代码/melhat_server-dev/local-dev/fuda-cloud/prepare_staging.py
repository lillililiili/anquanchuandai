"""Create private credentials for the isolated rehearsal only; never print them."""
import argparse,base64,json,os,secrets
from pathlib import Path

def write_new(path,text):
    path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    with os.fdopen(os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w',encoding='utf-8',newline='\n') as f:f.write(text)

def main():
    p=argparse.ArgumentParser();p.add_argument('--snapshot',required=True);a=p.parse_args()
    root=Path(__file__).resolve().parent;snapshot=Path(a.snapshot).resolve()
    if snapshot.parent!=(root/'.private/snapshots').resolve() or (snapshot/'INCOMPLETE').exists():raise ValueError('Validated local snapshot required')
    manifest=json.loads((snapshot/'snapshot-manifest.json').read_text(encoding='utf-8'))
    if manifest.get('purpose')!='isolated-staging-rehearsal':raise ValueError('Wrong snapshot purpose')
    key=json.loads((snapshot/'media-key.private.json').read_text(encoding='utf-8'))['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    if len(base64.b64decode(key,validate=True))!=32:raise ValueError('Invalid existing media key')
    targets=[root/'.env.staging',root/'.private/staging/fuda-api.yml',root/'.private/staging/http-credentials.json']
    if any(x.exists() for x in targets):raise ValueError('Private staging configuration already exists; refusing replacement')
    app_id='fuda-staging-20261027';secret=base64.b64encode(secrets.token_bytes(32)).decode('ascii')
    env={'FUDA_MYSQL_ROOT_PASSWORD':secrets.token_hex(32),'FUDA_MYSQL_PASSWORD':secrets.token_hex(32),
        'FUDA_REDIS_PASSWORD':secrets.token_hex(32),'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY':key,'FUDA_BACKEND_IMAGE':'fuda-wearable-backend:2.0.0'}
    write_new(targets[0],''.join(k+'='+v+'\n' for k,v in env.items()))
    config={'fuda':{'api':{'enabled':True,'source-platform':'wearable-platform','applications':{app_id:{'enabled':True,'secret-base64':secret,'allowed-ledger-device-ids':['device-12','device-13']}}}}}
    write_new(targets[1],json.dumps(config,indent=2)+'\n')
    write_new(targets[2],json.dumps({'appId':app_id,'secretBase64':secret},indent=2)+'\n')
    print('Private staging credentials created. Existing media key preserved. No credential values printed.')

if __name__=='__main__':main()
