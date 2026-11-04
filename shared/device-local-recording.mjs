export const LOCAL_RECORDING_TITLE = '设备本地录像 · 最后上报';
export const LOCAL_RECORDING_NOTE = '仅表示设备最后一次上报，不代表当前仍在录制或文件已生成。';

// This is a historical device observation, independent of platform recording
// commands, online status, media assets and acceptance of remote operations.
export function deviceLocalRecordingPresentation(device) {
  const visible = device?.source === 'DIRECT_HELMET' && ['H', 'HELMET'].includes(device?.type) && device.simulated !== true && device.demo !== true;
  const report = device?.localRecording;
  const reported = visible && report != null && typeof report === 'object' && !Array.isArray(report);
  const evidence = reported && report.source === 'DIRECT_HELMET' && report.reportAct === 'toggle_localrecord' && report.timeBasis === 'RECEIVED_AT';
  const label = !reported ? '暂无上报' : evidence && report.rawType === '0' && report.state === 'RECORDING' ? '开启' : evidence && report.rawType === '1' && report.state === 'STOPPED' ? '关闭' : '状态未知';
  const timestamp = typeof report?.receivedAt === 'string' ? report.receivedAt : '';
  const format = timestamp.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-]\d{2}:?\d{2})$/);
  const date = format ? new Date(format[1]+'T00:00:00Z') : null;
  const validTime = format && Number.isFinite(date.getTime()) && date.toISOString().slice(0,10) === format[1] && Number(format[2]) < 24 && Number(format[3]) < 60 && Number(format[4]) < 60 && Number.isFinite(Date.parse(timestamp));
  const receivedAt = evidence && validTime ? timestamp : null;
  return { visible, reported, label, receivedAt, title: LOCAL_RECORDING_TITLE, note: LOCAL_RECORDING_NOTE,
    personLabel: !reported ? '' : !evidence ? '归属未确认' : report.personName || (report.personId ? `${report.personId}（姓名未提供）` : '未关联人员') };
}
