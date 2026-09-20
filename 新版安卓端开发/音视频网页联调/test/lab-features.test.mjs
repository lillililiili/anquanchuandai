import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createLab } from '../server.mjs';

async function fixture(t, { ringMs = 45000, extraPeople = [], extraDevices = [] } = {}) {
  const simulatedEvents = [];
  const backend = http.createServer(async (req, res) => {
    const token = req.headers.authorization?.replace('Bearer ', '');
    const site = req.headers['x-site-id'] || '1';
    let result, code = 200;

    const pathname = req.url.split('?')[0];
    if (!token || token === 'bad') {
      code = 401;
    } else if (pathname === '/api/v1/me') {
      result = {
        userId: token,
        admin: token === 'admin',
        roles: token === 'duty' || token === 'siteA_duty' ? ['wear_duty'] : [],
        permissions: ['wear:call:start', 'wear:command:tts'],
        authorizedSites: [{ id: '1', status: '0' }, { id: '2', status: '0' }]
      };
    } else if (pathname === '/api/v1/people') {
      const allPeople = [
        { id: 'p1', name: '张工', personCode: 'P-001', teamName: '巡检一班', status: '0', siteIds: ['1'] },
        { id: 'p2', name: '李工', personCode: 'P-002', teamName: '检修二班', status: '0', siteIds: ['1'] },
        ...extraPeople
      ];
      result = {
        records: allPeople,
        total: allPeople.length
      };
    } else if (pathname.startsWith('/api/v1/people/')) {
      const id = pathname.split('/').pop();
      const found = extraPeople.find(p => p.id === id);
      result = found || { id, name: id === 'p1' ? '张工' : '李工', personCode: 'P-' + id, status: '0', siteIds: ['1'] };
    } else if (pathname === '/api/v1/devices') {
      const allDevices = [
        { id: 'd1', sn: 'MH-001', typeCode: 'helmet', siteId: '1', currentAssignment: { personId: 'p1', personName: '张工' } },
        { id: 'd2', sn: 'BLT-001', typeCode: 'belt', siteId: '1', currentAssignment: { personId: 'p1', personName: '张工' } },
        { id: 'd3', sn: 'MH-002', typeCode: 'helmet', siteId: '1', currentAssignment: { personId: 'p2', personName: '李工' } },
        ...extraDevices
      ];
      result = {
        records: allDevices,
        total: allDevices.length
      };
    } else if (pathname.startsWith('/api/v1/devices/')) {
      const id = pathname.split('/').pop();
      const found = extraDevices.find(d => d.id === id);
      result = found || {
        id,
        sn: 'TEST-' + id,
        typeCode: id === 'd2' ? 'belt' : 'helmet',
        siteId: '1',
        currentAssignment: { personId: id === 'd3' ? 'p2' : 'p1', personName: id === 'd3' ? '李工' : '张工' }
      };
    } else if (pathname === '/api/v1/work-tasks') {
      result = {
        records: [{ id: 't1', taskName: '主变巡视', taskCode: 'T-001', members: [{ personId: 'p1' }] }],
        total: 1
      };
    } else if (pathname.startsWith('/api/v1/work-tasks/')) {
      result = { id: 't1', taskName: '主变巡视', taskCode: 'T-001', members: [{ personId: 'p1' }] };
    } else if (pathname === '/api/v1/events/simulate') {
      let raw = '';
      for await (const c of req) raw += c;
      const parsed = JSON.parse(raw);
      simulatedEvents.push(parsed);
      result = { id: 'evt-' + simulatedEvents.length, ...parsed, demo: true };
    } else {
      result = { records: [], total: 0 };
    }

    res.writeHead(code, { 'Content-Type': 'application/json' }).end(
      JSON.stringify({ code, data: result, msg: code === 401 ? '未认证' : 'ok' })
    );
  });

  await new Promise(r => backend.listen(0, '127.0.0.1', r));
  const lab = createLab({ backendUrl: `http://127.0.0.1:${backend.address().port}`, ringMs });
  await new Promise(r => lab.server.listen(0, '127.0.0.1', r));

  t.after(async () => {
    await lab.close();
    await new Promise(r => backend.close(r));
  });

  async function api(path, { user = 'duty', site = '1', method = 'GET', body } = {}) {
    const r = await fetch(`http://127.0.0.1:${lab.server.address().port}/api/v1/lab${path}`, {
      method,
      headers: {
        Authorization: 'Bearer ' + user,
        'X-Site-Id': site,
        'Content-Type': 'application/json'
      },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    const j = await r.json();
    return { status: r.status, ...j };
  }

  return { api, simulatedEvents };
}

test('roster enriches people with assigned devices, tasks and presence', async t => {
  const { api } = await fixture(t);
  const res = await api('/roster');
  assert.equal(res.status, 200);
  assert.equal(res.data.people.length, 2);

  const p1 = res.data.people.find(p => p.id === 'p1');
  assert.ok(p1);
  assert.equal(p1.name, '张工');
  assert.equal(p1.assignedDevices.length, 2); // helmet d1 and belt d2
  assert.equal(p1.tasks.length, 1);
  assert.equal(p1.tasks[0].taskName, '主变巡视');
});

test('person can toggle online/offline without passwords and batch presence works', async t => {
  const { api } = await fixture(t);

  // Toggle single person online
  const pOnline = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: { personId: 'p1', online: true }
  });
  assert.equal(pOnline.status, 200);
  assert.equal(pOnline.data.online, true);

  // Check state
  const st1 = await api('/state');
  assert.ok(st1.data.people.some(p => p.personId === 'p1' && p.online === true));

  // Batch toggle
  const batchRes = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: {
      batch: [
        { personId: 'p1', online: false },
        { personId: 'p2', online: true }
      ]
    }
  });
  assert.equal(batchRes.status, 200);
  assert.equal(batchRes.data.batchUpdated, true);
});

test('custom device status simulation triggers event simulate and updates status', async t => {
  const { api, simulatedEvents } = await fixture(t);

  // 1. Helmet removal (脱帽)
  const removalRes = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: {
      deviceId: 'd1',
      customStatus: { code: 'helmet.removal', label: '员工脱帽' }
    }
  });
  assert.equal(removalRes.status, 200);
  assert.equal(removalRes.data.abnormal, true);
  assert.equal(removalRes.data.customStatus.code, 'helmet.removal');
  assert.equal(simulatedEvents.length, 1);
  assert.equal(simulatedEvents[0].type, 'realtime');
  assert.equal(simulatedEvents[0].scenarioCode, 'helmet.removal');

  // 2. Belt unhooked (安全带摘下/未挂钩)
  const unhookRes = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: {
      deviceId: 'd2',
      customStatus: { code: 'belt.unhooked', label: '安全带摘下' }
    }
  });
  assert.equal(unhookRes.status, 200);
  assert.equal(simulatedEvents.length, 2);
  assert.equal(simulatedEvents[1].scenarioCode, 'belt.unhooked');

  // 3. Reset back to normal
  const normalRes = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: {
      deviceId: 'd1',
      customStatus: { code: 'normal' }
    }
  });
  assert.equal(normalRes.status, 200);
  assert.equal(normalRes.data.abnormal, false);
  assert.equal(normalRes.data.customStatus, null);
});

test('helmet proactive call to duty staff and group call accept all', async t => {
  const { api } = await fixture(t);

  // Duty staff visits state to register presence
  await api('/state', { user: 'duty' });

  // Put d1 and d3 online
  await api('/presence', { user: 'admin', method: 'POST', body: { deviceId: 'd1', online: true } });
  await api('/presence', { user: 'admin', method: 'POST', body: { deviceId: 'd3', online: true } });

  // Proactive call from helmet d1
  const callRes = await api('/calls', {
    user: 'admin',
    method: 'POST',
    body: { deviceIds: ['d1'], direction: 'incoming' }
  });
  assert.equal(callRes.status, 200);
  assert.equal(callRes.data.direction, 'incoming');
  assert.equal(callRes.data.userId, 'duty');
  assert.equal(callRes.data.state, 'ringing');

  // Duty answers
  const answered = await api(`/calls/${callRes.data.id}/accept`, { user: 'duty', method: 'POST', body: {} });
  assert.equal(answered.data.state, 'connected');

  // Hangup
  await api(`/calls/${callRes.data.id}/end`, { user: 'duty', method: 'POST', body: {} });

  // Now duty initiates group call to d1 and d3
  const groupCall = await api('/calls', {
    user: 'duty',
    method: 'POST',
    body: { deviceIds: ['d1', 'd3'], direction: 'outgoing' }
  });
  assert.equal(groupCall.status, 200);
  assert.equal(groupCall.data.participants.length, 2);

  // Helmet side accepts all
  const groupAnswered = await api(`/calls/${groupCall.data.id}/accept`, {
    user: 'admin',
    method: 'POST',
    body: { all: true }
  });
  assert.equal(groupAnswered.data.state, 'connected');
  assert.ok(groupAnswered.data.participants.every(p => p.state === 'connected'));

  // Video enabled passive notice
  const videoEnabled = await api(`/calls/${groupCall.data.id}/video`, {
    user: 'duty',
    method: 'POST',
    body: { enabled: true }
  });
  assert.equal(videoEnabled.data.videoEnabled, true);

  // Group hangup all
  const groupEnded = await api(`/calls/${groupCall.data.id}/end`, {
    user: 'admin',
    method: 'POST',
    body: { all: true }
  });
  assert.equal(groupEnded.data.state, 'ended');
});

test('person without helmet cannot be activated online, and roster does not activate helmets', async t => {
  const { api } = await fixture(t, {
    extraPeople: [
      { id: 'p3', name: '王工', personCode: 'P-003', teamName: '未领用组', status: '0', siteIds: ['1'] }
    ]
  });

  // Reading a roster must not turn unreported equipment online.
  const rosterRes = await api('/roster');
  assert.equal(rosterRes.status, 200);
  const p1 = rosterRes.data.people.find(p => p.id === 'p1');
  const p3 = rosterRes.data.people.find(p => p.id === 'p3');
  assert.equal(p1.hasHelmet, true);
  assert.equal(p1.online, false);
  assert.equal(p3.hasHelmet, false);
  assert.equal(p3.online, false);

  // 2. Attempting to activate p3 online returns 400 error
  const activateP3 = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: { personId: 'p3', online: true }
  });
  assert.equal(activateP3.status, 400);
  assert.match(activateP3.msg, /未领用安全帽.*不可激活/);

  // 3. Batch presence activating all skips p3
  const batchRes = await api('/presence', {
    user: 'admin',
    method: 'POST',
    body: {
      batch: [
        { personId: 'p1', online: true },
        { personId: 'p3', online: true }
      ]
    }
  });
  assert.equal(batchRes.status, 200);

  // 4. Verify state: p1 is online, p3 is still offline
  const st = await api('/state');
  const p3State = st.data.people.find(p => p.personId === 'p3');
  assert.equal(p3State?.online ?? false, false);
});
