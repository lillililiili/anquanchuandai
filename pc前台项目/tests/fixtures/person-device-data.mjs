// Browser-only acceptance data. These IDs are never sent to a backend.
export const SCENARIOS = Object.freeze([
  ['belt', '仅安全带'], ['helmet', '仅安全帽'], ['both', '帽带同领'],
  ['unassigned', '未领用'], ['offline', '已领用但离线'], ['revoked', '权限已撤销'],
]);

export function fixtureState(scenario = 'belt', now = new Date()) {
  if (!SCENARIOS.some(([id]) => id === scenario)) throw Error('Unknown isolated scenario');
  const observed = now.toISOString();
  const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  const start = new Date(now.getTime() - 3600000).toISOString();
  const online = scenario !== 'offline';
  const makeDevice = type => {
    const helmet = type === 'H';
    const featureStates = Object.fromEntries(['battery','wear','hooks','height','location','alarm','sos','video','photo','recording','voice','broadcast','vitals'].map(key => {
      const supported = ['battery','wear','location','alarm','sos','voice'].includes(key) || (helmet ? ['video','photo','recording','broadcast'].includes(key) : key === 'hooks');
      const verified = supported && ['battery','location','alarm','sos','video','hooks'].includes(key);
      return [key, { supported, verified, available: verified && online, reason: !supported ? '该型号不支持' : !verified ? key === 'voice' && !helmet ? '待接入' : '待联调' : !online ? '设备离线' : '' }];
    }));
    return {
      id: helmet ? 'QA-HELMET-ISOLATED-000001' : 'QA-BELT-ISOLATED-000002', type,
      source: helmet ? 'DIRECT_HELMET' : 'DIRECT_BELT', active: true, station: 'S1', online,
      sourceTime: observed, updated: observed, lastSeenAt: observed, freshness: 'CURRENT',
      battery: helmet ? 59 : 98, batteryFreshness: 'CURRENT', worn: null, isWearedFreshness: 'CURRENT',
      hookAEngaged: true, hookBEngaged: false,
      latitude: 36.655453, longitude: 117.087183, coordinateSystem: 'WGS84', locationValid: true,
      locationQuality: 'VALID', locationFreshness: 'CURRENT', locationReportedAt: observed,
      featureStates, capabilities: { actions: helmet ? ['start_video','stop_video','take_photo','start_recording','stop_recording','list_recordings','upload_recording','intercom','tts'] : [], metrics: ['battery','location'] },
    };
  };
  const devices = scenario === 'belt' ? [makeDevice('B')] : scenario === 'helmet' || scenario === 'revoked' ? [makeDevice('H')] : [makeDevice('H'), makeDevice('B')];
  const bindings = scenario === 'unassigned' ? [] : devices.map((device, index) => ({ id: `QA-BINDING-${index}`, assignmentId: `QA-BINDING-${index}`, assignmentVersion: 1, deviceId: device.id, personId: 'QA-PERSON', start, end: null, operator: '隔离验收' }));
  const person = { id: 'QA-PERSON', name: '隔离验收人员', station: 'S1', team: '隔离验收班组', active: true, updated: observed, phone: '', workId: 'QA-WORK', dutyStatus: 'UNKNOWN' };
  if (bindings.length && online) Object.assign(person, {
    latitude: devices[0].latitude, longitude: devices[0].longitude, coordinateSystem: 'WGS84',
    locationQuality: 'VALID', locationFreshness: 'CURRENT', locationReportedAt: observed, locationValid: true,
    locationDeviceId: devices[0].id, locationAssignmentId: bindings[0].assignmentId, locationAssignmentVersion: 1,
  });
  const features = {};
  for (const binding of bindings) for (const [key, feature] of Object.entries(devices.find(device => device.id === binding.deviceId).featureStates)) {
    if (!feature.supported || features[key]) continue;
    features[key] = { ...feature, deviceId: binding.deviceId, assignmentId: binding.assignmentId, assignmentVersion: binding.assignmentVersion,
      ...(scenario === 'revoked' && ['video','photo','recording','voice','broadcast'].includes(key) ? { available: false, reason: '无操作权限' } : {}),
    };
  }
  return {
    version: 1, seq: 1, stations: [{ id: 'S1', name: '隔离验收厂站' }], people: [person], devices, bindings,
    works: [{ id: 'QA-WORK', station: 'S1', name: '隔离验收作业（非真实业务）', date, start: '08:00', end: '17:00', status: '监护中', members: ['QA-PERSON'], leader: 'QA-PERSON', supervisor: 'QA-PERSON', timeline: [], risks: [], safetyMeasures: '', source: 'ISOLATED_BROWSER_FIXTURE' }],
    events: [{ id: 'QA-SOS', station: 'S1', deviceId: devices.at(-1).id, personId: scenario === 'unassigned' ? '' : 'QA-PERSON', workId: scenario === 'unassigned' ? '' : 'QA-WORK', type: '人员求助', title: '隔离验收 SOS（非真实事件）', date, time: '10:00:00', occurredAt: observed, status: '待认领', version: 1, snapshot: {}, timeline: [], photos: [], permissions: { 'events:claim': true, 'sos:assist': true } }],
    calls: [], media: [], groups: [], fences: [], fenceRecords: [], vitals: [], commands: [], communications: [],
    assistance: { 'QA-SOS': { status: 'waiting', members: [], timeline: [] } }, sos: { status: 'ended', members: [], timeline: [] },
    operator: { id: 'qa-operator', name: '隔离验收操作员' }, businessConfig: { dataVersion: 'isolated-browser-fixture', simulatedWatchVisible: false },
    personEquipmentContext: { 'QA-PERSON': { personId: 'QA-PERSON', features } },
  };
}
