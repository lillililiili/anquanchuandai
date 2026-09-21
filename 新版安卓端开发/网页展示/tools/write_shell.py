from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'展示源码'
data=json.loads((SRC/'assets/preview/snapshot.json').read_text('utf-8'))
core=data['identity']['personId'];dev=next(d['id'] for d in data['devices'] if d['sn']=='RL-H001')
task=next(t['id'] for t in data['tasks'] if t['siteId']=='1' and core in [m['personId'] for m in t['members']])
event=next(e['id'] for e in data['events'] if e['siteId']=='1' and e['type']!='sos');sos=next(e['id'] for e in data['events'] if e['siteId']=='1' and e['type']=='sos')
fence=next(f['id'] for f in data['fences'] if f['siteId']=='1')
groups=[('现场','/workbench',[('作业列表','/tasks'),('作业详情',f'/tasks/{task}'),('人员列表','/people'),('人员详情',f'/people/{core}'),('设备列表','/devices'),('设备详情',f'/devices/{dev}'),('人员轨迹',f'/tracks?personId={core}'),('电子围栏','/fences'),('围栏详情',f'/fences/{fence}'),('SOS 列表','/sos-events')]),('通讯','/communications',[('联系人与筛选','/communications'),('批量播报','/communications?action=tts')]),('消息','/events',[('事件详情',f'/events?eventId={event}'),('SOS 详情',f'/events?eventId={sos}')]),('我的','/me',[('设置','/settings'),('交接记录','/handovers'),('切换厂站','/sites')])]
nav=''.join('<details '+('open' if i==0 else '')+'><summary><a href="#'+route+'">'+title+'</a></summary><div>'+''.join('<a href="#'+u+'">'+label+'</a>' for label,u in children)+'</div></details>' for i,(title,route,children) in enumerate(groups))
p=SRC/'web/index.html';html=p.read_text('utf-8')
aside='<aside class="guide"><span class="meta">CURRENT ANDROID · 2026.09.21</span><h1>安卓页面展示</h1><p>手机内为当前安卓样式。<br>滑动查看下方内容，点击按钮进入子页面。</p><nav>'+nav+'</nav><p><a class="reset" href="?login=1#/login">查看登录页</a> <a class="reset" href="?reset=1#/workbench">重置展示</a></p><footer>联系人、作业和事件来自本地数据快照。所有操作仅在本页演示，刷新后恢复。</footer></aside>'
html=re.sub(r'<aside class="guide">.*?</aside>',lambda _:aside,html,flags=re.S)
css='''.guide{position:fixed;left:24px;top:24px;bottom:24px;width:230px;font-size:13px;line-height:1.7;overflow:auto;scrollbar-width:thin}.guide h1{font-size:20px;margin:0 0 4px}.meta{font-size:11px;letter-spacing:1px;color:#72889c}.guide a{color:#305979;text-decoration:none}.guide details{border-top:1px solid #d8e4ee;padding:8px 0}.guide summary{cursor:pointer;font-weight:600}.guide details div{border-left:1px solid #bfcfdd;margin:6px 0 0 7px;padding-left:15px;display:grid;gap:3px}.guide details div a{padding:3px 6px;border-radius:4px}.guide a:hover,.guide a.active{color:#176df2;background:#dceafd}.guide .reset{display:inline-block;padding:6px 9px;border:1px solid #c7d7e5;border-radius:7px;background:#f8fbfd}footer{font-size:11px;color:#708496;margin-top:14px}@media(max-width:1050px){.guide{display:none}}'''
html=html.replace('</style>',css+'</style>').replace('<title>ROLLING · 安卓页面演示</title>','<title>安卓当前页面 · 静态展示</title>')
html=html.replace('<meta charset="utf-8">','<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'self\' data: blob:; connect-src \'self\'; img-src \'self\' data: blob:; style-src \'self\' \'unsafe-inline\'; script-src \'self\' \'unsafe-inline\' \'unsafe-eval\' blob:;">')
p.write_text(html,'utf-8')
(ROOT/'同步验收/20260921/页面导航.json').write_text(json.dumps(groups,ensure_ascii=False,indent=2),'utf-8')
print('Page navigation wrapper updated.')
