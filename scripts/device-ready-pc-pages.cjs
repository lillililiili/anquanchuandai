// Read-only PC page walkthrough using the local existing dev servers.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE);
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const out = path.resolve(__dirname,'../output/device-ready/pc-pages'); fs.mkdirSync(out,{recursive:true});
const steps=[]; const errors=[];
async function capture(page,name,expected) {
 await page.waitForTimeout(350);
 const text=await page.locator('body').innerText();
 assert(text.includes(expected),`${name} missing ${expected}`);
 assert(!/后端未连接|业务数据读取失败|加载失败/.test(text),`${name} load failed`);
 const screenshot=path.join(out,`${name}.png`);
 await page.screenshot({path:screenshot,fullPage:true});
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth+2);
 steps.push({name,url:page.url(),expected,overflow,screenshot,passed:true});
 fs.writeFileSync(path.join(out,`${name}.txt`),text);
 console.log('PASS '+name);
}
async function main(){
 const browser=await chromium.launch({headless:true,channel:'msedge'});
 try{
  const portal=await browser.newPage({viewport:{width:1440,height:1000}});
  portal.on('pageerror',e=>errors.push({surface:'portal',error:e.message}));
  await portal.goto('http://127.0.0.1:5191/');
  await portal.getByPlaceholder('请输入工作账号').fill('wear_duty');
  await portal.getByPlaceholder('请输入密码',{exact:true}).fill(process.env.DEVICE_READY_USER_PASSWORD);
  await portal.getByRole('button',{name:'登录',exact:true}).click();
  await portal.waitForURL(/overview/);
  await capture(portal,'01-portal-home','当班人员');
  for(const [label,expected,slug] of [['人员与装备','陈建国','personnel'],['作业监护','锅炉平台检修','works'],['告警与核验','安全帽发起 SOS','alarms'],['调度通信','广播','dispatch'],['定位与轨迹','定位','location'],['现场资料','现场资料','materials'],['统计追溯','统计','statistics']]){
   await portal.getByRole('link',{name:label,exact:true}).click();
   await capture(portal,'portal-'+slug,expected);
   if(slug==='works'){
    await portal.locator('a[href*="#/work/"]').first().click();
    await capture(portal,'portal-work-detail','锅炉平台检修');
    await portal.goBack();
   }
   if(slug==='alarms'){
    await portal.getByText('安全帽发起 SOS',{exact:true}).first().click();
    await capture(portal,'portal-sos-event-detail','核验');
   }
  }
  await portal.goto('http://127.0.0.1:5191/#/sos');
  await capture(portal,'portal-sos-queue','求助');
  const admin=await browser.newPage({viewport:{width:1440,height:1000}});
  admin.on('pageerror',e=>errors.push({surface:'admin',error:e.message}));
  await admin.goto('http://127.0.0.1:5181/');
  await admin.getByPlaceholder('请输入管理账号').fill('admin');
  await admin.getByPlaceholder('请输入密码',{exact:true}).fill(process.env.DEVICE_READY_ADMIN_PASSWORD);
  await admin.getByRole('button',{name:'登录',exact:true}).click();
  await admin.waitForURL(/overview/);
  await capture(admin,'admin-home','管理工作台');
  for(const [label,expected,slug] of [['装备资产','RL-H001','devices'],['人员组织','陈建国','people'],['权限协作','wear_user','accounts'],['操作日志','accounts.create','audit']]){
   await admin.getByRole('link',{name:label,exact:true}).click();
   await capture(admin,'admin-'+slug,expected);
  }
  await admin.getByRole('button',{name:'退出登录',exact:true}).click();
  await admin.waitForURL(/login/);
  await capture(admin,'admin-logout','欢迎登录');
  assert.equal(errors.length,0,JSON.stringify(errors));
 }finally{ fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({steps,errors},null,2)); await browser.close(); }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
