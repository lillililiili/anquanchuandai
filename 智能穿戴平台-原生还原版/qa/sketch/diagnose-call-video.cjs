const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {chromium} = require('C:/Users/19221/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root = path.resolve(__dirname, '../..');
const output = path.join(__dirname, 'call-video-diagnostics.json');
const result = {samples: [], network: [], failures: [], pageErrors: []};
(async () => {
  const server = spawn(process.execPath, [path.join(root, 'server.js'), '--port', '5211'], {windowsHide:true, stdio:['ignore','pipe','pipe']});
  let browser;
  try {
    await new Promise((resolve,reject) => {server.stdout.once('data',resolve);server.once('error',reject);});
    browser = await chromium.launch({headless:true, executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
    const context = await browser.newContext({viewport:{width:1920,height:1080}});
    await context.addInitScript(() => {
      sessionStorage.setItem('rolling-session','admin');
      window.mediaEvents = [];
      for (const name of ['loadstart','loadedmetadata','loadeddata','canplay','canplaythrough','playing','play','pause','waiting','stalled','suspend','error','ended']) {
        document.addEventListener(name, ev => {
          const v = ev.target;
          if (v instanceof HTMLMediaElement) window.mediaEvents.push({event:name, src:v.currentSrc||v.src, time:v.currentTime, readyState:v.readyState, networkState:v.networkState, error:v.error&&{code:v.error.code,message:v.error.message}, at:performance.now()});
        }, true);
      }
      const originalPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function (...args) {
        const value = originalPlay.apply(this,args);
        if (value && value.catch) value.catch(error => window.mediaEvents.push({event:'play-rejection',name:error.name,message:error.message}));
        return value;
      };
    });
    const p = await context.newPage();
    p.on('response', async r => {if(r.url().endsWith('.webm')) result.network.push({url:r.url(),status:r.status(),headers:r.headers()});});
    p.on('requestfailed', r=>result.failures.push({url:r.url(),failure:r.failure()}));
    p.on('pageerror', e=>result.pageErrors.push(e.message));
    await p.goto('http://127.0.0.1:5211/#/dispatch');
    await p.getByRole('heading',{name:'当前通话：未发起'}).waitFor();
    await p.getByRole('checkbox',{name:'全选',exact:true}).check();
    await p.getByRole('checkbox',{name:'全选',exact:true}).uncheck();
    await p.locator('[data-member="P2"]').check();
    await p.getByRole('button',{name:'单呼',exact:true}).click();
    for (const wait of [0,1000,4000,5000]) {
      if(wait) await p.waitForTimeout(wait);
      result.samples.push(await p.evaluate(() => ({at:performance.now(),route:R.route,call:R.db.state.calls[0], videos:[...document.querySelectorAll('video[data-call-video]')].map(v=>({src:v.currentSrc,readyState:v.readyState,networkState:v.networkState,paused:v.paused,currentTime:v.currentTime,duration:v.duration,muted:v.muted,autoplay:v.autoplay,error:v.error&&{code:v.error.code,message:v.error.message},width:v.videoWidth,height:v.videoHeight,rect:v.getBoundingClientRect().toJSON(),style:{display:getComputedStyle(v).display,visibility:getComputedStyle(v).visibility}})),events:window.mediaEvents})));
    }
    await p.screenshot({path:path.join(__dirname,'call-video-diagnostic.png'),fullPage:true});
    const legacy=fs.readFileSync(path.join(root,'scripts/check-call-video.js'),'utf8').replace(/http:\/\/127\.0\.0\.1:\d+/g,'http://127.0.0.1:5211').replace(/output\/playwright\//g,__dirname.replace(/\\/g,'/')+'/');
    try {result.legacy=await (0,eval)('('+legacy+'\n)')(p);} catch(error) {result.legacyError=error.stack;}
    console.log(JSON.stringify({network:result.network,failures:result.failures,samples:result.samples.map(s=>({at:s.at,videos:s.videos,events:s.events.slice(-8)})),legacy:result.legacy,legacyError:result.legacyError},null,2));
  } finally {
    fs.writeFileSync(output,JSON.stringify(result,null,2));
    if(browser) await browser.close();
    server.kill();
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
