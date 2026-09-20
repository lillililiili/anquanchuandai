const {chromium}=require('C:/Users/qiyue/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const root=path.resolve(__dirname,'..');
const data=JSON.parse(fs.readFileSync(path.join(root,'分析数据.json'),'utf8'));
function files(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(x=>x.isDirectory()?files(path.join(dir,x.name)):[path.join(dir,x.name)])}
const htmls=files(root).filter(x=>x.endsWith('.html'));
const links=[];
for(const file of htmls){
 const text=fs.readFileSync(file,'utf8');
 for(const m of text.matchAll(/(?:href|src)="([^"]+)"/g)){
  const rel=m[1].replace(/&amp;/g,'&');
  if(/^(https?:|data:|#)/.test(rel))continue;
  const target=path.resolve(path.dirname(file),decodeURIComponent(rel.split('#')[0]));
  if(!fs.existsSync(target))throw Error('Broken local link: '+path.relative(root,file)+' -> '+rel);
  links.push({from:path.relative(root,file),to:path.relative(root,target)});
 }
}
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const page=await browser.newPage({viewport:{width:1440,height:1060},deviceScaleFactor:1});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const go=async rel=>{await page.goto(pathToFileURL(path.join(root,rel)).href);await page.waitForFunction(()=>[...document.images].filter(i=>i.loading!=='lazy').every(i=>i.complete&&i.naturalWidth>0));};
 await go('index.html');
 if(await page.locator('.card').count()!==40)throw Error('Expected 40 cards');
 await page.screenshot({path:path.join(root,'证据/报告总览-桌面.png')});
 await page.locator('#group').selectOption('现场');
 if(await page.locator('.card:visible').count()!==13)throw Error('Module filter');
 await page.locator('#group').selectOption('');
 await page.locator('#search').fill('SOS');
 if(await page.locator('.card:visible').count()<1)throw Error('Search SOS');
 await page.locator('#search').fill('不存在的控件98765');
 if(!await page.locator('#noresults').isVisible())throw Error('No-results state');
 await page.locator('#search').fill('');
 const checks=[];let rows=0;
 for(const item of data.pages){
  await page.setViewportSize({width:1440,height:1060});
  await go('pages/'+item.id+'.html');
  const count=await page.locator('.features tbody tr').count();
  if(count!==item.rows.length)throw Error('Rows missing '+item.id);
  rows+=count;
  if(await page.locator('.longshot img').count()!==2)throw Error('Missing pair '+item.id);
  if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Desktop overflow '+item.id);
  const shot=await page.locator('.longshot').evaluateAll(els=>els.map(e=>{e.scrollTop=e.scrollHeight;return e.scrollTop+e.clientHeight>=e.scrollHeight-2}));
  if(shot.some(x=>!x))throw Error('Image bottom inaccessible '+item.id);
  await page.locator('.longshot').evaluateAll(els=>els.forEach(e=>e.scrollTop=0));
  if(['02','13','25'].includes(item.id))await page.screenshot({path:path.join(root,'证据/报告详情-'+item.id+'.png')});
  await page.setViewportSize({width:390,height:844});
  if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Mobile overflow '+item.id);
  checks.push({id:item.id,rows:count,images:true,desktop:true,mobile:true,bottomAccessible:true});
 }
 await go('pages/25.html');
 await page.locator('#row-search').fill('附件');
 if(!await page.locator('.features tbody tr:visible').count())throw Error('Row search');
 await page.locator('#row-search').fill('');
 await page.screenshot({path:path.join(root,'证据/报告详情-手机.png')});
 await go('index.html');
 if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Overview mobile overflow');
 await page.screenshot({path:path.join(root,'证据/报告总览-手机.png')});
 for(const file of htmls.filter(x=>path.dirname(x).endsWith('文档'))){
  await go(path.relative(root,file));
  if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Document mobile overflow '+file);
 }
 if(errors.length)throw Error(errors.join('\n'));
 fs.writeFileSync(path.join(root,'证据/网页验收.json'),JSON.stringify({verifiedAt:new Date().toISOString(),htmlFiles:htmls.length,localLinks:links.length,allLinksExist:true,referencePages:40,totalDetailRows:rows,search:true,moduleFilter:true,noResults:true,rowSearch:true,desktop:'1440x1060',mobile:'390x844',consoleErrors:errors,checks},null,2));
 await browser.close();console.log('PASS '+htmls.length+' HTML files, '+links.length+' links, 40 image pairs, '+rows+' rows, filters, search, desktop/mobile.');
})().catch(e=>{console.error(e);process.exit(1)});
