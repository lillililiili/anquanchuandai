import { db } from '@/mock/runtime';

export function sharedCalls(station) {
  return sharedRecords('call', station).map(row => ({
    ...row, time: row.startedAt || row.createdAt || '', kind: '设备语音', members: row.personId ? [row.personId] : [],
    status: ({requesting:'请求中',offered:'等待设备接听',connected:row.serverConnected===true?'设备已接通':'设备接通待确认',ending:'正在结束',ended:'已结束',failed:'失败',unknown:'结果未确认'})[row.status] || row.status,
    history: [{time:row.startedAt,text:`${row.actorName} 发起设备 ${row.deviceId} 语音`},
      ...(row.connectedAt ? [{time:row.connectedAt,text:row.serverConnected===true?'设备接通已由服务端确认':'本端已加入，设备接通待确认'}] : []),
      ...(row.endedAt ? [{time:row.endedAt,text:'通话已结束'}] : [])],
  }));
}
export function sharedBroadcasts(station) {
  return sharedRecords('broadcast', station).map(row => ({...row,time:row.startedAt || row.createdAt || '',groupName:row.actorName || '设备广播',members:[],
    recipientLabel:(row.deviceIds || []).join('、'),status:row.status === 'accepted'?'设备平台已受理（播放未确认）':'受理结果未确认'}));
}
function sharedRecords(type, station) {
  const site=db.state.stations.find(s=>s.id===station)?.siteId;
  return (db.state.communicationRecords || []).filter(r=>r.operationType===type && r.siteId===site);
}
