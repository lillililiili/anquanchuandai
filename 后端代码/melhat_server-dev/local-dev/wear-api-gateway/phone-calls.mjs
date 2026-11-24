import { createHash, createHmac, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

const validId = value => typeof value === 'string' && /^[A-Za-z0-9._-]{1,100}$/.test(value);
const uuid = value => typeof value === 'string' && /^[a-f0-9-]{36}$/i.test(value);
const alive = member => member.state === 'ringing' || member.state === 'accepted';
const fault = (status, message) => Object.assign(new Error(message), { status });

export function phoneRelay() {
  let secret = process.env.WEAR_PHONE_TURN_SECRET;
  if (!secret) {
    try { secret = readFileSync(new URL('./phone-turn.key', import.meta.url), 'utf8').trim(); }
    catch { return null; }
  }
  if (!/^[A-Za-z0-9_+/=-]{32,128}$/.test(secret)) return null;
  const host = process.env.WEAR_PHONE_TURN_HOST || 'lingzhiaide.com';
  if (!/^[a-z0-9.-]+$/i.test(host)) return null;
  return () => {
    const username = String(Math.floor(Date.now() / 1000) + 7200) + ':' + randomUUID();
    const credential = createHmac('sha1', secret).update(username).digest('base64');
    return [{ urls: ['stun:' + host + ':3478'] }, {
      urls: ['turn:' + host + ':3478?transport=udp', 'turn:' + host + ':3478?transport=tcp'], username, credential,
    }];
  };
}

export function phoneIdentityReader(upstream) {
  return async (token, siteId) => {
    async function read(path) {
      const response = await fetch(new URL('/api/guardian/v1/mobile/' + path, upstream), {
        headers: { 'X-Wearable-Token': token }, signal: AbortSignal.timeout(5000), redirect: 'error',
      });
      if (!response.ok) throw fault([401, 403].includes(response.status) ? response.status : 503, '无法验证手机通话权限');
      const result = await response.json();
      if (Number(result.code) >= 400) throw fault(Number(result.code), '无法验证手机通话权限');
      return result.data ?? result;
    }
    const identity = await read('identity');
    if (!identity.id || !identity.sites?.some(site => site.id === siteId)) throw fault(403, '账号无权访问此厂站');
    const people = await read('people?siteId=' + encodeURIComponent(siteId));
    const visible = new Map((people.rows ?? []).map(person => [String(person.id), person.name]));
    return { id: String(identity.id), name: String(identity.name || ''), visible,
      personId: identity.personId != null && visible.has(String(identity.personId)) ? String(identity.personId) : null,
      canDial: (identity.permissionsBySite?.[siteId] ?? []).includes('communications:voice') };
  };
}

// Leases are intentionally ephemeral. A gateway restart expires every call and client registration.
export class PhoneCalls {
  constructor({ identity, relay, now = Date.now }) {
    this.identity = identity;
    this.relay = relay;
    this.now = now;
    this.clients = new Map();
    this.calls = new Map();
    this.starts = new Map();
  }

  endMember(call, member, state) {
    if (!alive(member)) return;
    member.state = state;
    for (const [key, signal] of call.signals) {
      if (signal.from === member.id || signal.to === member.id) call.signals.delete(key);
    }
    if (member.id === call.caller || [...call.members.values()].filter(alive).length < 2) {
      this.calls.delete(call.id);
    }
  }

  expire() {
    const now = this.now();
    for (const [key, entry] of this.clients) if (entry.until <= now) this.clients.delete(key);
    for (const [id, entry] of this.starts) if (entry.until <= now) this.starts.delete(id);
    for (const call of this.calls.values()) {
      if (call.until <= now) { this.calls.delete(call.id); continue; }
      for (const m of call.members.values()) {
        if (!this.clients.has(m.key)) this.endMember(call, m, 'offline');
        else if (m.state === 'ringing' && call.ringUntil <= now) this.endMember(call, m, 'missed');
      }
    }
  }

  membership(key) {
    for (const call of this.calls.values()) {
      const member = call.members.get(key);
      if (member && alive(member)) return { call, member };
    }
    return {};
  }

  reachable(client) {
    const people = new Map();
    const occupied = new Set();
    for (const call of this.calls.values()) {
      for (const m of call.members.values()) if (alive(m)) occupied.add(m.account);
    }
    for (const item of this.clients.values()) {
      if (item.siteId !== client.siteId || item.account === client.account || item.busy ||
          occupied.has(item.account) || !item.personId || !client.visible.has(item.personId)) continue;
      const prior = people.get(item.personId);
      // A person with ambiguous account bindings must not silently route to a different account.
      if (prior === null || (prior && prior.account !== item.account)) people.set(item.personId, null);
      else if (!prior || prior.until <= item.until) people.set(item.personId, item);
    }
    return new Map([...people].filter(([, item]) => item));
  }

  view(client, ready) {
    const { call, member } = this.membership(client.key);
    const contacts = ready && client.canDial ? [...this.reachable(client).keys()] : [];
    if (!call) return { ready, contacts, call: null };
    const members = [...call.members.values()].map(m => ({ id: m.id, name: m.name, personId: m.personId, state: m.state }));
    const iceByPeer = {};
    if (member.state === 'accepted') {
      for (const other of call.members.values()) {
        if (other.id === member.id || other.state !== 'accepted') continue;
        if (!member.ice.has(other.id)) member.ice.set(other.id, this.relay());
        iceByPeer[other.id] = member.ice.get(other.id);
      }
    }
    const signals = member.state === 'accepted' ? [...call.signals.values()].filter(s => s.to === member.id) : [];
    return { ready, contacts, call: { id: call.id, caller: call.caller, self: member.id, members, signals, iceByPeer } };
  }

  async handle(action, token, body) {
    if (!body || !uuid(body.clientId) || !validId(body.siteId)) throw fault(400, '无效的手机会话或厂站');
    const identity = await this.identity(token, body.siteId);
    this.expire();
    const now = this.now();
    const key = createHash('sha256').update(token + '/' + body.clientId).digest('hex');
    const previous = this.clients.get(key);
    const original = this.membership(key);
    if (original.call && (original.call.siteId !== body.siteId || original.member.account !== identity.id ||
        original.member.personId !== identity.personId || (original.call.caller === original.member.id && !identity.canDial))) {
      this.endMember(original.call, original.member, 'left');
    }
    if (original.call && original.member.id === original.call.caller) {
      for (const member of original.call.members.values()) {
        if (member !== original.member && !identity.visible.has(member.personId)) this.endMember(original.call, member, 'left');
      }
    }
    const client = { key, siteId: body.siteId, account: identity.id, personId: identity.personId, name: identity.name,
      visible: identity.visible, canDial: identity.canDial, busy: body.busy === true || (action !== 'presence' && previous?.busy === true),
      until: now + 25000 };
    if (action === 'offline') {
      const { call, member } = this.membership(key);
      if (call && call.siteId === body.siteId) this.endMember(call, member, 'left');
      if (!previous || previous.siteId === body.siteId) this.clients.delete(key);
      return { ready: false, contacts: [], call: null };
    }
    if (!this.relay) return action === 'presence' ? this.view(client, false) : Promise.reject(fault(503, '手机语音服务尚未就绪'));
    if (!previous && this.clients.size >= 2000) throw fault(503, '手机语音服务繁忙');
    this.clients.set(key, client);
    if (action === 'presence') return this.view(client, true);
    if (action === 'start') {
      const ids = body.personIds;
      if (!identity.canDial) throw fault(403, '当前账号无手机呼叫权限');
      if (!uuid(body.requestId) || !Array.isArray(ids) || !ids.length || ids.length > 8 ||
          ids.some(id => !validId(id)) || new Set(ids).size !== ids.length) throw fault(400, '请选择 1 至 8 位手机联系人');
      const requestKey = key + '/' + body.requestId;
      const prior = this.starts.get(requestKey);
      const fingerprint = JSON.stringify([client.siteId, ...ids]);
      if (prior) {
        if (prior.fingerprint !== fingerprint || !this.calls.has(prior.id)) throw fault(409, '此呼叫请求已经结束或目标已变化');
        return this.view(client, true);
      }
      if (client.busy || [...this.calls.values()].some(c => [...c.members.values()].some(m => alive(m) && m.account === client.account))) {
        throw fault(409, '本机已有通话');
      }
      const available = this.reachable(client);
      const selected = ids.map(id => available.get(id));
      if (selected.some(item => !item)) throw fault(409, '有联系人当前无法接听，请刷新后重选');
      const members = new Map();
      for (const item of [client, ...selected]) {
        members.set(item.key, { id: randomUUID(), key: item.key, account: item.account, personId: item.personId,
          name: item.name, state: item === client ? 'accepted' : 'ringing', ice: new Map() });
      }
      const call = { id: randomUUID(), siteId: client.siteId, caller: members.get(key).id,
        members, signals: new Map(), ringUntil: now + 45000, until: now + 60 * 60 * 1000 };
      this.calls.set(call.id, call);
      this.starts.set(requestKey, { id: call.id, fingerprint, until: call.until });
      return this.view(client, true);
    }
    const { call, member } = this.membership(key);
    if (!call || call.id !== body.callId || call.siteId !== client.siteId) throw fault(404, '手机通话已结束');
    if (action === 'accept') {
      if (client.busy) throw fault(409, '本机已有其他通话');
      if (member.state === 'ringing') member.state = 'accepted';
    } else if (action === 'leave') {
      this.endMember(call, member, member.state === 'ringing' ? 'declined' : 'left');
    } else if (action === 'signal') {
      const other = [...call.members.values()].find(m => m.id === body.to);
      if (!other || other === member || other.state !== 'accepted' || member.state !== 'accepted') throw fault(409, '对方尚未接听或已离开');
      const type = member.id < other.id ? 'offer' : 'answer';
      const sdp = body.sdp;
      if (body.type !== type || typeof sdp !== 'string' || sdp.length > 60000 ||
          !/^v=0\r?\n/.test(sdp) || !/^m=audio /m.test(sdp) || /^m=(?!audio )/m.test(sdp)) throw fault(400, '手机语音协商参数无效');
      if (type === 'answer' && !call.signals.has(other.id + '/' + member.id)) throw fault(409, '尚未收到对端语音邀请');
      const pair = member.id + '/' + other.id;
      if (call.signals.has(pair) && call.signals.get(pair).sdp !== sdp) throw fault(409, '本次语音连接已协商');
      call.signals.set(pair, { from: member.id, to: other.id, type, sdp });
    } else throw fault(404, '未知手机通话操作');
    return this.view(client, true);
  }
}
