const {chromium}=require('C:/Users/qiyue/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),crypto=require('crypto');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:900}});
 const errors=[],remote=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(/^https?:/.test(r.url())&&!r.url().startsWith('http://127.0.0.1:18766/'))remote.push(r.url());});
 page.on('response',r=>{if(r.status()>=400)errors.push('HTTP '+r.status()+' '+r.url());});
 const snapshots=[];
 async function shot(name){await page.waitForTimeout(350);await page.screenshot({path:path.join(__dirname,name+'.png')});snapshots.push({name,url:page.url()});}
 async function accessible(){if(await page.locator('flt-semantics-placeholder').count())await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());await page.waitForTimeout(200);}
 async function click(text){await accessible();const exact=page.getByText(text,{exact:true});const target=await exact.count()?exact:page.getByText(text);await target.last().evaluate(e=>e.click());await page.waitForTimeout(450);}
 async function point(x,y){const r=await page.locator('#app').boundingBox();await page.mouse.click(r.x+x*r.width/360,r.y+y*r.height/616);await page.waitForTimeout(250);}
 async function wheel(n){const r=await page.locator('#app').boundingBox();await page.mouse.move(r.x+r.width*.65,r.y+r.height*.65);await page.mouse.wheel(0,n);await page.waitForTimeout(350);}
 async function captureLong(name){for(const f of fs.readdirSync(__dirname)){if(f.startsWith(name+'-')&&f.endsWith('.png'))fs.unlinkSync(path.join(__dirname,f));}await wheel(-7000);await shot(name+'-顶部');let previous='';for(let i=0;i<8;i++){await wheel(530);const b=await page.locator('#phone').screenshot();const h=crypto.createHash('sha256').update(b).digest('hex');if(h===previous)break;fs.writeFileSync(path.join(__dirname,name+'-滑动'+(i+1)+'.png'),b);previous=h;}await shot(name+'-底部');}
 await page.goto('http://127.0.0.1:18766/?sync='+Date.now());
 await page.locator('#loading').waitFor({state:'detached',timeout:90000});
 await page.waitForTimeout(500);
 for(const field of [[150,220],[150,300],[85,383]]) {
   await point(...field);
   await page.waitForTimeout(200);await page.keyboard.type('demo');await page.waitForTimeout(200);
 }
 await shot('00-登录输入检查');await point(180,465);await shot('02-厂站选择');await accessible();console.log('SITES',await page.locator('body').innerText());await page.getByText(/演示厂站A/).last().evaluate(e=>e.click());await page.waitForTimeout(500);
 console.log('HOME',await page.locator('body').innerText());
 if(!process.argv.includes('--remaining')) {
 await captureLong('03-现场');await wheel(-7000);await click('查看作业');
 await captureLong('04-作业详情');
 console.log('TASK',await page.locator('body').innerText());
 await wheel(-7000);await point(18,20);await page.waitForTimeout(400);
 if(!page.url().includes('/workbench'))throw Error('Task back did not return to workbench');
 await point(315,588);await captureLong('05-我的');await wheel(-7000);await click('我的装备');
 await captureLong('06-我的装备');await wheel(-7000);await point(18,20);
 await click('设置');await shot('07-设置');await point(20,25);await click('帮助与反馈');await shot('08-帮助与反馈');await point(20,25);
 await point(135,588);await captureLong('09-通讯');
 }
 async function route(r){await page.evaluate(r=>{location.hash=r},r);await page.waitForTimeout(850);await wheel(-7000);}
 await route('/communications?deviceId=201');await captureLong('10-语音操作');
 await route('/communications?deviceId=201&action=video');await captureLong('11-视频操作');
 await route('/communications?deviceId=201&action=tts');await captureLong('12-语音播报');
 await route('/events');await captureLong('13-消息');await wheel(-7000);await click('筛选');await shot('14-消息筛选');await page.keyboard.press('Escape');
 await route('/events?eventId=401');await captureLong('15-异常核验');
 await route('/events?eventId=402');await captureLong('16-SOS协助');
 await route('/people/101');await captureLong('17-人员详情');
 await route('/devices/201');await captureLong('18-设备详情');
 await route('/tracks');await captureLong('20-轨迹回放');
 await wheel(-7000);await click('示例预览');await captureLong('21-轨迹示例');
 await route('/me');await page.setViewportSize({width:320,height:568});await shot('19-窄屏我的');
 const phone=await page.locator('#phone').boundingBox();const ratio=phone.width/phone.height;if(Math.abs(ratio-9/16)>.001)throw Error('Phone aspect ratio changed');
 if(errors.length)throw Error('Browser errors: '+errors.join('\n'));if(remote.length)throw Error('Unexpected external requests: '+remote.join('\n'));
 snapshots.push({mobile:{width:320,height:568,phone,aspectRatio:ratio}});
 fs.writeFileSync(path.join(__dirname,'browser-state.json'),JSON.stringify({verifiedAt:new Date().toISOString(),snapshots,errors,remote},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
