import { formatRecordedDateTime } from './date-time.js';

export function durationText(value) {
  if (value == null || typeof value === 'string' && !value.trim() || typeof value === 'boolean' || !Number.isFinite(Number(value)) || Number(value) < 0) return '时长未提供';
  const total = Math.floor(Number(value));
  return String(Math.floor(total / 60)).padStart(2, '0') + ':' + String(total % 60).padStart(2, '0');
}

export function mediaKindLabel(media) {
  if (String(media?.kind).toLowerCase() === 'photo') return '照片';
  if (String(media?.kind).toLowerCase() !== 'video') return '影像资料';
  const origin = media.mediaOrigin;
  if (origin === 'PLATFORM_RECORDING' || !origin && media.commandAction === 'start_recording') return '平台录制';
  if (origin === 'DEVICE_RECORDING' || !origin && media.commandAction === 'upload_recording') return '设备内录像';
  if (media.simulated === true || media.source === 'DEMO') return '模拟录像';
  return '录像（录制来源未确认）';
}

export function mediaSourceLabel(media) {
  return ({ DIRECT_HELMET: '安全帽直连接入', DIRECT_BELT: '安全带直连接入', PLATFORM: '厂家平台同步',
    DEMO_WATCH: '模拟手表', DEMO: '模拟数据', MANUAL: '人工上传' })[media?.source] || '来源待确认';
}

export function mediaTime(media) {
  if (!media?.capturedAt && media?.timeBasis === 'RECEIVED_AT' && media?.receivedAt)
    return { label: '接收时间', value: formatRecordedDateTime(media.receivedAt) };
  return { label: media?.capturedAt ? '拍摄时间' : '资料生成时间', value: formatRecordedDateTime(media?.capturedAt || media?.createdAt || media?.created) };
}

export function mediaPerson(media) {
  if (!media?.personId && !media?.personName && (media?.receivedPersonId || media?.receivedPersonName))
    return { label: media.scopeBasis === 'UPLOAD_REQUEST' ? '上传时领用人' : '接收时领用人', value: media.receivedPersonName || `${media.receivedPersonId}（历史姓名未提供）` };
  return { label: '关联人员', value: media?.snapshot?.personName || media?.personName || (media?.personId ? `${media.personId}（历史姓名未提供）` : '未关联人员') };
}

export function normalizeMedia(media, station = media.station) {
  const time = mediaTime(media);
  return { ...media, station, kind: String(media.kind || '').toLowerCase(), title: media.title || media.originalName || media.name || '未命名影像资料',
    date: /^\d{4}-\d{2}-\d{2} /.test(time.value) ? time.value.slice(0, 10) : media.date || '',
    snapshot: { ...media.snapshot, personName: media.snapshot?.personName || media.personName || (media.personId ? `${media.personId}（历史姓名未提供）` : '未关联人员') } };
}
