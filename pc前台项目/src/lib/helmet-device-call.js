import { deviceActions, isCurrentDevice, supportsDeviceAction } from './device-telemetry.js';
import { communicationGuard } from './communication-guard.js';
import { authFetch, captureAuthRequest, onAuthCleared } from './auth.js';
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

export function deviceCallStatus(state) {
  if (state.recovering) return '正在核对当前账号已有通话';
  if (state.recovered && !state.endRequested && !['ended','failed','timeout'].includes(state.phase)) {
    const detail = state.serverConnected ? '服务端已接通' : state.deviceAnswered ? '设备已应答' : '状态待核实';
    return `已有会话（${detail}），本页未加入`;
  }
  const terminal = { idle: '尚未发起通话', ending: '正在结束，等待服务端确认', unknown: '通话结果待确认', ended: '通话已结束', failed: '呼叫失败', timeout: '通话建立超时' };
  if (terminal[state.phase]) return terminal[state.phase];
  if (state.serverConnected && state.localJoined) return '双方已接通（服务端及本端确认）';
  const stages = { microphone_permission: '等待电脑麦克风授权，尚未呼叫设备', microphone_ready: '电脑麦克风已就绪，正在请求设备呼叫', connecting_service: '正在连接电脑语音服务', registering: '正在注册电脑语音身份', preparing_offer: '正在准备电脑音频与入会请求', invite_sent: '电脑已发出入会请求，等待入会确认' };
  if (state.localJoined) return state.deviceAnswered ? '电脑已入会、设备已应答，等待双方接通确认' : '电脑已入会，等待设备接听';
  const stage = stages[state.clientStatus] || '正在请求呼叫';
  return state.deviceAnswered ? '设备已应答；' + stage : stage;
}

function connectionTimeoutMessage(state) {
  if (!state.localJoined) {
    const stages = { connecting_service: '连接语音服务', registering: 'SIP 注册', preparing_offer: '音频准备或入会请求发送', invite_sent: '等待电脑入会确认' };
    return `${state.deviceAnswered ? '安全帽已应答，' : '设备接听状态未确认，'}电脑${stages[state.clientStatus] || '入会'}超时，正在结束本次会话`;
  }
  return state.deviceAnswered ? '电脑已入会、安全帽已应答，但双方接通确认超时，正在结束本次会话' : '电脑已入会，等待安全帽接听超时，正在结束本次会话';
}

// Session IDs and public status only. SIP passwords stay in a short-lived local
// variable and are never copied into the store, snapshots or browser storage.
export function createHelmetDeviceCall({ fetchImpl, rtc, guard = communicationGuard,
  schedule = setTimeout, cancel = clearTimeout, now = Date.now, makeId = () => crypto.randomUUID(),
  requestTimeout = 15000, ringTimeout = 60000, pollDelay = 2000, getOperatorId = () => '', getCloseRequest = () => undefined } = {}) {
  const listeners = new Set();
  let context = null;
  let accountId = '', recoveryPromise = null, recoveryGeneration = 0;
  let state = { deviceId: '', recordId: '', callId: '', phase: 'idle', serverStatus: '',
    serverConnected: false, deviceAnswered: false, localJoined: false, clientStatus: 'idle', muted: false, error: '', pending: false, endRequested: false,
    recovered: false, recovering: false, recoveryError: '' };
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
        error.errorCode = value.errorCode || value.code;
        error.httpStatus = response.status;
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
    ctx.timer = schedule(() => poll(ctx), ctx.recovered ? Math.max(5000, pollDelay) : pollDelay);
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
  const terminal = status => ['ended','failed'].includes(status);
  // These backend checks run before device submission. A prior uncertain POST
  // is deliberately excluded: its outcome still needs the same-key recovery.
  const notSentCodes = new Set(['PERMISSION_DENIED','DEVICE_UNAVAILABLE','DEVICE_OFFLINE','SIP_NOT_REGISTERED',
    'REQUEST_ID_REQUIRED','VOICE_ONLY','DEVICE_NOT_FOUND','INVALID_REQUEST','INVALID_CALL','MEDIA_SERVICE_UNAVAILABLE',
    'ASSIGNMENT_CHANGED','ASSIGNMENT_REQUIRED','FEATURE_PENDING_ACCEPTANCE','FEATURE_UNSUPPORTED','FEATURE_NOT_CONNECTED']);
  function recoveredRow(ctx, row) {
    ctx.recordId = row.id || ctx.recordId;
    ctx.callId = row.channelName || ctx.callId || '';
    ctx.deviceId = row.deviceId || ctx.deviceId;
    ctx.recovered = true; ctx.deadline = Infinity;
    cancel(ctx.ringTimer);
    update({ recovered: true, recordId: ctx.recordId, callId: ctx.callId, deviceId: ctx.deviceId,
      personId: row.personId || state.personId || '', assignmentId: row.assignmentId || '', assignmentVersion: row.assignmentVersion,
      acceptanceTest: row.acceptanceTest === true,
      serverStatus: row.status || 'unknown', serverConnected: row.status === 'connected' && row.serverConnected === true && row.connectedDeviceIds?.includes(ctx.deviceId) === true,
      deviceAnswered: ['answered','connected'].includes(row.status) && row.connectedDeviceIds?.includes(ctx.deviceId) === true,
      localJoined: false, clientStatus: 'not_joined', pending: false, phase: ctx.endRequested ? 'ending' : 'unknown',
      error: row.failReason || (ctx.callId ? '' : '原请求结果待核实，尚未取得设备会话编号；本页不会重新拨号') });
  }
  async function recover({ operatorId = accountId || getOperatorId(), deviceId = '' } = {}) {
    if (!operatorId) { update({ recoveryError: '当前账号未就绪，无法核对已有通话' }); return false; }
    if (context?.operatorId === operatorId) return true;
    if (recoveryPromise && accountId === operatorId) return recoveryPromise;
    const operation = ++recoveryGeneration;
    accountId = operatorId;
    const prior = context;
    const task = (async () => {
      if (prior) await detach({ reason: '账号已变化，本页音频已退出', invalidateRecovery: false });
      if (operation !== recoveryGeneration || accountId !== operatorId) return false;
      update({ recovering: true, recoveryError: '' });
      try {
        const rows = await api('/mobile/calls?owned=true&status=active');
        if (operation !== recoveryGeneration || accountId !== operatorId) return false;
        if (!Array.isArray(rows)) throw Error('已有通话列表格式异常');
        const candidates = rows.filter(row => row?.id && row.requesterUserId === operatorId && row.operationType === 'call' && !terminal(row.status));
        candidates.sort((a,b) => Number(b.deviceId === deviceId) - Number(a.deviceId === deviceId) || Number(!!b.channelName) - Number(!!a.channelName) || String(b.startedAt || '').localeCompare(String(a.startedAt || '')));
        if (candidates[0] && !context) {
          const row = candidates[0], ctx = { operatorId, reservation: guard.acquire(), recordId: row.id, callId: row.channelName || '', deviceId: row.deviceId,
            recovered: true, localStarted: false, localJoined: false, creationRequested: true, endRequested: false, deadline: Infinity };
          context = ctx; recoveredRow(ctx, row); later(ctx);
        }
        return true;
      } catch (error) {
        if (operation === recoveryGeneration) update({ recoveryError: '未能核对已有通话，请刷新状态后再发起；不会重复拨号', error: error.message });
        return false;
      } finally {
        if (operation === recoveryGeneration) { recoveryPromise = null; update({ recovering: false }); }
      }
    })();
    recoveryPromise = task;
    return task;
  }
  async function closeOriginal(ctx, fallbackRequest) {
    if (!ctx.locallyCreated || !ctx.recordId || ctx.originalClosing) return ctx.originalClosing;
    const request = ctx.closeRequest || fallbackRequest;
    if (!request) return;
    ctx.originalClosing = (async () => {
      const controller = new AbortController(), timer = schedule(() => controller.abort(), requestTimeout);
      try { await request('/api/guardian/v1/mobile/calls/' + encodeURIComponent(ctx.recordId) + '/end', { method:'POST', headers:{'Content-Type':'application/json'}, body:'{}', signal:controller.signal }); }
      catch { /* Keep the server ledger recoverable; local cleanup is independent. */ }
      finally { cancel(timer); }
    })();
    return ctx.originalClosing;
  }
  async function detach({ reason = '本页音频已退出', request, invalidateRecovery = true } = {}) {
    if (invalidateRecovery) { recoveryGeneration++; recoveryPromise = null; accountId = ''; }
    const ctx = context;
    context = null;
    if (ctx) { ctx.detached = true; cancel(ctx.timer); cancel(ctx.ringTimer); }
    update({ phase: 'idle', deviceId:'', personId:'', assignmentId:'', assignmentVersion:undefined, acceptanceTest:false, muted:false, recordId: '', callId: '', serverStatus: '', serverConnected: false, deviceAnswered: false,
      localJoined: false, clientStatus: 'ended', pending: false, endRequested: false, recovered: false, recovering: false, recoveryError: '', error: '' });
    if (!ctx) return;
    // A recovered row may belong to another tab. Detaching this page never
    // hangs that tab up; only its explicit End button may do so.
    const closeRequest = closeOriginal(ctx, request);
    try { await leave(ctx); } catch { /* Local cancellation has already detached its generation. */ }
    finally { guard.release(ctx.reservation); }
    await closeRequest;
  }
  async function reportLocalJoined(ctx) {
    if (!active(ctx) || ctx.endRequested || ctx.joinReported || ctx.reportingJoin || !ctx.localJoined) return;
    ctx.reportingJoin = true;
    try {
      await api('/mobile/calls/' + encodeURIComponent(ctx.recordId) + '/joined', {});
      ctx.joinReported = true;
    } catch (error) {
      if (active(ctx) && !ctx.endRequested) {
        update({ error: '电脑已入会，但平台尚未确认本端入会记录' });
        if (error.definitive) await end();
      }
    } finally { ctx.reportingJoin = false; }
  }
  async function poll(ctx) {
    if (!active(ctx) || !ctx.recordId || ctx.polling) return;
    ctx.polling = true;
    try {
      const row = await api('/mobile/calls/' + encodeURIComponent(ctx.recordId));
      if (!active(ctx)) return;
      if (terminal(row.status)) { await finish(ctx, row.status); return; }
      if (row.channelName) ctx.callId = row.channelName;
      const call = ctx.recovered || !ctx.callId ? row : await api('/helmet/calls/' + encodeURIComponent(ctx.callId));
      if (!active(ctx)) return;
      if (['ended', 'failed'].includes(call.status)) { await finish(ctx, call.status); return; }
      const connected = call.status === 'connected' && call.serverConnected === true &&
        Array.isArray(call.connectedDeviceIds) && call.connectedDeviceIds.includes(ctx.deviceId);
      const deviceAnswered = ['answered','connected'].includes(call.status) && Array.isArray(call.connectedDeviceIds) && call.connectedDeviceIds.includes(ctx.deviceId);
      if (connected && ctx.localJoined) cancel(ctx.ringTimer);
      update({ serverStatus: call.status, serverConnected: connected, deviceAnswered, callId: ctx.callId,
        phase: ctx.endRequested ? 'ending' : ctx.recovered ? 'unknown' : connected && ctx.localJoined ? 'active' : 'connecting' });
      if (ctx.localJoined && !ctx.endRequested) await reportLocalJoined(ctx);
      if (ctx.endRequested && !ctx.endAccepted && now() < ctx.endDeadline) await end();
      if (!ctx.recovered && !ctx.endRequested && !(connected && ctx.localJoined) && now() >= ctx.deadline) {
        ctx.timedOut = true; update({ error: connectionTimeoutMessage(state) });
        await end();
      }
    } catch (error) {
      if (active(ctx)) update({ serverConnected: false, error: '服务端通话状态暂未确认，请刷新状态或请求结束',
        phase: ctx.endRequested ? 'ending' : 'unknown' });
    } finally { ctx.polling = false; later(ctx); }
  }
  async function resolveCreation(ctx) {
    if (!active(ctx) || ctx.creating) return;
    ctx.creating = true; ctx.creationRequested = true; update({ pending: true });
    try {
      // This existing endpoint is idempotent: retries recover the same call.
      const row = await api('/mobile/calls', ctx.input);
      if (!active(ctx)) {
        if (ctx.detached && row.id && !terminal(row.status)) { ctx.recordId = row.id; await closeOriginal(ctx); }
        return;
      }
      if (!row.id) throw Error('未取得可核对的通话编号');
      ctx.recordId = row.id; ctx.callId = row.channelName || '';
      if (terminal(row.status)) { update({ recordId: row.id, error: row.failReason || '' }); await finish(ctx, row.status); return; }
      if (ctx.recoveryOnly || row.recoveryOnly === true || !ctx.callId || ['requesting','unknown','ending'].includes(row.status)) {
        await leave(ctx); if (!active(ctx)) return;
        recoveredRow(ctx, row); later(ctx);
        if (ctx.endRequested) await end();
        return;
      }
      update({ recordId: row.id, callId: row.channelName, pending: false, phase: 'connecting', error: '', serverStatus: row.status });
      later(ctx);
      if (ctx.endRequested) {
        await end(); return;
      }
      const credentials = row.credentials;
      if (credentials?.protocol !== 'SIP') throw Error('此入口仅支持真实安全帽 SIP 语音');
      ctx.localStarted = true;
      await rtc.joinChannel({ ...credentials, callId: ctx.callId, video: false }, {
        reservation: ctx.reservation,
        onMediaState(value) {
          if (!active(ctx)) return;
          if (['local_joined','remote_audio','remote_video','playback_blocked'].includes(value)) ctx.localJoined = true;
          update({ clientStatus: value, localJoined: !!ctx.localJoined });
          if (ctx.localJoined && !ctx.endRequested) void reportLocalJoined(ctx);
          if (!ctx.endRequested && ['failed', 'ended'].includes(value)) {
            update({ error: value === 'failed' ? '本机音频连接中断，正在请求结束' : '本机音频会话已结束，正在核对服务端状态' });
            void end();
          }
        },
      });
    } catch (error) {
      if (!active(ctx)) return;
      update({ pending: false, ...(!ctx.endRequested ? { error: error.name === 'NotAllowedError' ? '麦克风权限被拒绝，正在结束本次会话' : error.message || '呼叫失败' } : {}) });
      if (ctx.recordId) { await end(); }
      else if (error.errorCode === 'CALL_BUSY' && !ctx.creationUncertain) {
        const operatorId = ctx.operatorId, deviceId = ctx.deviceId;
        await finish(ctx, 'failed');
        await recover({ operatorId, deviceId });
        if (!context) update({ error: '该设备已有通话或未结束请求，请刷新已有会话后再试' });
      } else if (!ctx.creationUncertain && notSentCodes.has(error.errorCode)) {
        await finish(ctx, 'failed');
      } else {
        ctx.creationUncertain = true; ctx.recoveryOnly = true; ctx.deadline = Infinity;
        cancel(ctx.ringTimer); await leave(ctx);
        if (active(ctx)) update({ phase: 'unknown', clientStatus:'not_joined', error: '呼叫结果未确认，请点“刷新通话状态”查询同一请求；不会重复创建呼叫' });
      }
    } finally { ctx.creating = false; if (active(ctx)) update({ pending: false }); }
  }
  async function start(device, feature, otherActive = false, assignment, options = {}) {
    const reason = deviceCallUnavailable(device, feature, otherActive, assignment, options);
    if (reason) throw Error(reason);
    const operatorId = options.operator?.id || getOperatorId() || accountId;
    if (!await recover({ operatorId, deviceId: device.id })) throw Error(state.recoveryError || '已有通话尚未核对');
    if (accountId !== operatorId) throw Error('登录状态已变化，未呼叫设备');
    if (context || rtc.getActiveCallId?.()) throw Error('请先结束已有通话并等待服务器确认；本页不会重复拨号');
    const reservation = guard.acquire();
    const acceptanceTest = options.acceptanceTest === true;
    const ctx = { operatorId, locallyCreated: true, closeRequest: getCloseRequest(), reservation, deviceId: device.id, input: {
      personId: assignment.personId, deviceId: device.id, assignmentId: assignment.assignmentId, assignmentVersion: assignment.assignmentVersion,
      video: false, idempotencyKey: makeId(), ...(acceptanceTest ? { acceptanceTest: true } : {}),
    },
      endRequested: false, localStarted: false, preparingMicrophone: true, localJoined: false };
    context = ctx;
    update({ deviceId: device.id, personId: assignment.personId, assignmentId: assignment.assignmentId, assignmentVersion: assignment.assignmentVersion, acceptanceTest, recordId: '', callId: '', phase: 'requesting', serverStatus: '', serverConnected: false,
      clientStatus: 'microphone_permission', localJoined: false, deviceAnswered: false, muted: false, error: '', pending: true, endRequested: false,
      recovered: false, recoveryError: '' });
    try {
      if (typeof rtc.prepareMicrophone !== 'function') throw Error('浏览器麦克风准备服务不可用，未呼叫设备');
      ctx.localStarted = true;
      await rtc.prepareMicrophone({ reservation, onMediaState: value => { if (active(ctx) && !ctx.endRequested) update({ clientStatus: value }); } });
    } catch (error) {
      if (active(ctx) && !ctx.endRequested) { update({ error: error.message || '电脑麦克风准备失败，未呼叫设备' }); await finish(ctx, 'failed'); }
      return;
    } finally { ctx.preparingMicrophone = false; }
    if (!active(ctx) || ctx.endRequested) return;
    ctx.deadline = now() + ringTimeout;
    ctx.ringTimer = schedule(() => {
      if (!active(ctx) || ctx.endRequested || state.serverConnected && ctx.localJoined) return;
      ctx.timedOut = true;
      update({ error: connectionTimeoutMessage(state) });
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
    if (!active(ctx)) return;
    if (!ctx.creationRequested && !ctx.recordId) { await finish(ctx, 'ended'); return; }
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
    const ctx = context; if (!ctx) return recover();
    if (ctx.preparingMicrophone) return;
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
    start, end: () => end(true), refresh, recover, detach, setMuted,
    resumeAudio: () => context ? rtc.resumeAudio(context.reservation) : Promise.resolve(),
    dispose(deviceId) { if (context?.deviceId === deviceId) return end(); return Promise.resolve(); },
    getState: () => ({ ...state }),
    subscribe(fn) { listeners.add(fn); fn({ ...state }); return () => listeners.delete(fn); },
  };
}

export const helmetDeviceCall = createHelmetDeviceCall({ fetchImpl: authFetch, rtc: rtcSession, getCloseRequest: captureAuthRequest });
onAuthCleared(({ request }) => helmetDeviceCall.detach({ reason: '登录已退出或失效', request }));
