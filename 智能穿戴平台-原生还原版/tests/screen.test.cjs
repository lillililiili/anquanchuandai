const {test} = require("node:test");
const assert = require("node:assert/strict");
const D = require("../js/data.js"), M = require("../js/screen-model.js");
const create = () => D.createStore({getItem: () => null, setItem: () => {}});
const now = D.DATE + " 10:42:18";
test("大屏轮播覆盖全部八人并双向循环，空厂站安全返回", () => {
  const list=create().state.people, seen=[];
  let id=list[0].id;
  for(let i=0;i<8;i++){seen.push(id);id=M.nextPerson(list,id);}
  assert.equal(new Set(seen).size,8);assert.equal(id,"P1");
  assert.equal(M.nextPerson(list,"P1",-1),"P8");assert.equal(M.nextPerson([],"P1"),"");
});
test("生命体征和曲线使用同一人员当前绑定；体温不会冒充皮肤温度", () => {
  const db=create(), a=M.currentVital(db,db.person("P1"),now), b=M.currentVital(db,db.person("P2"),now);
  assert.equal(a.values[0],72);assert.equal(b.values[0],78);
  assert.equal(a.trend.at(-1).value,a.values[0]);assert.equal(b.trend.at(-1).value,b.values[0]);
  assert.equal(a.values[2],34.2);
  const record=db.state.vitals.find(v=>v.personId==="P1");record.id="OBS-INCOMING";record.source="设备观测";
  assert.equal(M.currentVital(db,db.person("P1"),now).values[2],null);
  record.skinTemperature=33.8;assert.equal(M.currentVital(db,db.person("P1"),now).values[2],33.8);
});
test("离线、过期、未佩戴及无观测保留人员但清空读数与曲线", () => {
  const db=create();
  const read=()=>M.currentVital(db,db.person("P1"),now);
  db.device("RL-W001").online=false;assert.equal(read().status,"离线");assert.deepEqual(read().values,[null,null,null]);assert.deepEqual(read().trend,[]);
  db.device("RL-W001").online=true;
  db.state.vitals.find(v=>v.personId==="P1").observedAt=D.DATE+" 10:00:00";
  assert.equal(read().status,"数据过期");assert.deepEqual(read().values,[null,null,null]);
  db.state.vitals=[];assert.equal(read().status,"暂无数据");
  db.state.bindings.find(b=>b.deviceId==="RL-W001"&&!b.end).end=now;assert.equal(read().status,"未佩戴");
  assert.equal(M.currentVital(db,null,now).status,"暂无当班人员");
});
test("视频轮播只展示当前厂站可用通道，保留实际人机归属", () => {
  const db=create(), list=M.videoPeople(db,db.stats({station:"S1"}).people);
  assert.equal(list.length,6);assert.deepEqual(list.slice(0,3).map(p=>p.id),["P1","P5","P6"]);
  assert.ok(!list.some(p=>p.id==="P4"||p.id==="P7"));
  assert.deepEqual(M.videoPeople(db,db.stats({station:"S2"}).people),[]);
});
test("重点事件轮播不会移走未解除的生命体征异常", () => {
  const normal=Array.from({length:7},(_,i)=>({id:String(i),status:"处理中"}));
  const urgent={id:"urgent",status:"待认领",type:"生命体征"};
  for(let i=0;i<14;i++){const list=M.eventWindow([...normal,urgent],i);assert.equal(list.length,3);assert.equal(list[0].id,"urgent");}
  assert.deepEqual(M.eventWindow([],0),[]);
  assert.equal(M.isVitalAlert({...urgent,status:"已核验"}),false);
});
