const {chromium}=require('C:/Users/qiyue/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:900}});
 await page.goto('http://127.0.0.1:18766/?sync='+Date.now());
 await page.locator('#loading').waitFor({state:'detached',timeout:90000});
 await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 await page.waitForTimeout(700);
 console.log(await page.locator('body').innerText());
 console.log(await page.locator('input').evaluateAll(a=>a.map(e=>({type:e.type,aria:e.getAttribute('aria-label')}))));
 await page.screenshot({path:path.join(__dirname,'01-登录.png')});
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
