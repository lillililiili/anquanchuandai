from pathlib import Path
from html import escape as h
from datetime import datetime
import json,re,shutil,hashlib
from PIL import Image,ImageDraw,ImageFont
from final_data import P,COMMON

OUT=Path(__file__).resolve().parents[1]
ROOT=OUT.parents[1]
REF=OUT.parent/'安卓全页面设计-浅色多彩版'
CUR=OUT.parent/'安卓全页面设计-当前预览版'
APP=ROOT/'android代码/melhat_android-main'
refs=json.loads((REF/'manifest.json').read_text('utf-8-sig'))
current=json.loads((CUR/'manifest.json').read_text('utf-8-sig'))
cm={x['id']:x for x in current['items']}
stamp=datetime.now().astimezone().isoformat(timespec='seconds')
assert [x['id'] for x in P]==[f'{n:02}' for n in range(1,41)]
for folder in ['pages','页面图片/设计','页面图片/当前','文档','证据/后端控制器']:
 (OUT/folder).mkdir(parents=True,exist_ok=True)

def stitch(base,sid):
 meta=json.loads((base/'captures'/sid/'capture.json').read_text('utf-8'))
 frames=meta['frames']; im=Image.open(base/'captures'/sid/frames[0]['file']).convert('RGB')
 ratio=meta['pixelRatio']; w,hh=im.size
 bottom=min(hh,round((frames[0]['top']+frames[0]['height'])*ratio))
 strips=[im.crop((0,0,w,bottom))]
 for prev,frame in zip(frames,frames[1:]):
  im=Image.open(base/'captures'/sid/frame['file']).convert('RGB')
  delta=round((frame['offset']-prev['offset'])*ratio)
  strips.append(im.crop((0,bottom-delta,w,bottom)))
 if bottom<hh: strips.append(im.crop((0,bottom,w,hh)))
 dest=Image.new('RGB',(w,sum(x.height for x in strips)),'white'); y=0
 for im in strips: dest.paste(im,(0,y)); y+=im.height
 dest.save(OUT/f'页面图片/当前/{sid}.jpg',quality=93)
 return meta

newmeta={}
for x in refs:
 sid=x['id']; shutil.copy2(next((REF/'页面图片').glob(sid+'-*.png')),OUT/f'页面图片/设计/{sid}.png')
for x in current['items']:
 shutil.copy2(CUR/x['image'],OUT/f"页面图片/当前/{x['id']}.jpg")
for sid in ['01','02','13','16']:
 base=OUT/'证据'/('登录更新截图' if sid in ['01','02'] else '轨迹更新截图')
 newmeta[sid]=stitch(base,sid)
cm['02'].update(kind='独立页面（最新更新）',entry='登录 → 忘记密码 / 申请重置',source='lib/wear/password_reset_page.dart',note='最新为独立页，本地验证码与校验已实现，申请服务尚未接入。')
cm['13'].update(kind='页面',issue=False,note='最新轨迹支持示例预览、播放、拖动与倍速；旧空轨迹异常已不适用，真实定位待联调。')
cm['16'].update(kind='人员选择弹层',issue=False,note='最新轨迹页的人员选择弹层；按姓名查询后点击选择。')

# 保存收尾时完整源码快照；初次哈希结果保留，以便追溯并行修改。
hashes=[]
old=json.loads((CUR/'源码校验.json').read_text('utf-8-sig'))
for file in (APP/'lib/wear').rglob('*.dart'):
 rel=file.relative_to(APP).as_posix(); value=hashlib.sha256(file.read_bytes()).hexdigest()
 hashes.append({'path':rel,'sha256':value,'capture_sha256':old.get(rel),'match':old.get(rel)==value})
 target=OUT/'证据/源码摘录'/file.relative_to(APP/'lib/wear').with_suffix('.txt'); target.parent.mkdir(parents=True,exist_ok=True)
 target.write_text('\n'.join(f'{i}: {v}' for i,v in enumerate(file.read_text('utf-8-sig').splitlines(),1)),'utf-8')
(OUT/'证据/交付源码快照.json').write_text(json.dumps({'capturedAt':stamp,'files':hashes},ensure_ascii=False,indent=2),'utf-8')
backend=ROOT/'后端代码/melhat_server-dev/ruoyi-admin/src/main/java/com/ruoyi/wear/web/v1'
for name in ['WearWorkTaskController','WearPeopleController','WearDeviceController','WearFenceController','WearCallController','WearCommandController','WearEventController','WearAssignmentController','WearIdentityController','WearDutyController','WearFileController']:
 file=backend/(name+'.java')
 (OUT/'证据/后端控制器'/(name+'.txt')).write_text('\n'.join(f'{i}: {v}' for i,v in enumerate(file.read_text('utf-8-sig').splitlines(),1)),'utf-8')

note=OUT/'00-阅读说明与结论.md'; s=note.read_text('utf-8')
s=s.replace('找回密码仅弹提示；','最新找回页已如实说明尚未接入申请服务；')
s=s.replace('对13轨迹回放和16人员选择补采了当前原组件截图，','对01登录、02找回权限、13轨迹回放和16人员选择补采了当前原组件截图，')
s=s.replace('两项补采也通过。','四项补采也通过；新版找回页既有行为测试2项通过。')
if '收尾复核更新' not in s:
 s+='\n## 收尾复核更新\n\n分析期间工作区继续变化：`auth_pages.dart`接入新增`password_reset_page.dart`，02现为独立页面，账号、验证码、刷新和提醒卡已具备；旧新密码字段及“申请已记录”误导已移除。报告已更新01/02截图和结论，真实申请接口仍待接入。首次34/37哈希一致仅指首次读取时点，交付时源码以`证据/交付源码快照.json`为准。\n'
note.write_text(s,'utf-8')
road=OUT/'03-后续开发方向与验收清单.md'; s=road.read_text('utf-8')
s=s.replace('当前按钮无接口；先纠正“申请已记录”文案，不收集无去向的新密码','最新页面已修正文案并移除新密码字段，明确未发送；现有本地验证码仍需服务端申请契约')
s=s.replace('首轮完成U01—U04并同步纠正B01误导反馈，再完成U05—U08；','首轮完成U01—U04，再完成U05—U08；B01的误导反馈已在最新代码中修正，后续补真实申请服务。')
road.write_text(s,'utf-8')

CSS='''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f4f7fc;color:#172a42;font-family:"Microsoft YaHei",system-ui,sans-serif;line-height:1.75}a{color:#006bc5;text-decoration:none}a:hover{text-decoration:underline}header{background:#112e4d;color:white;padding:44px max(24px,calc((100vw - 1260px)/2)) 38px}header a{color:#b9ddff}header .eyebrow{letter-spacing:3px;font-size:12px;color:#8ec8ff}h1{font-size:32px;line-height:1.35;margin:12px 0 18px}h2{font-size:23px;margin:32px 0 16px}h3{font-size:18px}p{margin:10px 0}main{max-width:1308px;margin:auto;padding:24px}.muted{color:#60758c}.badge{display:inline-block;background:#e7f2ff;color:#116aa9;border-radius:7px;padding:3px 9px;font-size:12px;margin:2px}.stats{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0 0}.stats span{padding:10px 18px;border:1px solid #47617c;border-radius:10px}.stats b{font-size:26px;margin-right:8px}.panel{padding:22px;background:white;border:1px solid #dce5ef;border-radius:15px;margin:18px 0}.notice{border-left:4px solid #edaa35;background:#fff8e9;padding:15px 20px;border-radius:8px}.nav{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0}.controls{display:flex;gap:12px;flex-wrap:wrap;position:sticky;top:0;background:#f4f7cf00;backdrop-filter:blur(16px);z-index:2;padding:12px 0}input,select{font:inherit;background:white;border:1px solid #b9cbdc;padding:11px 14px;border-radius:9px;max-width:100%}input{flex:1;min-width:220px}select{width:185px}.cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}.card{display:block;background:white;border:1px solid #dce5ef;border-radius:14px;overflow:hidden;color:inherit}.card:hover{border-color:#087ed4;text-decoration:none;box-shadow:0 7px 25px #18345216}.thumbs{display:grid;grid-template-columns:1fr 1fr;gap:4px;background:#e1ebf4;height:225px;overflow:hidden}.thumbs img{width:100%;height:auto;display:block}.cardbody{padding:16px}.card h3{margin:3px 0}.card .id{font-family:monospace;font-size:14px;color:#2587cc}.card p{font-size:13px;color:#536b82}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;align-items:start}.imagebox{background:white;border:1px solid #dce5ef;border-radius:12px;overflow:hidden}.imagebar{padding:12px 16px;border-bottom:1px solid #dce5ef;font-weight:bold;display:flex;justify-content:space-between;gap:10px}.longshot{max-height:770px;overflow:auto;background:#e9f0f7;overscroll-behavior:contain}.longshot img{display:block;width:100%;max-width:440px;margin:auto}.summary{display:grid;grid-template-columns:1fr 1fr;gap:18px}.same{border-top:4px solid #29a18a}.diff{border-top:4px solid #e6a240}.tablewrap{overflow:auto;border:1px solid #dce5ef;border-radius:10px;background:white;margin:14px 0}table{border-collapse:collapse;width:100%;font-size:14px}th{background:#eaf2fa;text-align:left;color:#244462}th,td{padding:13px 14px;border-bottom:1px solid #e1e8f0;vertical-align:top;min-width:110px}td{overflow-wrap:anywhere}th:first-child{min-width:76px}.features th:nth-child(4),.features th:nth-child(5){min-width:230px}.features th:nth-child(3){min-width:200px}tbody tr:last-child td{border-bottom:0}tbody tr:hover{background:#f7fbff}.source{font:12px/1.7 Consolas,monospace;white-space:pre-wrap;overflow-wrap:anywhere}.sources{display:flex;gap:12px;flex-wrap:wrap}.pager{display:flex;justify-content:space-between;margin:30px 0;gap:15px}.article{max-width:1180px}code{background:#eef2f7;padding:2px 5px;overflow-wrap:anywhere}.article li{margin:8px 0}.hidden,[hidden]{display:none!important}footer{font-size:12px;padding:28px;color:#60758c;text-align:center}.count{font-size:13px;color:#536b82}.extra img{max-width:270px;width:100%;display:block}.article img{max-width:100%}@media(max-width:850px){.cards{grid-template-columns:repeat(2,minmax(0,1fr))}.pair{gap:12px}.summary{grid-template-columns:1fr}.thumbs{height:200px}}@media(max-width:560px){header{padding:28px 18px}h1{font-size:25px}main{padding:16px}.cards{grid-template-columns:1fr}.thumbs{height:280px}.pair{grid-template-columns:1fr}.longshot{max-height:620px}.panel{padding:16px}.controls{position:static}select{width:100%}.stats span{padding:7px 10px}.stats b{font-size:22px}.imagebar{font-size:14px}.nav{gap:10px}.features{min-width:1040px}}@media print{header{background:white;color:black;padding:12px}header a,.controls,footer,.pager{display:none}.longshot{max-height:none;overflow:visible}.panel{break-inside:avoid}.pair{grid-template-columns:1fr 1fr}.tablewrap{overflow:visible}table{font-size:10px}th,td{min-width:0!important;padding:6px}.features{min-width:0}.card{break-inside:avoid}.cards{grid-template-columns:1fr 1fr}}'''
(OUT/'style.css').write_text(CSS,'utf-8')

def table(headers,rows,klass=''):
 return f'<div class="tablewrap"><table class="{klass}"><thead><tr>'+''.join('<th>'+h(c)+'</th>' for c in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+h(str(c))+'</td>' for c in row)+'</tr>' for row in rows)+'</tbody></table></div>'
def mdtable(headers,rows):
 return '|'+ '|'.join(headers)+'|\n|'+'|'.join('---' for _ in headers)+'|\n'+''.join('|'+'|'.join(str(c).replace('|','／').replace('\n','<br>') for c in row)+'|\n' for row in rows)
def shell(title,body,head='',depth=0):
 pre='../'*depth
 return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+h(title)+' · 安卓对照报告</title><link rel="stylesheet" href="'+pre+'style.css"></head><body><header><div class="eyebrow">ANDROID / DESIGN × IMPLEMENTATION</div><h1>'+h(title)+'</h1>'+head+'</header>'+body+'<footer>来源：当前工作区代码与原组件示例截图 · '+h(stamp)+' · 功能存在不等于真实业务验收完成</footer></body></html>'
def inline(s):
 s=h(s)
 s=re.sub(r'!\[([^\]]*)\]\(([^)]+)\)',lambda m:'<img alt="'+m[1]+'" loading="lazy" src="../'+m[2]+'">',s)
 s=re.sub(r'`([^`]+)`',r'<code>\1</code>',s)
 s=re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',s)
 def link(m):
  target=m[2]
  if target.endswith('.md'): target=Path(target).stem+'.html'
  elif target=='index.html': target='../index.html'
  elif target.startswith('pages/'): target='../'+target
  return '<a href="'+target+'">'+m[1]+'</a>'
 return re.sub(r'\[([^\]]+)\]\(([^)]+)\)',link,s)
def markdown(s):
 out=[]; lines=s.splitlines(); i=0; inlist=False
 while i<len(lines):
  line=lines[i]
  if line.startswith('|'):
   if inlist: out.append('</ul>'); inlist=False
   block=[]
   while i<len(lines) and lines[i].startswith('|'): block.append(lines[i]); i+=1
   rows=[[c.strip() for c in x.strip('|').split('|')] for x in block]
   out.append('<div class="tablewrap"><table><thead><tr>'+''.join('<th>'+inline(c)+'</th>' for c in rows[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+inline(c)+'</td>' for c in r)+'</tr>' for r in rows[2:])+'</tbody></table></div>'); continue
  if line.startswith('- '):
   if not inlist: out.append('<ul>'); inlist=True
   out.append('<li>'+inline(line[2:])+'</li>')
  else:
   if inlist: out.append('</ul>'); inlist=False
   m=re.match(r'^(#{1,6}) (.*)',line)
   if m: out.append(f'<h{len(m[1])}>'+inline(m[2])+f'</h{len(m[1])}>')
   elif line.strip(): out.append('<p>'+inline(line)+'</p>')
  i+=1
 if inlist: out.append('</ul>')
 return ''.join(out)

full=['# 40张逐页详细分析\n\n先UI后功能。每项均列设计、当前UI、功能结论、下一步；独立页可浏览并排完整长图。当前图为原组件样例渲染，非真机业务结果。\n']
flat=['# 逐项功能对照总表\n\n共40张参考图，'+str(sum(len(x['rows']) for x in P))+'条逐页项，另列'+str(len(COMMON))+'条公共项。状态文字包含实现边界，不使用未经实测的完成百分比。\n\n## 公共UI和交互\n\n'+mdtable(['部位','设计要求','当前UI','功能结论','下一步'],COMMON)]
cards=[]; records=[]
for ref,p in zip(refs,P):
 sid=p['id']; cur=cm[sid]; group='账号' if int(sid)<=3 else '现场' if int(sid)<=16 else '通讯' if int(sid)<=21 else '消息' if int(sid)<=29 else '我的' if int(sid)<=38 else '通用'
 rows=[[f"{sid}-{i:02}"]+r for i,r in enumerate(p['rows'],1)]
 title=sid+' · '+ref['title']; pre='../'
 sources=[]
 for name in re.findall(r'[\w/]+\.dart',p['evidence']):
  matches=list((OUT/'证据/源码摘录').rglob(Path(name).name.replace('.dart','.txt')))
  for target in matches:
   sources.append('<a href="../'+target.relative_to(OUT).as_posix()+'">'+h(target.relative_to(OUT/'证据/源码摘录').as_posix())+'</a>')
 parents=[cur.get('parent')]+cur.get('otherParents',[])
 relation=' · '.join(f'<a href="{pid}.html">返回关联图 {pid}</a>' for pid in dict.fromkeys(parents) if pid and int(pid)<=40)
 shotnote='使用既有组件截图；业务数据为示例。'
 if sid in ['01','02']: shotnote='本报告补采最新登录/找回组件，02已改为独立页，申请服务未接入。'
 if sid in ['13','16']: shotnote='本报告补采最新轨迹组件；自绘地图方块字为测试字体限制，未据此判定真机缺陷。'
 body='<main><nav class="nav"><a href="../index.html">← 全部40图</a><a href="../文档/03-后续开发方向与验收清单.html">开发方向</a>'+relation+'</nav>'
 body+='<div class="notice">'+h(p['conclusion'])+'</div><div class="summary"><section class="panel same"><h3>相同 · 已有基础</h3><p>'+h(p['same'])+'</p></section><section class="panel diff"><h3>不同 · UI与场景</h3><p>'+h(p['diff'])+'</p></section></div>'
 body+='<h2>01 / 先看 UI</h2><p class="muted">两图显示宽度统一；设计390px与当前360逻辑宽的画布不同。各图可独立滚动到底，点击“原图”放大。</p><div class="pair">'
 for label,path in [('参考设计',f'页面图片/设计/{sid}.png'),('当前实现',f'页面图片/当前/{sid}.jpg')]:
  body+='<section class="imagebox"><div class="imagebar"><span>'+label+'</span><a target="_blank" href="../'+path+'">查看原图 ↗</a></div><div class="longshot"><img src="../'+path+'" alt="'+h(title+' '+label)+'"></div></section>'
 body+='</div><p class="muted">'+h(shotnote)+'</p><h2>02 / 逐项核对功能与小交互</h2><p>入口：'+h(cur['entry'])+' · 当前形态：'+h(cur['kind'])+'</p>'
 body+='<input id="row-search" type="search" aria-label="搜索本页细项" placeholder="搜索本页细项，如：返回、搜索、接口">'+table(['编号','部位','设计要求','当前UI','功能结论','下一步'],rows,'features')
 body+='<section class="panel"><h3>源码依据</h3><p class="source">'+h(p['evidence'])+'</p><div class="sources">'+''.join(dict.fromkeys(sources))+'</div><p class="muted">链接为随报告保存的带行号快照；行号对应分析时源码。以函数和字段共同定位，不能将请求代码视为执行成功证据。</p></section>'
 if sid in ['38','40']:
  extra='42' if sid=='38' else '41'
  body+='<section class="panel extra"><h3>额外覆盖：'+extra+' '+h(cm[extra]['title'])+'</h3><p>'+h(cm[extra]['entry'])+'</p><a href="../页面图片/当前/'+extra+'.jpg"><img src="../页面图片/当前/'+extra+'.jpg" alt="补充状态"></a></section>'
 body+='<nav class="pager">'+(f'<a href="{int(sid)-1:02}.html">← 上一图</a>' if sid!='01' else '<span></span>')+(f'<a href="{int(sid)+1:02}.html">下一图 →</a>' if sid!='40' else '<a href="../index.html">回到总览</a>')+'</nav></main>'
 body+='''<script>document.querySelector('#row-search').addEventListener('input',e=>{const q=e.target.value.toLowerCase();document.querySelectorAll('.features tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q))})</script>'''
 (OUT/f'pages/{sid}.html').write_text(shell(title,body,'<p>'+h(group+' / '+cur['kind'])+' · '+str(len(rows))+'项细节</p>',1),'utf-8')
 section=f"\n## {title}\n\n- 当前入口：{cur['entry']}。当前形态：{cur['kind']}。\n- 相同：{p['same']}\n- 不同：{p['diff']}\n- 结论：{p['conclusion']}\n\n[打开独立双图分析](pages/{sid}.html)\n\n|设计|当前实现|\n|---|---|\n|![设计](页面图片/设计/{sid}.png)|![当前](页面图片/当前/{sid}.jpg)|\n\n{shotnote}\n\n"
 section+=mdtable(['编号','部位','设计要求','当前UI','功能结论','下一步'],rows)+f"\n源码依据：`{p['evidence']}`。\n"
 full.append(section)
 flat.append('\n## '+title+'\n\n'+mdtable(['编号','部位','设计要求','当前UI','功能结论','下一步'],rows))
 search=' '.join([title,group,p['same'],p['diff'],p['conclusion']]+[' '.join(r) for r in rows])
 cards.append('<a class="card" data-group="'+group+'" data-search="'+h(search)+'" href="pages/'+sid+'.html"><div class="thumbs"><img loading="lazy" src="页面图片/设计/'+sid+'.png" alt="参考 '+sid+'"><img loading="lazy" src="页面图片/当前/'+sid+'.jpg" alt="当前 '+sid+'"></div><div class="cardbody"><span class="id">'+sid+' / '+group+'</span><h3>'+h(ref['title'])+'</h3><span class="badge">'+h(cur['kind'])+'</span><span class="badge">'+str(len(rows))+'项对比</span><p>'+h(p['conclusion'])+'</p></div></a>')
 records.append(dict(**p,title=ref['title'],group=group,current=cur,frames=newmeta.get(sid,cur).get('frames')))
(OUT/'01-40张逐页详细分析.md').write_text('\n'.join(full),'utf-8')
(OUT/'02-逐项功能对照总表.md').write_text('\n'.join(flat),'utf-8')
(OUT/'分析数据.json').write_text(json.dumps({'generatedAt':stamp,'common':COMMON,'pages':records},ensure_ascii=False,indent=2),'utf-8')

coverage={'generatedAt':stamp,'referencePages':len(P),'currentImages':42,'pageItems':sum(len(x['rows']) for x in P),'commonItems':len(COMMON),'freshCaptures':list(newmeta),'tracksExistingTests':3,'resetExistingTests':2,'captureTests':4,'scope':'代码核对与原组件样例渲染；未部署、未真实呼叫或播报','pages':[]}
for p in records:
 frames=p['frames']; last=frames[-1]
 assert abs(last['offset']-last['max'])<1,p['id']
 coverage['pages'].append({'id':p['id'],'items':len(p['rows']),'frames':len(frames),'bottomReached':True,'designImage':True,'currentImage':True})
(OUT/'证据/覆盖校验.json').write_text(json.dumps(coverage,ensure_ascii=False,indent=2),'utf-8')
proof=f'''# 证据与覆盖校验

交付生成时点：{stamp}。代码还可能继续变化，后续修订应重新比较哈希，不能将报告当实时看板。

## 覆盖结果

- 参考manifest的01—40连续编号全部存在，40份HTML文字已提取、40张参考图已查看；每张都有独立图文页。
- 当前图共42张：40个对应场景，加41加载、42切换账号；附加场景在40/38分析页展示。
- 逐页细项{coverage['pageItems']}条，公共细项{len(COMMON)}条，合计{coverage['pageItems']+len(COMMON)}条。不是完成率。
- 每项均有“设计要求、当前UI、功能结论、下一步”；每页均有“相同、不同、结论”和源码依据。
- 所有原组件采集场景最后一帧均到达滚动底部。页面长图不能替代弹层键盘态与全部业务分支的真机验收。
- 首次读取预览哈希34/37一致；随后发现登录/找回更新，已补采01/02并刷新源码快照。13/16也使用最新补采。
- 实际路由16条及Navigator子页面已列清；旧版19个路由定义和启动跳转另列，不算当前生产能力。

## 可追溯文件

|文件/目录|用途|
|---|---|
|证据/参考稿逐页文本.json、txt|全部参考HTML文字和链接|
|证据/客户方案提取.txt|客户DOCX正文文字，保留业务边界依据|
|证据/截图源码一致性.json|首次读取时的37个文件哈希对照|
|证据/交付源码快照.json|收尾时wear源码哈希及生成时间|
|证据/源码摘录/|当前wear源码带行号快照|
|证据/后端控制器/|任务、人员、设备、围栏、通话、命令、事件、装备分配、身份、值班、文件接口快照|
|证据/轨迹更新截图/、登录更新截图/|补采原始帧与滚动元数据|
|证据/轨迹行为测试.txt|既有轨迹3项行为测试输出|
|证据/找回权限行为测试.txt|既有找回页2项行为测试输出|
|证据/轨迹截图日志.txt、登录截图日志.txt|4个补采场景执行输出|
|证据/覆盖校验.json|40图编号、每图项数、帧数和底部到达记录|
|证据/网页验收.json|离线网页链接、图片、搜索、手机宽度验收，生成后由浏览器脚本写入|
|分析数据.json|结构化逐项分析，便于后续继续跟踪|
|tools/|提取、补采、报告生成与校验脚本，不修改业务实现|

## 已做和未做的验证

轨迹既有测试覆盖预览播放/拖动（1.0与1.5文字倍率）以及稳定人员ID/日期查询和空结果；找回既有测试覆盖空账号、错验证码、刷新、键盘、未发送说明和返回（1.0与1.5倍率）。本次没有新增业务测试，也未改生产代码。

UI证据来自Flutter测试渲染，示例接口数据由PreviewAdapter提供。不是雷电系统截图，不是线上查询成功证据；没有真实硬件端群呼、TTS听到、附件上传、SOS组、通知锁屏或厂站网络验收记录。地图自绘中文的采集字体限制已标注，不作为真实乱码缺陷。

生产工作区有用户既有未提交改动，本报告未回滚、恢复或提交它们。参考图片日期、姓名、示例数量与当前样例不同，单纯数值差异不统计为缺失功能。
'''
(OUT/'05-证据与覆盖校验.md').write_text(proof,'utf-8')

docs=['00-阅读说明与结论','02-逐项功能对照总表','03-后续开发方向与验收清单','04-全部页面与附加场景清单','05-证据与覆盖校验']
for name in docs:
 text=(OUT/(name+'.md')).read_text('utf-8')
 (OUT/'文档'/(name+'.html')).write_text(shell(name[3:],'<main class="article"><nav class="nav"><a href="../index.html">← 回到图文总览</a><a href="../'+name+'.md">Markdown原稿</a></nav>'+markdown(text)+'</main>',depth=1),'utf-8')
name='01-40张逐页详细分析'
(OUT/'文档'/(name+'.html')).write_text(shell('40张逐页详细分析目录','<main class="article"><nav class="nav"><a href="../index.html">← 图文总览</a><a href="../'+name+'.md">完整Markdown</a></nav><p>逐页分析含并排原图、完整细项与源码链接；点击下方编号进入。</p>'+''.join('<p><a href="../pages/'+p['id']+'.html">'+h(p['id']+' '+p['title'])+'</a> · '+str(len(p['rows']))+'项</p>' for p in records)+'</main>',depth=1),'utf-8')
# 总览是首选阅读入口，不依赖服务器或外部资源。
body='<main><div class="notice"><strong>判断：</strong>40张设计图都有对应场景，但不等于全部完成。优先统一UI，再逐页验证功能；群呼、帽发起、SOS协助组和真实申请仍有闭环缺口。</div><nav class="nav">'+''.join('<a href="文档/'+name+'.html">'+h(name[3:])+'</a>' for name in docs)+'<a href="01-40张逐页详细分析.md">完整Markdown</a></nav>'
body+='<section class="panel"><h3>怎么读</h3><p>每张卡左侧为设计，右侧为当前。进入后先看完整长图、相同与不同，再逐项读 UI、功能结论与下一步。姓名和数量的示例差异不算缺功能；“已有代码”不代表真实业务验收通过。</p><p class="muted">最新补采：01登录、02找回权限、13轨迹、16人员选择。02已修正旧误导提示，13已有播放和倍速，报告不再将旧问题重复列为待办。</p></section>'
body+='<div class="controls"><input id="search" type="search" aria-label="搜索全部对照项" placeholder="搜索页面、控件或差异，如：SOS、底栏、验证码"><select id="group" aria-label="按模块筛选"><option value="">全部模块</option>'+''.join('<option>'+x+'</option>' for x in ['账号','现场','通讯','消息','我的','通用'])+'</select></div><p id="count" class="count">显示40 / 40张参考图</p><div class="cards">'+''.join(cards)+'</div><p id="noresults" hidden>没有匹配项，请清空搜索或切换模块。</p></main>'
body+='''<script>const cards=[...document.querySelectorAll('.card')];function filter(){let q=document.querySelector('#search').value.trim().toLowerCase(),g=document.querySelector('#group').value,n=0;cards.forEach(c=>{c.hidden=!(c.dataset.search.toLowerCase().includes(q)&&(!g||c.dataset.group===g));if(!c.hidden)n++});document.querySelector('#count').textContent=`显示${n} / 40张参考图`;document.querySelector('#noresults').hidden=!!n}document.querySelector('#search').addEventListener('input',filter);document.querySelector('#group').addEventListener('change',filter)</script>'''
head='<p>浅色多彩版 × 当前 Android WearApp<br>逐页 UI、功能、小交互与后续开发方向</p><div class="stats"><span><b>40</b>张参考图</span><span><b>'+str(coverage['pageItems'])+'</b>条逐页对照</span><span><b>9</b>条公共项</span><span><b>42</b>个当前场景图</span></div>'
(OUT/'index.html').write_text(shell('安卓全页面 · 设计与实现对照',body,head),'utf-8')

# 将早期检查用拼图替换为交付采用的新图，防止证据中并列出现过期当前图。
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
for start in range(1,41,2):
 cols=[]
 for n in [start,start+1]:
  for label,folder,ext in [('设计','设计','png'),('当前','当前','jpg')]:
   im=Image.open(OUT/f'页面图片/{folder}/{n:02}.{ext}').convert('RGB'); im=im.resize((390,round(im.height*390/im.width)))
   col=Image.new('RGB',(410,im.height+48),'#e0e7ef'); ImageDraw.Draw(col).text((10,10),f'{n:02} {label}',font=font,fill='black');col.paste(im,(10,45));cols.append(col)
 sheet=Image.new('RGB',(1640,max(x.height for x in cols)),'#e0e7ef')
 for i,col in enumerate(cols):sheet.paste(col,(i*410,0))
 sheet.save(OUT/f'证据/对照{start:02}-{start+1:02}.jpg',quality=90)
print(json.dumps({k:v for k,v in coverage.items() if k!='pages'},ensure_ascii=False))
