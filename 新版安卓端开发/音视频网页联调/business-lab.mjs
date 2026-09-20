import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const previewSelection = {};
export function streamRandomVideo(req, res, selection = previewSelection) {
  let videoDir = path.resolve(process.cwd(), 'video');
  if (!fs.existsSync(videoDir)) {
    videoDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), 'video');
  }
  if (!fs.existsSync(videoDir)) {
    res.writeHead(404, { 'Content-Type': 'application/json' }).end(JSON.stringify({ code: 404, msg: '视频目录不存在' }));
    return true;
  }
  const files = fs.readdirSync(videoDir).filter(f => /\.(mp4|webm)$/i.test(f));
  if (!files.length) {
    res.writeHead(404, { 'Content-Type': 'application/json' }).end(JSON.stringify({ code: 404, msg: 'video 目录下无可用视频' }));
    return true;
  }
  // Keep the same file for every Range request in one call/device session.
  // Changing files halfway through a seek corrupts the decoder's byte stream.
  const randomFile = selection.videoFile || files[Math.floor(Math.random() * files.length)];
  if (!files.includes(randomFile)) {
    res.writeHead(404, { 'Content-Type': 'application/json' }).end(JSON.stringify({ code: 404, msg: '当前联调视频已移除，请重新开启画面' }));
    return true;
  }
  selection.videoFile = randomFile;
  const filePath = path.join(videoDir, randomFile);
  const stat = fs.statSync(filePath);
  const fileSize = stat.size;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Range, Content-Type',
    }).end();
    return true;
  }

  const type = /\.webm$/i.test(randomFile) ? 'video/webm' : 'video/mp4';
  const range = req.headers.range;
  if (range) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range);
    let start = match?.[1] ? Number(match[1]) : Math.max(0, fileSize - Number(match?.[2]));
    let end = match?.[1] && match?.[2] ? Math.min(Number(match[2]), fileSize - 1) : fileSize - 1;
    if (!match || (!match[1] && !match[2]) || !Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= fileSize || end < start) {
      res.writeHead(416, { 'Content-Range': `bytes */${fileSize}`, 'Accept-Ranges': 'bytes', 'Content-Length': '0', 'Cache-Control': 'no-store' }).end();
      return true;
    }
    const chunksize = (end - start) + 1;
    const stream = fs.createReadStream(filePath, { start, end });
    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': type,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache',
    });
    if (req.method === 'HEAD') { stream.destroy(); res.end(); }
    else { stream.on('error', () => res.destroy()); res.on('close', () => stream.destroy()); stream.pipe(res); }
  } else {
    res.writeHead(200, {
      'Content-Length': fileSize,
      'Content-Type': type,
      'Accept-Ranges': 'bytes',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache',
    });
    if (req.method === 'HEAD') res.end();
    else { const stream = fs.createReadStream(filePath); stream.on('error', () => res.destroy()); res.on('close', () => stream.destroy()); stream.pipe(res); }
  }
  return true;
}

// Local, authenticated signalling simulator. Never advertises real media delivery.
export function createBusinessLab({ backendUrl, ringMs = 45000 }) {
  const sites = new Map();
  const fail = (message, status = 400) => { throw Object.assign(new Error(message), { status }); };
  const active = c => !['ended', 'rejected', 'timed_out'].includes(c.state);
  const can = (me, permission) => me.admin || me.permissions?.some(p => [permission, '*:*:*'].includes(p));
  const duty = me => me.roles?.some(r => ['wear_duty', 'wear_team_lead'].includes(r));

  let cachedSystemToken = null;
  async function getBackendToken() {
    if (cachedSystemToken) return cachedSystemToken;
    try {
      const res = await fetch(`${backendUrl}/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 'siteA_duty', password: 'admin123' })
      });
      const data = await res.json();
      if (data.token) {
        cachedSystemToken = data.token;
        return cachedSystemToken;
      }
    } catch (e) {
      console.warn('Backend auto-login failed:', e);
    }
    return null;
  }

  // Device state is submitted through the authenticated main-platform API below.

  // 预定义各设备类型的模拟状态字典 (与主系统 simulation-scenarios.json 严格对齐)
  const SCENARIOS = {
    // Helmet
    'helmet.removal': { type: 'realtime', scenarioCode: 'helmet.removal', label: '脱帽告警', measurements: { durationSeconds: 60 } },
    'helmet.fall': { type: 'fall', scenarioCode: 'helmet.fall', label: '跌落告警', measurements: {} },
    'helmet.impact': { type: 'impact', scenarioCode: 'helmet.impact', label: '撞击告警', measurements: {} },
    'helmet.silent': { type: 'realtime', scenarioCode: 'helmet.silent', label: '静默倒地', measurements: { durationSeconds: 60 } },
    'helmet.climb': { type: 'realtime', scenarioCode: 'helmet.climb', label: '登高作业', measurements: { height: 5 } },
    'helmet.proximity': { type: 'realtime', scenarioCode: 'helmet.proximity', label: '近电预警', measurements: {} },
    'helmet.battery': { type: 'realtime', scenarioCode: 'helmet.battery', label: '低电量', measurements: { battery: 4 } },
    'helmet.temperature': { type: 'realtime', scenarioCode: 'helmet.temperature', label: 'CPU温度异常', measurements: { temperature: 80 } },
    'helmet.fence_enter': { type: 'geofence', scenarioCode: 'helmet.fence_enter', label: '进入禁区', measurements: {} },
    'helmet.fence_exit': { type: 'geofence', scenarioCode: 'helmet.fence_exit', label: '离开区域', measurements: {} },
    'helmet.sos': { type: 'sos', scenarioCode: 'helmet.sos', label: 'SOS求救', measurements: {} },
    // Belt
    'belt.unhooked': { type: 'realtime', scenarioCode: 'belt.unhooked', label: '安全带摘下/未挂钩', measurements: { durationSeconds: 60 } },
    'belt.unfastened': { type: 'realtime', scenarioCode: 'belt.unfastened', label: '腰带未扣紧', measurements: { durationSeconds: 60 } },
    'belt.low_anchor': { type: 'realtime', scenarioCode: 'belt.low_anchor', label: '低挂高用', measurements: { height: 5 } },
    'belt.fall': { type: 'fall', scenarioCode: 'belt.fall', label: '高空坠落', measurements: {} },
    'belt.battery': { type: 'realtime', scenarioCode: 'belt.battery', label: '低电量', measurements: { battery: 4 } },
    'belt.sos': { type: 'sos', scenarioCode: 'belt.sos', label: 'SOS求救', measurements: {} },
    // Watch
    'watch.off_wrist': { type: 'realtime', scenarioCode: 'watch.off_wrist', label: '员工离腕', measurements: { durationSeconds: 60 } },
    'watch.heart_high': { type: 'realtime', scenarioCode: 'watch.heart_high', label: '心率偏高', measurements: { heartRate: 130 } },
    'watch.heart_low': { type: 'realtime', scenarioCode: 'watch.heart_low', label: '心率偏低', measurements: { heartRate: 45 } },
    'watch.oxygen': { type: 'realtime', scenarioCode: 'watch.oxygen', label: '血氧偏低', measurements: { spo2: 88 } },
    'watch.temperature': { type: 'realtime', scenarioCode: 'watch.temperature', label: '体温偏高', measurements: { temperature: 39 } },
    'watch.fall': { type: 'fall', scenarioCode: 'watch.fall', label: '跌倒', measurements: {} },
    'watch.fence_exit': { type: 'geofence', scenarioCode: 'watch.fence_exit', label: '越界离开', measurements: {} },
    'watch.battery': { type: 'realtime', scenarioCode: 'watch.battery', label: '低电量', measurements: { battery: 4 } },
    'watch.sos': { type: 'sos', scenarioCode: 'watch.sos', label: 'SOS求救', measurements: {} },
  };

  return async function handle(req, res, url) {
    if (!url.pathname.startsWith('/api/v1/lab/')) return false;

    // Standalone console preview is a sample file, never a business camera.
    if (url.pathname === '/api/v1/lab/video/stream') {
      return streamRandomVideo(req, res);
    }
    const callVideo = /^\/api\/v1\/lab\/calls\/([0-9a-f-]{36})\/video\/stream$/.exec(url.pathname);
    const send = (status, data) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(data));
    try {
      let authHeader = req.headers.authorization || '';
      if (callVideo && (!/^Bearer \S+$/.test(authHeader) || !/^[1-9]\d*$/.test(req.headers['x-site-id'] || ''))) fail('视频请求需要有效登录及厂站', 401);
      if (!authHeader || authHeader === 'Bearer null' || authHeader === 'Bearer undefined' || authHeader === 'Bearer') {
        const sysTok = await getBackendToken();
        if (sysTok) authHeader = `Bearer ${sysTok}`;
      }

      const headers = {
        'Content-Type': 'application/json',
        Authorization: authHeader,
        'X-Site-Id': req.headers['x-site-id'] || '1'
      };

      async function api(path, method = 'GET', body) {
        const r = await fetch(backendUrl + '/api/v1' + path, {
          method,
          headers,
          body: body === undefined ? undefined : JSON.stringify(body),
          signal: AbortSignal.timeout(15000)
        });
        const j = await r.json();
        if (!r.ok || (j.code != null && j.code !== 200)) fail(j.msg || '业务接口拒绝请求', j.code === 401 ? 401 : 403);
        return j.data;
      }

      let me;
      try {
        me = await api('/me');
      } catch (err) {
        if (callVideo) throw err;
        // If auth fails, try refreshing system token once
        cachedSystemToken = null;
        const sysTok = await getBackendToken();
        if (sysTok) {
          headers.Authorization = `Bearer ${sysTok}`;
          me = await api('/me');
        } else {
          throw err;
        }
      }

      const siteId = String(headers['X-Site-Id'] || '1');
      if (!siteId || !me.authorizedSites?.some(s => String(s.id) === siteId && (s.status == null || String(s.status) === '0'))) fail('无厂站权限', 403);
      let site = sites.get(siteId);
      if (!site) sites.set(siteId, site = { devices: new Map(), people: new Map(), calls: [], messages: [], dispatchers: new Map(), reservations: new Set() });
      const now = Date.now(), userId = String(me.userId);
      if (callVideo) {
        if (!['GET', 'HEAD'].includes(req.method)) fail('视频请求方法不支持', 405);
        const call = site.calls.find(c => c.id === callVideo[1]);
        if (!call || !(me.admin || (call.userId === userId && duty(me)))) fail('无权查看该安全帽画面', 403);
        if (call.state !== 'connected' || call.videoEnabled !== true) fail('请接通通话并开启画面', 409);
        const deviceId = url.searchParams.get('deviceId');
        if (!call.participants.some(p => p.deviceId === deviceId && p.state === 'connected')) fail('设备未接入当前通话', 403);
        call.videoSelections ||= {};
        return streamRandomVideo(req, res, call.videoSelections[deviceId] ||= {});
      }
      for (const c of site.calls) {
        for (const p of c.participants) if (p.state === 'ringing' && now - (p.invitedAt ?? c.createdAt) > ringMs) p.state = 'timed_out';
        if (active(c) && !c.participants.some(p => ['ringing', 'connected'].includes(p.state))) { c.state = c.participants.every(p => p.state === 'timed_out') ? 'timed_out' : 'ended'; c.endedAt = now; }
        if (active(c) && c.direction === 'incoming' && now - c.createdAt > ringMs && c.state === 'ringing') { c.state = 'timed_out'; c.endedAt = now; }
        if (active(c) && site.dispatchers.has(c.userId) && now - site.dispatchers.get(c.userId).seen > 25000) { c.state = 'ended'; c.reason = '值班端离线'; c.endedAt = now; c.participants.forEach(p => { if (['ringing','connected'].includes(p.state)) p.state = 'ended'; }); }
      }
      for (const [id, d] of site.devices) {
        if (!d.online) {
          for (const c of site.calls.filter(active)) {
            const p = c.participants.find(p => p.deviceId === id);
            if (p && ['ringing', 'connected'].includes(p.state)) p.state = 'offline';
            if (!c.participants.some(p => ['ringing', 'connected'].includes(p.state))) { c.state = 'ended'; c.reason = '设备离线'; c.endedAt = now; }
          }
        }
      }
      for (const c of site.calls) if (c.state !== 'connected' || !c.participants.some(p => p.state === 'connected')) c.videoEnabled = false;
      let body = {};
      if (req.method !== 'GET') {
        let raw = '';
        for await (const chunk of req) { raw += chunk; if (raw.length > 65536) fail('请求过大'); }
        body = JSON.parse(raw || '{}');
      }
      async function all(path) {
        const out = [];
        for (let current = 1; current <= 200; current++) {
          const page = await api(`${path}?current=${current}&size=100`);
          if (Array.isArray(page)) return page;
          const rows = page.records || [];
          out.push(...rows);
          if (!rows.length || out.length >= Number(page.total)) return out;
        }
        fail('数据超过联调容量，请缩小厂站范围');
      }
      const consoleWrite = () => { if (!(me.admin || duty(me) || me.roles?.includes('wear_platform_admin'))) fail('无联调配置权限', 403); };
      const path = url.pathname.slice('/api/v1/lab'.length);
      let result;

      // Helper to detect main project duty operators
      async function getPlantDutyOperators() {
        try {
          const ops = await api('/duty/operators');
          return Array.isArray(ops) ? ops : [];
        } catch {
          return [];
        }
      }

      if (path === '/roster' && req.method === 'GET') {
        const [people, devices, taskRows, dutyOps] = await Promise.all([
          all('/people'),
          all('/devices'),
          all('/work-tasks'),
          getPlantDutyOperators()
        ]);
        async function details(rows, path) {
          const out = [];
          for (let offset = 0; offset < rows.length; offset += 6) out.push(...await Promise.all(rows.slice(offset,offset+6).map(r=>api(`${path}/${r.id}`))));
          return out;
        }
        const [tasks, deviceDetails] = await Promise.all([details(taskRows,'/work-tasks'),details(devices,'/devices')]);
        
        const enrichedTasks = tasks.map(t => ({
          ...t,
          taskName: t.title || t.taskName || `任务 #${t.id}`,
          taskCode: t.ticketNo || t.taskCode || ''
        }));

        // Assemble enriched people with bound equipment and tasks
        const enrichedPeople = people.map(p => {
          const pid = String(p.id);
          const assignedDevices = deviceDetails.filter(d => String(d.currentAssignment?.personId || '') === pid).map(d => ({
            ...d,
            lab: site.devices.get(String(d.id)) || null
          }));
          if (p.equipment && Array.isArray(p.equipment)) {
            for (const eq of p.equipment) {
              const eqDevId = String(eq.deviceId || eq.id);
              if (!assignedDevices.some(d => String(d.id) === eqDevId)) {
                const fullDev = deviceDetails.find(d => String(d.id) === eqDevId);
                assignedDevices.push({
                  id: eqDevId,
                  sn: eq.sn || fullDev?.sn || eqDevId,
                  typeCode: eq.typeCode || fullDev?.typeCode || 'helmet',
                  currentAssignment: { personId: pid, personName: p.name },
                  ...(fullDev || {}),
                  lab: site.devices.get(eqDevId) || null
                });
              }
            }
          }
          const memberTasks = enrichedTasks.filter(t => t.members?.some(m => String(m.personId) === pid)).map(t => ({
            id: t.id,
            taskName: t.taskName,
            taskCode: t.taskCode,
            status: t.status
          }));
          // Reading the roster must not bring equipment online or override another device's state.
          for (const d of assignedDevices) {
            let state = site.devices.get(String(d.id));
            if (!state) {
              state = {deviceId:String(d.id),sn:d.sn,typeCode:d.typeCode,personId:pid,personName:p.name,
                online:d.online === '1' && d.connectionQuality === 'ok',
                abnormal:Boolean(d.simulationStatus && d.simulationStatus !== 'normal'),
                customStatus:d.simulationStatus && d.simulationStatus !== 'normal'
                  ? {code:d.simulationStatus,label:d.simulationStatusLabel} : null,
                seen:now,controller:userId,simulation:true};
              site.devices.set(String(d.id),state);
            }
            state.personId=pid; state.personName=p.name;
            d.lab=state;
          }
          const hasHelmet=assignedDevices.some(d=>d.typeCode==='helmet');
          const isOnline=assignedDevices.some(d=>d.typeCode==='helmet' && d.lab?.online);
          const simPerson={personId:pid,personName:p.name,online:isOnline,seen:now};
          site.people.set(pid,simPerson);
          return {
            ...p,
            assignedDevices,
            tasks: memberTasks,
            online: isOnline,
            hasHelmet,
            lab: simPerson || null
          };
        });

        // Current active or detected duty staff
        const activeDispatcher = [...site.dispatchers.values()].find(d => d.duty && now - d.seen < 25000);
        const detectedDuty = activeDispatcher || dutyOps[0] || {
          userId: siteId === '2' ? '22' : '21',
          userName: siteId === '2' ? 'siteB_duty' : 'siteA_duty',
          nickName: siteId === '2' ? 'B站值班员' : 'A站值班员'
        };

        result = {
          people: enrichedPeople,
          tasks: enrichedTasks,
          devices: deviceDetails.map(d => ({ ...d, lab: site.devices.get(String(d.id)) || null })),
          dutyStaff: {
            userId: String(detectedDuty.userId),
            userName: detectedDuty.userName,
            name: detectedDuty.nickName || detectedDuty.name || detectedDuty.userName,
            online: Boolean(activeDispatcher && now - activeDispatcher.seen < 25000),
            allOperators: dutyOps
          },
          simulation: true
        };
      } else if (path === '/presence' && req.method === 'POST') {
        consoleWrite();
        const summaries = await all('/devices');
        const allDevs = [];
        for (let offset = 0; offset < summaries.length; offset += 6) {
          allDevs.push(...await Promise.all(summaries.slice(offset, offset + 6).map(d => api(`/devices/${d.id}`))));
        }
        // Ownership always comes from the main platform's current assignment.
        for (const d of allDevs) {
          const old = site.devices.get(String(d.id));
          if (old) {
            old.personId = String(d.currentAssignment?.personId || '');
            old.personName = d.currentAssignment?.personName || '';
          } else if (d.currentAssignment) {
            site.devices.set(String(d.id), {
              deviceId: String(d.id), sn: d.sn, typeCode: d.typeCode,
              personId: String(d.currentAssignment.personId), personName: d.currentAssignment.personName,
              online: false, abnormal: false, customStatus: null, seen: now, controller: userId, simulation: true,
            });
          }
        }
        if (body.batch && Array.isArray(body.batch)) {
          const updated = [];
          for (const item of body.batch) {
            if (item.personId) {
              const pid = String(item.personId);
              const personDevices = allDevs.filter(d => String(d.currentAssignment?.personId || '') === pid);
              let hasHelmet = personDevices.some(d => d.typeCode === 'helmet');
              if (!hasHelmet && Array.isArray(item.equipment)) {
                hasHelmet = item.equipment.some(eq => eq.typeCode === 'helmet' || allDevs.find(d => String(d.id) === String(eq.deviceId || eq.id))?.typeCode === 'helmet');
              }
              if (!hasHelmet && item.online === true) {
                // 未领用安全帽，不可激活在线状态
                continue;
              }
              site.people.set(pid, { personId: pid, online: item.online === true, seen: now });
              for (const dev of personDevices) {
                let d = site.devices.get(String(dev.id));
                if (!d) {
                  d = {
                    deviceId: String(dev.id),
                    sn: dev.sn,
                    typeCode: dev.typeCode,
                    personId: pid,
                    online: item.online === true,
                    abnormal: false,
                    customStatus: null,
                    seen: now,
                    simulation: true
                  };
                  site.devices.set(String(dev.id), d);
                } else {
                  d.online = item.online === true;
                  d.seen = now;
                  if (!item.online) {
                    d.customStatus = null;
                    d.abnormal = false;
                  }
                }
                updated.push(d);
              }
            } else if (item.deviceId) {
              const did = String(item.deviceId);
              const d = site.devices.get(did);
              if (d) {
                d.online = item.online === true;
                d.seen = now;
                if (!item.online) {
                  d.customStatus = null;
                  d.abnormal = false;
                }
                updated.push(d);
              }
            }
          }
          result = { batchUpdated: true, devices: updated, simulation: true };
        } else if (body.personId && !body.deviceId) {
          const pid = String(body.personId);
          const person = await api(`/people/${encodeURIComponent(pid)}`);
          if (!person.siteIds?.map(String).includes(siteId) || String(person.status) !== '0') fail('人员不在当前厂站或已停用', 403);
          
          const personDevices = allDevs.filter(d => String(d.currentAssignment?.personId || '') === pid);
          const hasHelmetInAssignment = personDevices.some(d => d.typeCode === 'helmet');
          const hasHelmetInEquipment = Array.isArray(person.equipment) && person.equipment.some(eq => {
            if (eq.typeCode === 'helmet') return true;
            const dev = allDevs.find(d => String(d.id) === String(eq.deviceId || eq.id));
            return dev?.typeCode === 'helmet';
          });
          const hasHelmet = hasHelmetInAssignment || hasHelmetInEquipment;
          if (!hasHelmet && body.online === true) {
            fail('该人员未领用安全帽，在线状态不可激活', 400);
          }

          site.people.set(pid, { personId: pid, personName: person.name, online: body.online === true, seen: now });
          for (const dev of personDevices) {
            let d = site.devices.get(String(dev.id));
            if (!d) {
              d = {
                deviceId: String(dev.id),
                sn: dev.sn,
                typeCode: dev.typeCode,
                personId: pid,
                personName: person.name,
                online: body.online === true,
                abnormal: false,
                customStatus: null,
                seen: now,
                simulation: true
              };
              site.devices.set(String(dev.id), d);
            } else {
              d.online = body.online === true;
              d.seen = now;
              if (!body.online) {
                d.customStatus = null;
                d.abnormal = false;
              }
            }
          }
          result = { personId: pid, online: body.online === true, seen: now, simulation: true };
        } else {
          const device = await api(`/devices/${encodeURIComponent(body.deviceId)}`);
          if (String(device.siteId) !== siteId) fail('设备不在当前厂站', 403);
          let personName = device.currentAssignment?.personName || '';
          if (body.personId) {
            const person = await api(`/people/${encodeURIComponent(body.personId)}`);
            if (!person.siteIds?.map(String).includes(siteId) || String(person.status) !== '0') fail('人员不在当前厂站或已停用', 403);
            if (String(body.personId) !== String(device.currentAssignment?.personId || '')) fail('请先在主平台完成设备领用，联调不能覆盖领用关系', 409);
            personName = person.name || '';
          }
          const old = site.devices.get(String(device.id));
          let devOnline = body.online !== undefined ? body.online === true : (old ? old.online : true);
          let abnormal = body.abnormal === undefined ? old?.abnormal === true : body.abnormal === true;
          let customStatus = body.customStatus || null;
          
          if (customStatus && customStatus.code) {
            if (customStatus.code === 'offline') {
              devOnline = false;
              customStatus = null;
              abnormal = false;
            } else if (customStatus.code === 'normal') {
              devOnline = true;
              customStatus = null;
              abnormal = false;
            } else if (SCENARIOS[customStatus.code]) {
              const sc = SCENARIOS[customStatus.code];
              devOnline = true;
              abnormal = true;
              try {
                const event = await api('/events/simulate', 'POST', {
                  deviceId: String(device.id),
                  siteId,
                  type: sc.type,
                  scenarioCode: sc.scenarioCode,
                  measurements: customStatus.measurements || sc.measurements || {},
                  sourceEventId: `call-lab:${customStatus.code}:${randomUUID()}`,
                  occurredAt: new Date().toISOString()
                });
                customStatus = {
                  code: sc.scenarioCode,
                  label: customStatus.label || sc.label,
                  type: sc.type,
                  eventId: String(event.id),
                  at: now
                };
              } catch (err) {
                console.error('Simulate event failed:', err);
                fail('告警事件生成与上报失败: ' + err.message, 400);
              }
            }
          } else if (old?.customStatus && body.online !== undefined && !body.customStatus) {
            customStatus = old.customStatus;
          }

          result = {
            deviceId: String(device.id),
            sn: device.sn,
            typeCode: device.typeCode,
            personId: String(device.currentAssignment?.personId || ''),
            online: devOnline,
            abnormal,
            customStatus,
            seen: now,
            controller: userId,
            simulation: true
          };
          result.personName = result.personId ? personName : '';
          site.devices.set(String(device.id), result);
          if (result.personId) {
            const pid = String(result.personId);
            site.people.set(pid, { personId: pid, personName: result.personName, online: result.online, seen: now });
          }
          if (old?.online && !result.online) for (const c of site.calls.filter(active)) {
            const p = c.participants.find(p => p.deviceId === result.deviceId);
            if (p) p.state = 'offline';
            if (!c.participants.some(p => ['ringing','connected'].includes(p.state))) { c.state = 'ended'; c.reason = '设备离线'; c.endedAt = now; }
            if (!c.participants.some(p => p.state === 'connected')) c.videoEnabled = false;
          }
        }
      } else if (path === '/state' && req.method === 'GET') {
        const consoleMode = url.searchParams.get('client') === 'console';
        if (consoleMode) {
          consoleWrite();
          // A permitted console maintains this station's enabled virtual devices,
          // including those enabled by another operator before a shift change.
          for (const d of site.devices.values()) if (d.online) d.seen = now;
          for (const p of site.people.values()) if (p.online) p.seen = now;
        } else if (can(me, 'wear:call:start')) site.dispatchers.set(userId, { userId, name: me.nickName || me.userName || userId, duty: duty(me), seen: now });
        
        const dutyOps = await getPlantDutyOperators();
        const activeDispatcher = [...site.dispatchers.values()].find(d => d.duty && now - d.seen < 25000);
        const primaryDuty = activeDispatcher || dutyOps[0] || {
          userId: siteId === '2' ? '22' : '21',
          userName: siteId === '2' ? 'siteB_duty' : 'siteA_duty',
          nickName: siteId === '2' ? 'B站值班员' : 'A站值班员'
        };

        result = {
          simulation: true,
          devices: [...site.devices.values()],
          people: [...site.people.values()],
          calls: site.calls.filter(c => consoleMode || c.userId === userId),
          messages: site.messages.filter(m => consoleMode || m.userId === userId),
          dispatchers: [...site.dispatchers.values()].filter(d => now - d.seen < 25000 && d.duty),
          dutyStaff: {
            userId: String(primaryDuty.userId),
            userName: primaryDuty.userName,
            name: primaryDuty.nickName || primaryDuty.name || primaryDuty.userName,
            online: Boolean(activeDispatcher && now - activeDispatcher.seen < 25000)
          }
        };
      } else if (path === '/calls' && req.method === 'POST') {
        if (!can(me, 'wear:call:start')) fail('无呼叫权限', 403);
        const incoming = body.direction === 'incoming';
        if (incoming) consoleWrite();
        const ids = [...new Set((body.deviceIds || []).map(String))];
        if (!ids.length || ids.length > 30) fail('请选择 1–30 台设备');
        if (incoming && ids.length !== 1) fail('设备来电每次请选择一台安全帽');
        const devices = ids.map(id => site.devices.get(id));
        if (devices.some(d => !d?.online)) fail('所选虚拟设备尚未上线', 409);
        if (devices.some(d => d.typeCode !== 'helmet')) fail('本次语音和视频联调仅支持安全帽');

        // Automatically target the main project's detected duty operator
        let target = userId;
        if (incoming) {
          const dutyDispatchers = [...site.dispatchers.values()].filter(d => d.duty && now - d.seen < 25000);
          if (!dutyDispatchers.length) fail('当前厂站没有在线值班人员', 409);
          if (dutyDispatchers.length > 1) fail('当前厂站有多个在线值班人员，请在后台保持唯一值班接听端', 409);
          target = dutyDispatchers[0].userId;
        }

        const reserved = [`u:${target}`, ...ids.map(id=>`d:${id}`)];
        if (reserved.some(key=>site.reservations.has(key))) fail('值班端或设备正在建立通话',409);
        if (site.calls.some(c => active(c) && (c.userId === target || c.participants.some(p => ids.includes(p.deviceId) && ['ringing','connected'].includes(p.state))))) fail('值班端或设备正在通话', 409);
        result = {
          id: randomUUID(),
          siteId,
          userId: target,
          direction: incoming ? 'incoming' : 'outgoing',
          video: false,
          videoEnabled: false,
          sos: incoming && body.sos === true,
          state: 'ringing',
          createdAt: now,
          connectedAt: null,
          simulation: true,
          participants: devices.map(d => ({ deviceId: d.deviceId, sn: d.sn, personId: d.personId, state: 'ringing' }))
        };
        result.participants.forEach(p => p.personName = site.devices.get(p.deviceId)?.personName || '');
        reserved.forEach(key=>site.reservations.add(key));
        try {
          if (result.sos) {
            const actualDevice = await api(`/devices/${encodeURIComponent(ids[0])}`);
            if (String(actualDevice.siteId) !== siteId) fail('设备已不属于当前厂站，SOS 呼叫未发起',409);
            const actualPersonId = String(actualDevice.currentAssignment?.personId || '');
            const simulatedPersonId = String(result.participants[0].personId || '');
            if (simulatedPersonId !== actualPersonId) {
              fail('SOS 必须与设备真实佩戴人一致。请将测试佩戴人设为设备当前真实佩戴人；虚拟佩戴仅用于普通通信联调，未修改业务绑定',409);
            }
            const event = await api('/events/simulate', 'POST', { deviceId: ids[0], siteId, type: 'sos', sourceEventId: `call-lab:${result.id}`, occurredAt: new Date().toISOString() });
            result.eventId = String(event.id);
          }
          if (ids.some(id => !site.devices.get(id)?.online)) {
            fail(result.eventId ? `SOS事件 ${result.eventId} 已登记，但设备已离线，呼叫未发起` : '设备已离线，呼叫未发起', 409);
          }
          site.calls.unshift(result); site.calls = site.calls.slice(0,100);
        } finally { reserved.forEach(key=>site.reservations.delete(key)); }
      } else if (/^\/calls\/[^/]+\/invite$/.test(path) && req.method === 'POST') {
        const call = site.calls.find(c => c.id === path.split('/')[2]);
        if (!call) fail('通话不存在', 404);
        if (!can(me, 'wear:call:start') || call.userId !== userId || !(me.admin || duty(me))) fail('仅当前通话的值班端可邀请人员', 403);
        if (call.state !== 'connected') fail('请在通话接通后邀请人员', 409);
        if (!Array.isArray(body.deviceIds) || !body.deviceIds.length || body.deviceIds.length > 30) fail('请选择 1–30 台安全帽');
        const requested = [...new Set(body.deviceIds.map(String))];
        const ids = requested.filter(id => !call.participants.some(p => p.deviceId === id));
        if (call.participants.length + ids.length > 30) fail('当前通话最多支持 30 台设备');
        const reserved = [`u:${call.userId}`, ...ids.map(id => `d:${id}`)];
        if (reserved.some(key => site.reservations.has(key))) fail('邀请正在处理，请稍后同步状态', 409);
        reserved.forEach(key => site.reservations.add(key));
        try {
          const additions = [];
          for (const id of ids) {
            const device = await api(`/devices/${encodeURIComponent(id)}`);
            if (String(device.siteId) !== siteId) fail('所选设备不属于当前厂站', 403);
            if (device.typeCode !== 'helmet' || !device.capabilities?.actions?.includes('intercom')) fail('所选设备不支持呼叫', 400);
            if (!['1', 'true', 'online'].includes(String(device.online)) || device.connectionQuality !== 'ok' || !site.devices.get(id)?.online) fail('所选设备已离线，请刷新后重试', 409);
            if (site.calls.some(c => c.id !== call.id && active(c) && c.participants.some(p => p.deviceId === id && ['ringing','connected'].includes(p.state)))) fail('所选设备正在其他通话中', 409);
            additions.push({deviceId:id, sn:device.sn, personId:String(device.currentAssignment?.personId || ''), personName:device.currentAssignment?.personName || '', state:'ringing', direction:'outgoing', invitedAt:Date.now()});
          }
          // The original call may have ended while backend membership was loading.
          if (call.state !== 'connected' || !call.participants.some(p => p.state === 'connected')) fail('当前通话已结束', 409);
          if (ids.some(id => !site.devices.get(id)?.online)) fail('所选设备已离线，请刷新后重试', 409);
          call.participants.push(...additions);
          result = call;
        } finally { reserved.forEach(key => site.reservations.delete(key)); }
      } else if (/^\/calls\/[^/]+\/video$/.test(path) && req.method === 'POST') {
        const id = path.split('/')[2];
        const call = site.calls.find(c => c.id === id);
        if (!call) fail('通话不存在', 404);
        if (!(me.admin || (call.userId === userId && duty(me)))) fail('无权查看安全帽画面', 403);
        if (typeof body.enabled !== 'boolean') fail('请指定是否开启画面');
        if (call.state !== 'connected' || !call.participants.some(p => p.state === 'connected')) fail('请在通话接听后查看安全帽画面', 409);
        call.videoEnabled = body.enabled;
        if (body.enabled) {
          call.streamUrl = `/api/v1/lab/video/stream?callId=${id}`;
        } else {
          delete call.streamUrl;
        }
        result = call;
      } else if (/^\/calls\/[^/]+\/(accept|reject|end)$/.test(path) && req.method === 'POST') {
        const [, , id, action] = path.split('/');
        const call = site.calls.find(c => c.id === id);
        if (!call) fail('通话不存在', 404);
        if (!active(call)) fail('通话已结束', 409);
        
        if (action === 'end') {
          if (body.all) {
            call.state = 'ended';
            call.endedAt = now;
            call.participants.forEach(p => p.state = 'ended');
          } else if (body.deviceId) {
            const p = call.participants.find(p => p.deviceId === String(body.deviceId));
            if (!p) fail('设备不属于此通话', 403);
            p.state = 'ended';
            if (!call.participants.some(p => ['ringing','connected'].includes(p.state))) { call.state = 'ended'; call.endedAt = now; }
          } else {
            if (!me.admin && call.userId !== userId) fail('无权处理他人通话', 403);
            call.state = 'ended'; call.endedAt = now; call.participants.forEach(p => p.state = 'ended');
          }
        } else if (body.all) {
          for (const p of call.participants) {
            if (p.state === 'ringing') {
              p.state = action === 'accept' ? 'connected' : 'rejected';
            }
          }
          if (action === 'accept') {
            call.state = 'connected';
            call.connectedAt ||= now;
          } else if (!call.participants.some(p => ['ringing','connected'].includes(p.state))) {
            call.state = 'rejected';
            call.endedAt = now;
          }
        } else if (body.deviceId) {
          const p = call.participants.find(p => p.deviceId === String(body.deviceId));
          if (!p || p.state !== 'ringing') fail('该设备没有待接来电', 409);
          p.state = action === 'accept' ? 'connected' : 'rejected';
          if (action === 'accept') { call.state = 'connected'; call.connectedAt ||= now; }
          else if (!call.participants.some(p => ['ringing','connected'].includes(p.state))) { call.state = 'rejected'; call.endedAt = now; }
        } else {
          if (!me.admin && call.userId !== userId) fail('无权处理他人通话', 403);
          if (call.state !== 'ringing') fail('当前无待接来电', 409);
          call.state = action === 'accept' ? 'connected' : 'rejected';
          call.participants.forEach(p => p.state = call.state);
          if (action === 'accept') call.connectedAt = now; else call.endedAt = now;
        }
        if (call.state !== 'connected' || !call.participants.some(p => p.state === 'connected')) call.videoEnabled = false;
        result = call;
      } else if (path === '/tts' && req.method === 'POST') {
        if (!can(me, 'wear:command:tts')) fail('无播报权限', 403);
        const text = String(body.text || '').trim(), ids = [...new Set((body.deviceIds || []).map(String))];
        if (!text || text.length > 500 || !ids.length || ids.length > 30) fail('请选择设备并填写 1–500 字播报内容');
        result = { id: randomUUID(), userId, text, createdAt: now, simulation: true, receipts: ids.map(id => ({ deviceId: id, state: site.devices.get(id)?.online ? 'sent' : 'offline' })) };
        site.messages.unshift(result); site.messages = site.messages.slice(0,100);
      } else if (path === '/tts/ack' && req.method === 'POST') {
        consoleWrite(); const m = site.messages.find(m => m.id === body.id), r = m?.receipts.find(r => r.deviceId === String(body.deviceId));
        if (!r || r.state !== 'sent') fail('没有待确认播报');
        if (!site.devices.get(String(body.deviceId))?.online) fail('设备已离线，不能确认播报',409);
        r.state = 'acknowledged'; result = m;
      } else if (path === '/events' && req.method === 'GET') {
        const current = url.searchParams.get('current') || '1';
        const size = url.searchParams.get('size') || '20';
        result = await api(`/events?current=${encodeURIComponent(current)}&size=${encodeURIComponent(size)}`);
      } else if (path.startsWith('/events/') && req.method === 'POST') {
        const subPath = path.slice('/events/'.length);
        result = await api(`/events/${subPath}`, 'POST', body);
      } else fail('未知联调接口', 404);
      // Console changes and heartbeats are acknowledged only after the main platform stores them.
      // Android reads /devices; it never needs this process's presence map.
      if ((path === '/presence' && req.method === 'POST') ||
          (path === '/state' && url.searchParams.get('client') === 'console')) {
        const pending = [...site.devices.values()].filter(d => {
          if (path === '/state' && !d.online) return false;
          if (path === '/presence') {
            const selected = body.deviceId ? String(body.deviceId) === d.deviceId
              : body.personId ? String(body.personId) === String(d.personId)
              : (body.batch || []).some(item => item.deviceId ? String(item.deviceId) === d.deviceId : String(item.personId) === String(d.personId));
            if (!selected) return false;
          }
          const signature = JSON.stringify([d.online, d.abnormal, d.customStatus?.code, d.customStatus?.label]);
          return signature !== d.mainSignature || (d.online && now - (d.mainSyncedAt || 0) >= 5000);
        });
        for (let offset = 0; offset < pending.length; offset += 6) {
          await Promise.all(pending.slice(offset, offset + 6).map(async d => {
            await api(`/simulation/devices/${encodeURIComponent(d.deviceId)}/state`, 'POST', {
              online: d.online === true,
              status: d.customStatus?.code || (d.abnormal ? 'abnormal' : 'normal'),
              statusLabel: d.customStatus?.label || (d.abnormal ? '设备异常' : '正常'),
            });
            d.mainSignature = JSON.stringify([d.online, d.abnormal, d.customStatus?.code, d.customStatus?.label]);
            d.mainSyncedAt = now;
          }));
        }
      }
      send(200, { code: 200, data: result });
    } catch (e) { send(e.status || 400, { code: e.status || 400, msg: e.message }); }
    return true;
  };
}
