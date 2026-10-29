"""Signed local readiness; no credentials or SIP account details printed."""
import hashlib
import hmac
import json
import secrets
import time
import urllib.request
from pathlib import Path

key=json.loads((Path(__file__).resolve().parents[1]/'.local/secrets.json').read_text())['signingKey']
endpoint='/helmet-media/control/v1/health'
for attempt in range(30):
    timestamp=str(int(time.time()));nonce=secrets.token_urlsafe(18)
    canonical='\n'.join([timestamp,nonce,'GET',endpoint,hashlib.sha256(b'').hexdigest()])
    signature=hmac.new(key.encode(),canonical.encode(),hashlib.sha256).hexdigest()
    try:
        request=urllib.request.Request('http://10.255.1.1:18190'+endpoint,headers={'X-Media-Time':timestamp,'X-Media-Nonce':nonce,'X-Media-Signature':signature})
        data=json.load(urllib.request.urlopen(request,timeout=8))['data']
        if data.get('ready') and data.get('components',{}).get('tts'):
            print(json.dumps({'configured':data['configured'],'ready':data['ready'],'components':data['components'],'realDeviceRegistration':'not checked by this readiness probe'}))
            raise SystemExit(0)
    except (OSError,ValueError,KeyError): pass
    time.sleep(2)
raise SystemExit('Media components are not ready; inspect owned container logs privately')
