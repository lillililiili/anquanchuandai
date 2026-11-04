// Opt-in isolated acceptance fixture. Real media HTTP/auth/store code, simulated
// FreeSWITCH/SRS. Never deploy this adapter or its readiness evidence to production.
import fs from 'node:fs';
import https from 'node:https';
import {createServer} from '/opt/wearable/helmet-media/server.mjs';
if(process.env.WEARABLE_ISOLATED_LAB!=='wearable-lab-acceptance')throw Error('Laboratory marker required');
const config=JSON.parse(fs.readFileSync('/private/media.json','utf8'));
if(config.publicIp!=='127.0.0.1'||config.dataDir!=='/data'||config.srsApi!=='http://simulated-srs'||config.ttsOrigin!=='http://simulated-tts')throw Error('Non-laboratory dependency refused');
let service;
const created=createServer(config,{
  command:async command=>{
    if(command==='show registrations as json')return JSON.stringify({rows:Object.values(service.store.data.accounts).map(a=>({reg_user:a.sipId}))});
    if(command==='status')return 'UP laboratory simulator';
    if(command==='sofia status')return 'helmet profile sip:simulated@127.0.0.1:5060 RUNNING (0)';
    if(command.startsWith('uuid_exists'))return 'false';
    return '+OK laboratory simulator';
  },
  fetch:async url=>{
    if(!/^http:\/\/simulated-(srs|tts)(\/|$)/.test(String(url)))throw Error('External request refused');
    return new Response(JSON.stringify(String(url).endsWith('/health')?{ready:true}:{code:0,streams:[],clients:[]}));
  },
  spawn:()=>{throw Error('This fixture does not implement actual video recording');},
  probe:async()=>false
});
service=created.service;
const tls=https.createServer({cert:fs.readFileSync('/private/media.crt'),key:fs.readFileSync('/private/media.key')},created.server.listeners('request')[0]);
created.server.listen(18190,'0.0.0.0');tls.listen(18191,'0.0.0.0');
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{service.close();created.server.close();tls.close();});
console.log('Isolated real media API with simulated media engines; actual playback/recording is not provided.');
