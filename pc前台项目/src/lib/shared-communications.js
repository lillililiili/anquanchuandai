import { db } from '@/mock/runtime';

export function sharedCalls(station) {
  return sharedRecords('call', station).map(row => ({
    ...row, time: row.startedAt, kind: '安卓设备语音', members: row.personId ? [row.personId] : [],
    status: ({requesting:'请求中',offered:'等待加入',connected:'本端已加入',ended:'已结束',unknown:'结果未确认'})[row.status] || row.status,
    history: [{time:row.startedAt,text:`${row.actorName} 发起设备 ${row.deviceId} 语音`},
      ...(row.connectedAt ? [{time:row.connectedAt,text:'安卓本端已加入；设备是否接通以现场 RTC 状态为准'}] : []),
      ...(row.endedAt ? [{time:row.endedAt,text:'通话已结束'}] : [])],
  }));
}
export function sharedBroadcasts(station) {
  return sharedRecords('broadcast', station).map(row => ({...row,time:row.startedAt,groupName:`安卓 · ${row.actorName}`,members:[],
    recipientLabel:(row.deviceIds || []).join('、'),status:row.status === 'accepted'?'设备平台已受理（播放未确认）':'受理结果未确认'}));
}
function sharedRecords(type, station) {
  const site=db.state.stations.find(s=>s.id===station)?.siteId;
  return (db.state.communicationRecords || []).filter(r=>r.operationType===type && r.siteId===site);
}
