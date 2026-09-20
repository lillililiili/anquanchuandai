// Interactive local QA harness. Drives the real web UI while Android is operated
// separately. It never captures media or prints credentials. Only run locally.
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
const { chromium } = createRequire(import.meta.url)('playwright');
const base = process.env.CALL_LAB_URL || 'http://127.0.0.1:5188';
if (!['localhost','127.0.0.1'].includes(new URL(base).hostname)) throw Error('Local QA only');
const oldFixture = await readFile(new URL('alarms-browser.mjs',import.meta.url),'utf8');
const password = process.env.LAB_TEST_PASSWORD || oldFixture.match(/password = process.env.LAB_TEST_PASSWORD \|\| '([^']+)'/)[1];
const browser = await chromium.launch({channel:'chrome',headless:true});
const page = await browser.newPage({viewport:{width:1440,height:1100}});
page.on('pageerror',e=>console.log(JSON.stringify({pageError:e.message})));
await page.goto(base+'/business');
await page.locator('#username').fill(process.env.LAB_ADMIN || 'admin');
await page.locator('#password').fill(password);
await page.locator('#signIn').click();
await page.locator('#workspace').waitFor({state:'visible'});
await page.locator('[data-device="12"]').waitFor();
async function idle(){await page.waitForFunction(()=>!document.getElementById('refreshRoster').disabled);}
async function select(ids){
  await idle();await page.locator('#search').fill('');await page.locator('#deviceType').selectOption('');await page.locator('#taskFilter').selectOption('');
  for(const input of await page.locator('#devices .device-title input').all()) if(await input.isChecked()) await input.uncheck();
  for(const id of ids) await page.locator(`[data-device="${id}"] .device-title input`).check();
}
await select(['12','13']);await page.locator('#onlineSelected').click();await idle();
console.log(JSON.stringify({ready:true,devices:['12','13'],note:'Existing demo helmets, web-controlled simulated presence only'}));
await mkdir(new URL('../artifacts/',import.meta.url),{recursive:true});
for await (const line of createInterface({input:process.stdin,terminal:false})) {
  try {
    const [cmd,...args]=line.trim().split(/\s+/);
    if(cmd==='status') console.log(JSON.stringify({calls:await page.locator('#calls').innerText(),dispatchers:await page.locator('#dispatcher').innerText(),messages:await page.locator('#messages').innerText(),notice:await page.locator('#notice').innerText()}));
    else if(cmd==='incoming') {await select([args[0]||'12']);await page.locator(args.includes('sos')?'#sosCall':'#normalCall').click();await idle();console.log(JSON.stringify({incoming:await page.locator('#notice').innerText()}));}
    else if(cmd==='accept'||cmd==='reject'||cmd==='hangup') {await idle();await page.locator('#search').fill('');await page.locator('#deviceType').selectOption('');await page.locator('#taskFilter').selectOption('');const eligible=await page.locator('#calls [data-participant]').evaluateAll((rows,action)=>[...new Set(rows.filter(row=>action==='hangup'?!!row.querySelector('.badge.connected,.badge.ringing'):row.closest('[data-direction]')?.dataset.direction==='outgoing'&&!!row.querySelector('.badge.ringing')).map(row=>row.dataset.participant))],cmd);const ids=args[0]?eligible.filter(id=>id===args[0]):eligible;for(const id of ids){const key=page.locator(cmd==='accept'?`[data-helmet-call="${id}"]`:`[data-helmet-end="${id}"]`);if(await key.count()&&await key.isEnabled()){await key.click();await idle();}}console.log(JSON.stringify({action:cmd,note:cmd==='reject'?'模拟按帽端挂断键拒绝来电':undefined}));}
    else if(cmd==='ack') {const b=page.locator('#messages').getByRole('button',{name:'模拟收到播报'});while(await b.count()){await b.first().click();await idle();}console.log(JSON.stringify({ack:true}));}
    else if(cmd==='shot') {await idle();if(args.length>1)await page.locator('#search').fill(args.slice(1).join(' '));const name=(args[0]||'web').replace(/[\\/:*?"<>|]/g,'-');const path=fileURLToPath(new URL(`../artifacts/live-${encodeURIComponent(name)}.png`,import.meta.url));await page.screenshot({path,fullPage:true});console.log(JSON.stringify({screenshot:true,path}));}
    else if(cmd==='online'||cmd==='offline') {await select(args.length?args:['12','13']);await page.locator(cmd==='online'?'#onlineSelected':'#offlineSelected').click();await idle();console.log(JSON.stringify({presence:cmd}));}
    else if(cmd==='exit') {await page.locator('#signOut').click();await page.locator('#workspace').waitFor({state:'hidden'});break;}
    else console.log(JSON.stringify({commands:'status | incoming 12 [sos] | accept [device] | reject [device] | hangup [device] | ack | shot name [device SN / search text] | online/offline [ids] | exit'}));
  } catch(e){console.log(JSON.stringify({error:e.message}));}
}
await browser.close();
