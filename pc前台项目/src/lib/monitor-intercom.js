import { createRtcSession } from './rtc.js';
import { communicationGuard } from './communication-guard.js';
import { splitProxyPath } from './zlm-session.js';

// The video player owns the viewing lease. This control owns only its outgoing audio.
export function createMonitorIntercom({ guard = communicationGuard, rtc = createRtcSession(), onChange = () => {} } = {}) {
  let owner, closing;
  async function stop(message = '') {
    if (closing) return closing;
    const token = owner;
    if (!token) return;
    owner = null;
    onChange('closing', '');
    closing = rtc.leaveChannel(token).finally(() => {
      guard.release(token);
      closing = null;
      onChange('off', message);
    });
    return closing;
  }
  async function start(live) {
    if (owner || closing) return;
    let token;
    try {
      const { sessionId, deviceId, playUrl, talkUrl, heartbeatUrl } = live;
      const path = '/api/guardian/v1/split/sessions/' + sessionId;
      if (live.protocol !== 'ZLM_WEBRTC' || !deviceId || playUrl !== path + '/devices/' + deviceId + '/play' ||
          talkUrl !== path + '/devices/' + deviceId + '/talk' || heartbeatUrl !== path + '/heartbeat') throw Error('当前监看会话缺少对讲授权');
      splitProxyPath(talkUrl);
      token = guard.acquire();
      owner = token;
      onChange('preparing', '');
      await rtc.prepareMicrophone({ reservation: token });
      if (owner !== token) return;
      onChange('connecting', '');
      await rtc.joinChannel({ protocol: live.protocol, callId: sessionId, heartbeatUrl, sessions: [{ deviceId, playUrl, talkUrl }] }, {
        reservation: token, talkOnly: true,
        onMediaState(state) {
          if (owner !== token) return;
          if (state === 'local_joined') onChange('on', '');
          if (state === 'failed') void stop('对讲连接已中断，可重新开启麦克风');
        },
      });
    } catch (error) {
      if (!token) onChange('off', error.message);
      else if (owner === token) await stop(error.message || '麦克风连接失败');
    }
  }
  return { start, stop };
}
