import { deviceActions, isCurrentDevice, supportsDeviceAction } from './device-telemetry.js';
import { communicationGuard } from './communication-guard.js';
import { authFetch } from './auth.js';
import * as rtcSession from './rtc.js';

export function deviceCallUnavailable(device, feature, otherActive = false, assignment, options = {}) {
  const testing = options.acceptanceTest === true;
  if (testing && (options.operator?.id !== 'demo-system' || options.operator?.enabled === false)) return '仅系统管理员可发起语音联调测试';
  if (!assignment?.personId || !assignment?.assignmentId || assignment.assignmentVersion == null || assignment.deviceId !== device?.id) return '人员领用关系未就绪，请刷新';
  if (otherActive) return '请先结束当前人员通话或 SOS 通话';
  if (!device?.id || device.source !== 'DIRECT_HELMET' || device.type !== 'H' || device.active === false) return '此设备没有已启用的直连安全帽语音能力';
  if (!isCurrentDevice(device) || device.online !== true) return '设备离线或状态已过期，请等待最新上报';
  if (!feature?.supported || feature.integrationStatus !== 'CONNECTED') return feature?.reason || '人员语音接入服务尚未就绪';
  // Only the explicit administrator test can bypass PENDING acceptance. A
  // permission, connection or assignment failure must never become testable.
  const pendingTest = testing && feature.verified === false && feature.reason === '待联调';
  if (!pendingTest && (!feature.verified || !feature.available)) return feature?.reason || '人员语音能力尚未就绪';
  if (['personId','deviceId','assignmentId','assignmentVersion'].some(key => feature[key] !== assignment[key])) return '人员领用关系已变化，请刷新';
  // The guardian snapshot exposes per-device voiceAvailable, derived on the
  // server from SIP registration. Older projections omit sipRegistered itself.
  if (device.sipRegistered === false || !(device.voiceAvailable === true || device.sipRegistered === true || device.capabilities?.sipRegistered === true)) return '设备语音服务尚未就绪';
  if (pendingTest) {
    if (device.featureStates?.voice?.supported !== true || !deviceActions(device).includes('intercom') || device.communicationProtocol !== 'SIP') return '该设备未接入可联调的 SIP 语音';
  } else if (!supportsDeviceAction(device, 'intercom')) return '设备当前没有可用的语音对讲能力';
  return '';
}

// Session IDs and public status only. SIP passwords stay in a short-lived local
// variable and are never copied into the store, snapshots or browser storage.
export function createHelmetDeviceCall({ fetchImpl, rtc, guard = communicationGuard,
  schedule = setTimeout, cancel = clearTimeout, now = Date.now, makeId = () => crypto.randomUUID(),
  requestTimeout = 15000, ringTimeout = 60000, pollDelay = 2000 } = {}) {
  const listeners = new Set();
  let context = null;
  let state = { deviceId: '', recordId: '', callId: '', phase: 'idle', serverStatus: '',
    serverConnected: false, clientStatus: 'idle', muted: false, error: '', pending: false, endRequested: false };
  function update(values) { state = { ...state, ...values }; listeners.forEach(fn => fn({ ...state })); }
  function active(ctx) { return context === ctx; }
  async function api(path, body) {
    const controller = new AbortController();
    const timer = schedule(() => controller.abort(), requestTimeout);
    try {
      const response = await fetchImpl('/api/guardian/v1' + path, { signal: controller.signal,
        ...(body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) });
      const value = await response.json().catch(() => ({}));
      if (!response.ok) {
        const error = Error(value.message || '设备通话请求失败');
        error.definitive = response.status >= 400 && response.status < 500 && response.status !== 408;
        throw error;
      }
      return value;
    } finally { cancel(timer); }
  }
  function later(ctx) {
    cancel(ctx.timer);
    if (!active(ctx)) return;
    if (ctx.endRequested && now() >= ctx.endDeadline) {
      update({ phase: 'unknown', error: '服务器尚未确认结束，本机音频已退出；请到调度通信刷新或重试结束' });
      return;
    }
    ctx.timer = schedule(() => poll(ctx), pollDelay);
  }
  async function leave(ctx) {
    if (!ctx.localStarted) return;
    ctx.localStarted = false;
    await rtc.leaveChannel(ctx.reservation);
  }
  async function finish(ctx, status) {
    if (!active(ctx)) return;
    cancel(ctx.timer);
    cancel(ctx.ringTimer);
    try { await leave(ctx); } catch { /* Local RTC already detaches before cleanup. */ }
    if (!active(ctx)) return;
    guard.release(ctx.reservation); context = null;
    update({ phase: ctx.timedOut ? 'timeout' : status === 'failed' ? 'failed' : 'ended', pending: false,
      serverStatus: status, serverConnected: false, clientStatus: 'ended', muted: false, endRequested: false });
  }
  async function poll(ctx) {
    if (!active(ctx) || !ctx.recordId || ctx.polling) return;
    ctx.polling = true;
    try {
      const row = await api('/mobile/calls/' + encodeURIComponent(ctx.recordId));
      if (!active(ctx)) return;
      if (['ended', 'failed'].includes(row.status)) { await finish(ctx, row.status); return; }
      const call = await api('/helmet/calls/' + encodeURIComponent(ctx.callId));
      if (!active(ctx)) return;
      if (['ended', 'failed'].includes(call.status)) { await finish(ctx, call.status); return; }
      const connected = call.status === 'connected' && call.serverConnected === true &&
        Array.isArray(call.connectedDeviceIds) && call.connectedDeviceIds.includes(ctx.deviceId);
      if (connected) cancel(ctx.ringTimer);
      update({ serverStatus: call.status, serverConnected: connected,
        phase: ctx.endRequested ? 'ending' : connected ? 'active' : 'connecting' });
      if (ctx.endRequested && !ctx.endAccepted && now() < ctx.endDeadline) await end();
      if (!ctx.endRequested && !connected && now() >= ctx.deadline) {
        ctx.timedOut = true; update({ error: '等待安全帽接听超时，正在结束本次会话' });
        await end();
      }
    } catch (error) {
      if (active(ctx)) update({ serverConnected: false, error: '服务端通话状态暂未确认，请刷新状态或请求结束',
        phase: ctx.endRequested ? 'ending' : 'unknown' });
    } finally { ctx.polling = false; later(ctx); }
  }
  async function resolveCreation(ctx) {
    if (!active(ctx) || ctx.creating) return;
    ctx.creating = true; update({ pending: true });
    try {
      // This existing endpoint is idempotent: retries recover the same call.
      const row = await api('/mobile/calls', ctx.input);
      if (!active(ctx)) return;
      if (!row.id || !row.channelName) throw Error('未取得可核对的通话编号');
      ctx.recordId = row.id; ctx.callId = row.channelName;
      update({ recordId: row.id, callId: row.channelName, pending: false, phase: 'connecting', error: '', serverStatus: row.status });
      later(ctx);
      if (ctx.endRequested || row.status === 'unknown') {
        if (row.status === 'unknown') update({ error: '云端呼叫结果未确认，正在请求结束' });
        await end(); return;
      }
      const credentials = row.credentials;
      if (credentials?.protocol !== 'SIP') throw Error('此入口仅支持真实安全帽 SIP 语音');
      ctx.localStarted = true;
      await rtc.joinChannel({ ...credentials, callId: ctx.callId, video: false }, {
        reservation: ctx.reservation,
        onMediaState(value) {
          if (!active(ctx)) return;
          update({ clientStatus: value });
          if (!ctx.endRequested && ['failed', 'ended'].includes(value)) {
            update({ error: value === 'failed' ? '本机音频连接中断，正在请求结束' : '本机音频会话已结束，正在核对服务端状态' });
            void end();
          }
        },
      });
      if (active(ctx) && !ctx.endRequested && state.clientStatus === 'idle') update({ clientStatus: 'local_joined' });
    } catch (error) {
      if (!active(ctx)) return;
      update({ pending: false, ...(!ctx.endRequested ? { error: error.name === 'NotAllowedError' ? '麦克风权限被拒绝，正在结束本次会话' : error.message || '呼叫失败' } : {}) });
      if (ctx.recordId) { await end(); }
      else if (error.definitive) { await finish(ctx, 'failed'); }
      else update({ phase: 'unknown', error: '呼叫结果未确认，请点“刷新通话状态”查询同一请求；不会重复创建呼叫' });
    } finally { ctx.creating = false; if (active(ctx)) update({ pending: false }); }
  }
  async function start(device, feature, otherActive = false, assignment, options = {}) {
    const reason = deviceCallUnavailable(device, feature, otherActive, assignment, options);
    if (reason) throw Error(reason);
    if (context || rtc.getActiveCallId?.()) throw Error('请先结束当前通话并等待服务器确认');
    const reservation = guard.acquire();
    const acceptanceTest = options.acceptanceTest === true;
    const ctx = { reservation, deviceId: device.id, input: {
      personId: assignment.personId, deviceId: device.id, assignmentId: assignment.assignmentId, assignmentVersion: assignment.assignmentVersion,
      video: false, idempotencyKey: makeId(), ...(acceptanceTest ? { acceptanceTest: true } : {}),
    },
      deadline: now() + ringTimeout, endRequested: false, localStarted: false };
    context = ctx;
    update({ deviceId: device.id, personId: assignment.personId, assignmentId: assignment.assignmentId, assignmentVersion: assignment.assignmentVersion, acceptanceTest, recordId: '', callId: '', phase: 'requesting', serverStatus: '', serverConnected: false,
      clientStatus: 'idle', muted: false, error: '', pending: true, endRequested: false });
    ctx.ringTimer = schedule(() => {
      if (!active(ctx) || ctx.endRequested || state.serverConnected) return;
      ctx.timedOut = true;
      update({ error: '等待安全帽接听超时，正在结束本次会话' });
      return end();
    }, ringTimeout);
    await resolveCreation(ctx);
  }
  async function end(renew = false) {
    const ctx = context;
    if (!ctx) return;
    if (!ctx.endDeadline || renew) ctx.endDeadline = now() + 45000;
    ctx.endRequested = true;
    cancel(ctx.ringTimer);
    update({ endRequested: true, phase: 'ending', serverConnected: false });
    try { await leave(ctx); } catch { update({ error: '本机音频清理待确认，继续请求服务器结束' }); }
    if (!ctx.recordId) {
      if (!ctx.creating) await resolveCreation(ctx);
      return;
    }
    if (ctx.ending) return;
    ctx.ending = true;
    try {
      const row = await api('/mobile/calls/' + encodeURIComponent(ctx.recordId) + '/end', {});
      ctx.endAccepted = true;
      if (active(ctx) && ['ended', 'failed'].includes(row.status)) await finish(ctx, row.status);
    } catch { if (active(ctx)) update({ error: '结束请求尚未确认，本机已退出音频，请重试结束并核对设备' }); }
    finally { ctx.ending = false; later(ctx); }
  }
  async function refresh() {
    const ctx = context; if (!ctx) return;
    if (!ctx.recordId) return resolveCreation(ctx);
    if (ctx.endRequested) await end(true);
    return poll(ctx);
  }
  async function setMuted(value) {
    const ctx = context;
    if (!ctx || ctx.endRequested || !ctx.localStarted) throw Error('本端尚未加入通话');
    await rtc.setMuted(value, ctx.reservation); if (active(ctx)) update({ muted: value });
  }
  return {
    start, end: () => end(true), refresh, setMuted,
    resumeAudio: () => context ? rtc.resumeAudio(context.reservation) : Promise.resolve(),
    dispose(deviceId) { if (context?.deviceId === deviceId) return end(); return Promise.resolve(); },
    getState: () => ({ ...state }),
    subscribe(fn) { listeners.add(fn); fn({ ...state }); return () => listeners.delete(fn); },
  };
}

export const helmetDeviceCall = createHelmetDeviceCall({ fetchImpl: authFetch, rtc: rtcSession });
