import fs from 'node:fs';
import path from 'node:path';
import { randomBytes, randomUUID, createHmac } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import Busboy from 'busboy';
import { Readable } from 'node:stream';
import { Store } from './store.mjs';
import { readTicket, ticket } from './auth.mjs';
import { eslCommand } from './esl.mjs';

export const CONTROL = '/helmet-media/control/v1';
export const PUBLIC = '/helmet-media';
export function fault(status, code) { return Object.assign(new Error(code), { status, code }); }
export function id(value) { if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(value)) throw fault(400, 'INVALID_ID'); return value; }
const epoch = value => typeof value === 'number' ? (value > 1e12 ? value : value * 1000) : Date.parse(value);
const xml = value => String(value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[ch]));
// FreeSWITCH's file preprocessor drops the entire line containing an XML declaration.
const missingXml = '<?xml version="1.0"?>\n<document type="freeswitch/xml"><section name="result"><result status="not found"/></section></document>';
export class MediaService {
  constructor(config, dependencies = {}) {
    this.config = config;
    this.store = dependencies.store ?? new Store(config.dataDir);
    this.command = dependencies.command ?? (command => eslCommand(config, command));
    this.fetch = dependencies.fetch ?? fetch;
    this.spawn = dependencies.spawn ?? spawn;
    this.probe = dependencies.probe ?? (async filename => {
      const {stdout}=await promisify(execFile)('ffprobe',['-v','error','-show_entries','format=duration:stream=codec_type,codec_name','-of','json',filename],{timeout:30000,maxBuffer:1024*1024});
      const parsed=JSON.parse(stdout);
      return Number(parsed.format?.duration)>0 && (parsed.streams??[]).some(s=>s.codec_type==='video');
    });
    this.activeRecordings = new Map();
  }
  token(purpose, identifier, seconds = 900) {
    return ticket(this.config.signingKey, { purpose, id: identifier, exp: Math.floor(Date.now() / 1000) + seconds });
  }
  authorize(tokenValue, purpose, identifier) {
    const c = readTicket(this.config.signingKey, tokenValue);
    return c?.purpose === purpose && c.id === identifier;
  }
  async health() {
    const parts = await Promise.allSettled([
      Promise.all([this.command('status'), this.command('sofia status')]).then(([status, profiles]) => ({
        // FreeSWITCH right-aligns profile names; inspect one table row at a time.
        ready: status.includes('UP') && profiles.split(/\r?\n/).some(line => {
          const [name, type, address, state] = line.trim().split(/\s+/);
          return name === 'helmet' && type === 'profile' && Boolean(address) && state === 'RUNNING';
        }),
      })),
      this.fetch(`${this.config.srsApi}/api/v1/versions`, { signal: AbortSignal.timeout(3000) }).then(r => { if (!r.ok) throw Error(); return r.json(); }),
      this.fetch(`${this.config.ttsOrigin}/health`, { signal: AbortSignal.timeout(3000) }).then(r => { if (!r.ok) throw Error(); return r.json(); }),
    ]);
    const components = { freeswitch: parts[0].status === 'fulfilled' && parts[0].value.ready, srs: parts[1].status === 'fulfilled' && parts[1].value?.code === 0,
      tts: parts[2].status === 'fulfilled' && parts[2].value?.ready === true };
    return { configured: true, ready: components.freeswitch && components.srs, components,
      devices: await this.registrationState().catch(() => []), mediaTransport: 'direct-cloud-udp', backendLocation: 'local-tunnel' };
  }
  async registrationState() {
    const response = JSON.parse(await this.command('show registrations as json'));
    const rows = response.rows ?? [];
    return Object.values(this.store.data.accounts).filter(a => a.kind === 'helmet').map(a => ({ sipId: a.sipId,
      deviceId: a.deviceId ?? null, registered: rows.some(row => String(row.reg_user ?? row.user) === a.sipId) }));
  }
  async putAccount(sipId, input) {
    id(sipId);
    if (!['helmet', 'operator'].includes(input.kind) || !/^[A-Za-z0-9_-]{20,128}$/.test(input.password ?? '')) throw fault(400, 'INVALID_ACCOUNT');
    const expires = input.expiresAt ? epoch(input.expiresAt) : null;
    if (input.kind === 'operator' && (!Number.isFinite(expires) || expires <= Date.now() || expires > Date.now() + 86400000 || !input.roomId))
      throw fault(400, 'OPERATOR_SCOPE_REQUIRED');
    if (input.roomId) id(input.roomId);
    if (input.deviceId) id(input.deviceId);
    const existing = this.store.data.accounts[sipId];
    if (existing && existing.kind !== input.kind) throw fault(409, 'ACCOUNT_KIND_CONFLICT');
    this.store.data.accounts[sipId] = { sipId, password: input.password, kind: input.kind, roomId: input.roomId ?? null,
      deviceId: input.deviceId ?? null, expiresAt: expires, updatedAt: new Date().toISOString() };
    this.store.save();
    const wssUrl = new URL(`${PUBLIC}/sip`, this.config.publicOrigin);
    wssUrl.protocol = 'wss:';
    return { sipId, sipHost: this.config.sipHost, wssUrl: wssUrl.href,
      expiresAt: expires ? new Date(expires).toISOString() : null, roomId: input.roomId ?? null, iceServers: this.iceServers() };
  }
  iceServers() {
    const username = `${Math.floor(Date.now() / 1000) + 3600}:wear`;
    const credential = createHmac('sha1', this.config.turnSecret).update(username).digest('base64');
    const host = new URL(this.config.publicOrigin).hostname;
    return [{ urls: `stun:${host}:3478` }, { urls: [`turn:${host}:3478?transport=udp`, `turn:${host}:3478?transport=tcp`], username, credential }];
  }
  account(sipId) {
    const a = this.store.data.accounts[sipId];
    return a && (!a.expiresAt || a.expiresAt > Date.now()) ? a : null;
  }
  directory(form) {
    if (form.get('section') === 'directory') {
      const name = form.get('user') ?? form.get('key_value'), account = this.account(name);
      const domain = form.get('domain') ?? this.config.sipHost;
      if (!account || domain !== this.config.sipHost) return missingXml;
      return `<?xml version="1.0"?>\n<document type="freeswitch/xml"><section name="directory"><domain name="${xml(domain)}"><params><param name="dial-string" value="{sip_invite_domain=\${domain_name}}\${sofia_contact(\${dialed_user}@\${dialed_domain})}"/></params><groups><group name="default"><users><user id="${xml(name)}"><params><param name="password" value="${xml(account.password)}"/></params><variables><variable name="user_context" value="helmet"/><variable name="domain_name" value="${xml(domain)}"/></variables></user></users></group></groups></domain></section></document>`;
    }
    if (form.get('section') === 'dialplan') {
      const account = this.account(form.get('variable_sip_auth_username'));
      const target = form.get('Caller-Destination-Number') ?? form.get('destination_number');
      const call = Object.values(this.store.data.calls).find(c => c.roomId === target && !['ended', 'failed'].includes(c.status));
      // Every INVITE is scoped, including an already registered account after expiry.
      if (!account || !call || ['ending','ended','failed'].includes(call.status) || account.roomId !== target) return missingXml;
      const inboundUuid=form.get('Caller-Unique-ID')??form.get('Unique-ID');
      if(account.kind==='operator'&&/^[a-f0-9-]{36}$/i.test(inboundUuid??'')){call.operatorUuid=inboundUuid;this.store.save();}
      return `<?xml version="1.0"?>\n<document type="freeswitch/xml"><section name="dialplan"><context name="helmet"><extension name="authorized-room"><condition><action application="set" data="helmet_call_id=${xml(call.callId)}"/><action application="answer"/><action application="conference" data="${xml(target)}@${call.video ? 'helmet-video' : 'helmet'}"/></condition></extension></context></section></document>`;
    }
    return missingXml;
  }
  createStream(input) {
    const deviceId = id(input.deviceId), sessionId = id(input.sessionId);
    let stream = Object.values(this.store.data.streams).find(s => s.sessionId === sessionId && s.deviceId === deviceId && s.status !== 'stopped');
    if (!stream) {
      stream = { streamId: randomBytes(16).toString('hex'), sessionId, deviceId, status: 'requested', createdAt: new Date().toISOString() };
      this.store.data.streams[stream.streamId] = stream; this.store.save();
    }
    return this.streamUrls(stream);
  }
  streamUrls(stream) {
    const playToken = this.token('play', stream.streamId, 30), publishToken = this.token('publish', stream.streamId, 14400);
    return { ...stream, pushUrl: `rtmp://${this.config.publicIp}:1935/helmet/${stream.streamId}?token=${publishToken}`,
      whepUrl: `${this.config.publicOrigin}${PUBLIC}/whep/${stream.streamId}?token=${playToken}`,
      hlsUrl: `${this.config.publicOrigin}${PUBLIC}/hls/${stream.streamId}/index.m3u8?token=${playToken}`,
      expiresAt: new Date(Date.now() + 30000).toISOString(), iceServers: this.iceServers() };
  }
  async streamState(streamId) {
    const stream = this.store.data.streams[id(streamId)]; if (!stream) throw fault(404, 'STREAM_NOT_FOUND');
    let publishing = false, verified = false;
    try {
      const r = await this.fetch(`${this.config.srsApi}/api/v1/streams`, { signal: AbortSignal.timeout(3000) });
      const body = await r.json(); if (!r.ok || body.code !== 0) throw Error();
      publishing = (body.streams ?? []).some(s => s.app === 'helmet' && s.name === streamId && s.publish?.active);
      verified = true;
    } catch { /* A failed management call does not prove the device is offline. */ }
    return { ...this.streamUrls(stream), publishing, statusVerified: verified };
  }
  async stopStream(streamId) {
    const stream = this.store.data.streams[id(streamId)]; if (!stream) throw fault(404, 'STREAM_NOT_FOUND');
    stream.status = 'stopped'; this.store.save();
    // Revoke publication and playback by checking state in both callbacks/proxy.
    const response = await this.fetch(`${this.config.srsApi}/api/v1/clients`, { signal: AbortSignal.timeout(4000) });
    const body = await response.json();
    if (!response.ok || body.code !== 0) throw fault(503, 'SRS_UNAVAILABLE');
    for (const client of body.clients ?? []) if (client.name === streamId || client.url?.split('?')[0].endsWith(`/helmet/${streamId}`))
      await this.fetch(`${this.config.srsApi}/api/v1/clients/${encodeURIComponent(client.id)}`, { method: 'DELETE', signal: AbortSignal.timeout(4000) });
    return { streamId, status: 'stopped' };
  }
  async startCall(input) {
    const callId = id(input.callId), roomId = id(input.roomId);
    if (!Array.isArray(input.participants) || input.participants.length < 1 || input.participants.length > 32)
      throw fault(400, 'INVALID_CALL');
    const participants = [...new Set(input.participants.map(id))];
    for (const sipId of participants) if (this.account(sipId)?.kind !== 'helmet') throw fault(409, 'HELMET_ACCOUNT_REQUIRED');
    const old = this.store.data.calls[callId]; if (old) return this.callPublic(old);
    const call = { callId, roomId, participants, video: input.video === true, status: 'dialing', createdAt: new Date().toISOString(), legs: {} };
    this.store.data.calls[callId] = call;
    for (const sipId of participants) this.store.data.accounts[sipId].roomId = roomId;
    this.store.save();
    try {
      for (const sipId of participants) {
        const uuid = randomUUID(); call.legs[uuid] = { sipId, status: 'dialing' }; this.store.save();
        const codec = call.video ? "'PCMA,H264,VP8'" : 'PCMA';
        await this.command(`bgapi originate {origination_uuid=${uuid},helmet_call_id=${callId},originate_timeout=45,absolute_codec_string=${codec},ignore_early_media=true}user/${sipId}@${this.config.sipHost} &conference(${roomId}@${call.video ? 'helmet-video' : 'helmet'})`);
      }
    } catch (error) {
      call.startFailed=true;call.status='ending';this.store.save();
      await this.endCall(callId);
      return {...this.callPublic(call),startError:'CALL_START_FAILED'};
    }
    return this.callPublic(call);
  }
  callPublic(call) { return { callId: call.callId, roomId: call.roomId, target: call.roomId ? `sip:${call.roomId}@${this.config.sipHost}` : null, video: call.video === true, connectedDeviceIds:call.status==='ended'?[]:Object.values(call.legs??{}).filter(l=>l.status==='answered').map(l=>this.store.data.accounts[l.sipId]?.deviceId).filter(Boolean), status: call.status, terminationConfirmed:call.terminationConfirmed===true, legs: call.legs }; }
  finishCall(call) {
    if(call.status==='ended')return;
    call.status='ended';call.endedAt=new Date().toISOString();call.terminationConfirmed=true;
    for(const account of Object.values(this.store.data.accounts))if(account.roomId===call.roomId){
      if(account.kind==='operator')account.expiresAt=Date.now();account.roomId=null;
    }
    this.store.event('call.ended',{callId:call.callId,connectedDeviceIds:[]});
  }
  async endCall(callId) {
    id(callId);let call=this.store.data.calls[callId];
    if(!call){call={callId,roomId:null,participants:[],legs:{},status:'ended',terminationConfirmed:true};this.store.data.calls[callId]=call;this.store.save();return this.callPublic(call);}
    if(call.status==='ended')return this.callPublic(call);
    call.status='ending';call.endRequestedAt=new Date().toISOString();this.store.save();
    for(const account of Object.values(this.store.data.accounts))if(account.kind==='operator'&&account.roomId===call.roomId)account.expiresAt=Date.now();
    const uuids=[...Object.keys(call.legs),...(call.operatorUuid?[call.operatorUuid]:[])];
    // Sending a hangup command is not proof that media stopped. Query actual channels
    // after the command; on ESL failure remain ending until events/reconciliation.
    for(const uuid of uuids)await this.command(`uuid_kill ${uuid}`).catch(()=>{});
    const states=await Promise.all(uuids.map(uuid=>this.command(`uuid_exists ${uuid}`).then(x=>x.trim()==='false').catch(()=>false)));
    const pendingOrigination=Object.values(call.legs).some(l=>!l.seen) && Date.now()-Date.parse(call.createdAt??0)<50000;
    if(states.every(Boolean)&&!pendingOrigination)this.finishCall(call);else this.store.save();
    return this.callPublic(call);
  }
  handleEsl(event) {
    const callId = event.variable_helmet_call_id, uuid = event['Unique-ID'];
    const call = this.store.data.calls[callId];
    if (!call) return;
    const leg = call.legs[uuid];
    if(event['Event-Name']==='CHANNEL_ANSWER'&&['ending','ended'].includes(call.status)){
      if(leg){leg.seen=true;leg.status='answered';}else call.operatorUuid=uuid;
      call.status='ending';this.store.save();void this.endCall(callId).catch(()=>{});return;
    }
    if(call.status==='ended')return;
    if (event['Event-Name'] === 'CHANNEL_ANSWER') {
      if (leg) {leg.status = 'answered';leg.seen=true;}
      else { call.operatorAnswered = true; call.operatorUuid = uuid; }
      if (leg) { leg.audioCodec = event.variable_read_codec ?? null; leg.videoCodec = event.variable_video_read_codec ?? null; }
      const helmetAnswered = Object.values(call.legs).some(l => l.status === 'answered');
      call.status = call.operatorAnswered && helmetAnswered ? 'connected' : 'answered';
      if(call.status==='connected')call.everConnected=true;
      const connectedDeviceIds = Object.values(call.legs).filter(l => l.status === 'answered').map(l => this.store.data.accounts[l.sipId]?.deviceId).filter(Boolean);
      this.store.event(call.status === 'connected' ? 'call.connected' : 'call.answered', { callId, sipId: leg?.sipId ?? null, connectedDeviceIds });
    } else if (event['Event-Name'] === 'CHANNEL_HANGUP_COMPLETE') {
      if (leg) leg.status = 'ended';
      else if(uuid===call.operatorUuid)call.operatorEnded=true;
      const allEnded = Object.values(call.legs).every(l => l.status === 'ended');
      const connectedDeviceIds=Object.values(call.legs).filter(l=>l.status==='answered').map(l=>this.store.data.accounts[l.sipId]?.deviceId).filter(Boolean);
      if(allEnded && (!call.operatorUuid || call.operatorEnded))this.finishCall(call);
      else if(allEnded || uuid===call.operatorUuid)void this.endCall(callId).catch(()=>{});
      this.store.event('call.participant-ended',{callId,sipId:leg?.sipId??null,connectedDeviceIds,cause:event['Hangup-Cause']??'UNKNOWN'});
    }
  }
  async callState(callId) {
    const call=this.store.data.calls[id(callId)];if(!call)throw fault(404,'CALL_NOT_FOUND');
    if(call.status==='ended'||call.status==='failed')return {...this.callPublic(call),statusVerified:call.terminationConfirmed===true};
    if(call.status==='ending')return this.endCall(callId);
    if(Date.now()-Date.parse(call.createdAt)<5000)return {...this.callPublic(call),statusVerified:false};
    let verified=true;
    const entries=[...Object.entries(call.legs),...(call.operatorUuid?[[call.operatorUuid,null]]:[])];
    for(const [uuid,leg] of entries){
      try{
        const exists=(await this.command(`uuid_exists ${uuid}`)).trim();
        if(exists==='false') {
          if(leg&&!leg.seen&&Date.now()-Date.parse(call.createdAt)<50000)verified=false;
          else if(leg)leg.status='ended';else call.operatorEnded=true;
        }
        else if(exists==='true'){
          if(leg)leg.seen=true;
          const answered=Number((await this.command(`uuid_getvar ${uuid} answered_epoch`)).trim())>0;
          if(answered){if(leg)leg.status='answered';else call.operatorAnswered=true;}
        }else verified=false;
      }catch{verified=false;}
    }
    if(verified){
      const answered=Object.values(call.legs).some(l=>l.status==='answered');
      if(answered&&call.operatorAnswered&&!call.operatorEnded)call.status='connected';
      if(Object.values(call.legs).every(l=>l.status==='ended'))await this.endCall(callId);
      this.store.save();
    }
    return {...this.callPublic(call),statusVerified:verified};
  }
  async reapExpired() {
    const expiredRooms = new Set(Object.values(this.store.data.accounts).filter(a => a.kind === 'operator' && a.expiresAt <= Date.now()).map(a => a.roomId).filter(Boolean));
    for (const call of Object.values(this.store.data.calls)) if ((expiredRooms.has(call.roomId) || call.status==='ending') && call.status !== 'ended') await this.endCall(call.callId);
  }
  handleSrs(body) {
    // SRS HLS on_play reports the playlist filename, including .m3u8.
    // Normalize this one playback representation; publication identities stay exact.
    const hls = body.action === 'on_play' && typeof body.stream === 'string'
      ? body.stream.match(/^([A-Za-z0-9_-]{1,80})\.m3u8$/) : null;
    const streamId = hls ? hls[1] : body.stream;
    const stream = this.store.data.streams[streamId];
    if (!stream || stream.status === 'stopped' || body.app !== 'helmet') return 1;
    const tokenValue = new URLSearchParams(String(body.param ?? '').replace(/^\?/, '')).get('token');
    if (body.action === 'on_publish' && !this.authorize(tokenValue, 'publish', streamId)) return 1;
    if (body.action === 'on_play' && !this.authorize(tokenValue, 'play', streamId)) return 1;
    if (body.action === 'on_publish') { stream.status = 'publishing'; stream.clientId = body.client_id; this.store.event('stream.publishing', { streamId: stream.streamId, deviceId: stream.deviceId }); }
    if (body.action === 'on_unpublish' && (!stream.clientId || stream.clientId === body.client_id)) { stream.status = 'offline'; this.store.event('stream.offline', { streamId: stream.streamId, deviceId: stream.deviceId }); }
    return 0;
  }
  assetPublic(asset) {
    const { filename, ...data } = asset;
    return { ...data, url: `${this.config.publicOrigin}${PUBLIC}/files/${asset.assetId}?token=${this.token('asset', asset.assetId)}` };
  }
  registerAsset(assetId, filename, meta) {
    const info = fs.statSync(filename);
    if(process.platform!=='win32'){const directory=fs.openSync(path.dirname(filename),'r');try{fs.fsyncSync(directory);}finally{fs.closeSync(directory);}}
    const asset = { assetId, filename: path.basename(filename), ...meta, size: info.size, status: 'ready', createdAt: new Date().toISOString() };
    this.store.data.assets[assetId] = asset; this.store.event('asset.ready', { assetId, deviceId: asset.deviceId ?? null, kind: asset.kind, requestId: asset.requestId ?? null });
    return this.assetPublic(asset);
  }
  async tts(input) {
    id(input.requestId);
    if (typeof input.text !== 'string' || !input.text.trim() || input.text.length > 1000) throw fault(400, 'INVALID_TEXT');
    const prior = Object.values(this.store.data.assets).find(a => a.requestId === input.requestId && a.kind === 'broadcast');
    if (prior) return { ...this.assetPublic(prior), audioUrl: this.assetPublic(prior).url };
    const assetId = randomUUID();
    const response = await this.fetch(`${this.config.ttsOrigin}/synthesize`, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ text: input.text, assetId }), signal: AbortSignal.timeout(90000) });
    if (!response.ok) throw fault(503, 'TTS_UNAVAILABLE');
    const generated = await response.json();
    if (generated.assetId !== assetId || generated.status !== 'ready') throw fault(502, 'INVALID_TTS_RESPONSE');
    const asset = this.registerAsset(assetId, this.store.assetPath(assetId, 'mp3'), { kind: 'broadcast', mime: 'audio/mpeg', requestId: input.requestId });
    return { ...asset, audioUrl: asset.url };
  }
  async ingestUpload(body, contentType, deviceId, kind, metadata = {}) {
    id(deviceId);
    if (!['photo', 'audio', 'video'].includes(kind)) throw fault(400, 'INVALID_UPLOAD');
    if (metadata.requestId) id(metadata.requestId);
    if (metadata.progressId && !/^[A-Za-z0-9_-]{8,80}$/.test(metadata.progressId)) throw fault(400,'INVALID_PROGRESS_ID');
    const prior = metadata.progressId && Object.values(this.store.data.assets).find(a => a.deviceId === deviceId && a.progressId === metadata.progressId);
    if (prior) return this.assetPublic(prior);
    const assetId = randomUUID(), temporary = this.store.assetPath(assetId, 'partial');
    let parser, error, fileCount = 0, originalName = '', writing;
    try { parser = Busboy({ headers: { 'content-type': contentType }, limits: { files: 1, fileSize: 255 * 1024 * 1024, fields: 16, fieldSize: 4096, parts: 18 } }); }
    catch { throw fault(400, 'INVALID_MULTIPART'); }
    const finished = new Promise((resolve,reject) => {
      parser.on('field',(name,value)=>{ if(name==='device_id' && value!==deviceId) error=fault(403,'DEVICE_MISMATCH'); });
      parser.on('file',(name,file,info)=>{
        fileCount++; if(name!=='file') error=fault(400,'INVALID_FILE_FIELD');
        originalName=path.basename(info.filename ?? '').slice(0,160);
        file.on('limit',()=>{error=fault(413,'FILE_TOO_LARGE');});
        writing=(async()=>{const output=await fs.promises.open(temporary,'wx',0o600);try{for await(const chunk of file)await output.write(chunk);await output.sync();}finally{await output.close();}})();
        writing.catch(e=>{error=e;file.resume();});
      });
      for(const name of ['filesLimit','fieldsLimit','partsLimit'])parser.on(name,()=>{error=fault(400,'MULTIPART_LIMIT');});
      parser.on('error',reject);parser.on('close',resolve);
    });
    const source = Buffer.isBuffer(body) ? Readable.from(body) : fs.createReadStream(body.filename);
    source.on('error',e=>parser.destroy(e));source.pipe(parser);
    try {
      await finished; if(writing)await writing; if(error)throw error; if(fileCount!==1)throw fault(400,'FILE_REQUIRED');
      const handle=await fs.promises.open(temporary,'r'),head=Buffer.alloc(16);await handle.read(head,0,16,0);await handle.close();
      let extension,mime;
      if(kind==='photo'&&head[0]===255&&head[1]===216&&head[2]===255){extension='jpg';mime='image/jpeg';}
      else if(kind==='photo'&&head.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'))){extension='png';mime='image/png';}
      else if(kind==='audio'&&(head.subarray(0,3).toString()==='ID3'||head[0]===255&&(head[1]&224)===224)){extension='mp3';mime='audio/mpeg';}
      else if(kind==='video'&&head.subarray(4,8).toString()==='ftyp'){extension='mp4';mime='video/mp4';}
      else throw fault(415,'UNSUPPORTED_FILE_CONTENT');
      if(kind==='video' && !await this.probe(temporary))throw fault(415,'INVALID_VIDEO');
      const filename=this.store.assetPath(assetId,extension);await fs.promises.rename(temporary,filename);
      return this.registerAsset(assetId,filename,{deviceId,kind,mime,originalName,...metadata});
    } finally {source.destroy();await fs.promises.unlink(temporary).catch(()=>{});}
  }
  bindPhoto(input) {
    const deviceId=id(input.deviceId);let url;
    try{url=new URL(input.imageUrl);}catch{throw fault(400,'INVALID_ASSET_URL');}
    if(url.origin!==this.config.publicOrigin)throw fault(403,'ASSET_OWNER_MISMATCH');
    const assetId=url.pathname.match(/^\/helmet-media\/files\/([A-Za-z0-9_-]+)$/)?.[1];
    const asset=this.store.data.assets[assetId];
    if(!asset || asset.deviceId!==deviceId || asset.kind!=='photo')throw fault(403,'ASSET_OWNER_MISMATCH');
    const latitude=Number(input.latitude),longitude=Number(input.longitude);
    if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||Math.abs(latitude)>90||Math.abs(longitude)>180)throw fault(400,'INVALID_LOCATION');
    asset.deviceBindingConfirmed=true;asset.latitude=latitude;asset.longitude=longitude;asset.coordinateSystem='GCJ-02';
    this.store.event('asset.bound',{assetId,deviceId,requestId:asset.requestId??null});
    return {assetId,status:'ready'};
  }
  async startRecording(input) {
    const stream = this.store.data.streams[id(input.streamId)]; if (!stream || stream.status === 'stopped') throw fault(404, 'STREAM_NOT_FOUND');
    id(input.requestId);
    const prior = Object.values(this.store.data.recordings).find(r => r.requestId === input.requestId); if (prior) return prior;
    const state = await this.streamState(stream.streamId); if (!state.statusVerified || !state.publishing) throw fault(409, 'STREAM_NOT_PUBLISHING');
    const recordingId = randomUUID(), filename = this.store.assetPath(recordingId, 'mp4');
    const record = { recordingId, streamId: stream.streamId, deviceId: stream.deviceId, requestId: input.requestId, status: 'starting', createdAt: new Date().toISOString() };
    this.store.data.recordings[recordingId] = record; this.store.save();
    const source = `rtmp://127.0.0.1:1935/helmet/${stream.streamId}?token=${this.token('play', stream.streamId, 14400)}`;
    const process = this.spawn('ffmpeg', ['-nostdin', '-hide_banner', '-loglevel', 'error', '-rw_timeout', '15000000', '-i', source, '-t', '14400', '-c', 'copy', '-movflags', '+frag_keyframe+empty_moov', filename], { stdio: ['ignore', 'ignore', 'pipe'] });
    this.activeRecordings.set(recordingId, process);
    process.stderr.on('data', () => {}); // URLs contain credentials; never log stderr.
    process.on('spawn', () => { record.status = 'recording'; this.store.save(); });
    process.on('error', () => { record.status = 'failed'; this.store.event('recording.failed', { recordingId, requestId:record.requestId, deviceId:record.deviceId }); });
    process.on('close', async code => {
      this.activeRecordings.delete(recordingId);
      if ((code === 0 || code === 255) && fs.existsSync(filename) && fs.statSync(filename).size > 1024 && await this.probe(filename).catch(()=>false)) {
        record.status = 'ready'; record.assetId = recordingId;
        this.registerAsset(recordingId, filename, { deviceId: stream.deviceId, kind: 'video', mime: 'video/mp4', requestId: input.requestId });
        this.store.event('recording.ready', { recordingId, requestId:record.requestId, deviceId:record.deviceId, assetId:recordingId });
      } else { record.status = 'failed'; this.store.event('recording.failed', { recordingId, requestId:record.requestId, deviceId:record.deviceId }); }
    });
    return record;
  }
  stopRecording(recordingId) {
    const record = this.store.data.recordings[id(recordingId)]; if (!record) throw fault(404, 'RECORDING_NOT_FOUND');
    const process = this.activeRecordings.get(recordingId);
    if (process) { record.status = 'finalizing'; this.store.save(); process.kill('SIGINT'); }
    return record;
  }
  recordingState(recordingId) {
    const record=this.store.data.recordings[id(recordingId)];if(!record)throw fault(404,'RECORDING_NOT_FOUND');
    return {...record};
  }
  close() { for (const process of this.activeRecordings.values()) process.kill('SIGINT'); }
}
