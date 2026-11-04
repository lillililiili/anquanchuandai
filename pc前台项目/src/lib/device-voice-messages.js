export function isDeviceVoiceMessage(row) {
  return !!row?.id && row.operationType === 'deviceVoiceMessage' && row.direction === 'DEVICE_TO_PLATFORM' &&
    row.source === 'DIRECT_HELMET' && row.reportAct === 'ca_sending_message' && row.timeBasis === 'RECEIVED_AT';
}

function playbackExpiry(value) {
  if (typeof value !== 'string') return NaN;
  const match = value.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-](\d{2}):(\d{2}))$/);
  if (!match) return NaN;
  const date = new Date(match[1] + 'T00:00:00Z');
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== match[1] ||
      Number(match[2]) > 23 || Number(match[3]) > 59 || Number(match[4]) > 59 ||
      Number(match[5] || 0) > 23 || Number(match[6] || 0) > 59) return NaN;
  return Date.parse(value);
}

export function voiceMessagePerson(row) {
  return row.personName || (row.personId ? `${row.personId}（历史姓名未提供）` : '未关联人员');
}

export function voiceMessageStatus(row) {
  if (row.status === 'READY' && row.playable === true && row.assetId) return '录音已收到';
  if (row.status === 'REJECTED') return '消息已收到，录音未通过校验';
  return '消息已收到，暂无可播放录音';
}

export function voicePlaybackAuthorization(row, result, now = Date.now()) {
  if (!isDeviceVoiceMessage(row) || row.status !== 'READY' || row.playable !== true || !row.assetId ||
      result?.id !== row.id || result.assetId !== row.assetId || result.mime !== 'audio/mpeg') throw Error('录音授权与当前消息不一致');
  let url;
  try { url = new URL(result.url); } catch { throw Error('录音播放地址无效'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.hash ||
      url.pathname !== `/helmet-media/files/${encodeURIComponent(row.assetId)}` ||
      [...url.searchParams.keys()].some(key => !['variant', 'token'].includes(key)) ||
      url.searchParams.getAll('variant').length !== 1 || url.searchParams.get('variant') !== 'playback' ||
      url.searchParams.getAll('token').length !== 1 || !url.searchParams.get('token')) throw Error('录音播放地址无效');
  const expiresAt = playbackExpiry(result.expiresAt);
  if (!Number.isFinite(expiresAt) || expiresAt <= now) throw Error('录音播放授权已过期，请重新加载');
  return { id: row.id, assetId: row.assetId, url: url.href, mime: result.mime, expiresAt };
}

export function createDeviceVoiceApi(fetchImpl) {
  async function request(path, signal) {
    const response = await fetchImpl(`/api/guardian/v1/voice-messages${path}`, { signal });
    if (!response.ok) throw Object.assign(Error(({401:'登录已失效',403:'没有查看此录音的权限',404:'语音消息不存在或不在授权范围',503:'设备语音消息暂不可用'})[response.status] || '设备语音消息读取失败，请稍后重试'), { status: response.status });
    return response.json();
  }
  return {
    list: ({siteId,pageNum,pageSize}, signal) => request('?' + new URLSearchParams({siteId,pageNum,pageSize}), signal),
    playback: (id, signal) => request('/' + encodeURIComponent(id) + '/playback', signal),
  };
}
