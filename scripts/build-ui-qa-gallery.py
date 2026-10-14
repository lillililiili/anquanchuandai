"""Build a local screenshot gallery. Crops only the outside of the fixed viewport harness."""
import html
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/ui-spec'
checks=json.loads((OUT/'route-checks.json').read_text(encoding='utf-8'))
for p in (OUT/'after').glob('*.png'):
    m=re.search(r'-(\d+)x(\d+)\.png$',p.name)
    if not m:continue
    w,h=map(int,m.groups())
    with Image.open(p) as im:
        if im.width<w or im.height<h:raise ValueError(f'Incomplete screenshot: {p.name} {im.size}')
        if im.size!=(w,h):im.crop((0,0,w,h)).save(p)

body=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>UI 规范迁移截图验收</title><style>body{margin:24px;background:#121e37;color:#d1dae5;font:14px/1.6 Arial,"Microsoft YaHei",sans-serif}h1{font-size:24px}a{color:#83f6fd}section{margin:24px 0;padding:16px;background:rgba(80,177,249,.12);border-radius:12px}img{width:100%;display:block}figure{margin:0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}summary{cursor:pointer}nav{position:sticky;top:0;background:#121e37;padding:12px}small{color:#b0becb}code{overflow-wrap:anywhere}</style><h1>前台与管理后台 UI 规范验收</h1><p>前后对照统一为 1280×720；另存三个目标桌面尺寸。截图为真实应用，固定尺寸 iframe 仅用于尺寸校验；已裁去其外部空白，不缩放应用像素。业务数据会随快照与时间变化。</p><nav><a href="#before-after">前后对照</a> · <a href="#sizes">三尺寸记录</a> · <a href="#details">弹窗与控件</a> · <a href="computed-components.json">控件实测参数</a> · <a href="route-checks.json">路由实测记录</a></nav><h2 id="before-after">全部页面前后对照</h2>']
for p in sorted((OUT/'before').glob('*.png')):
    after=OUT/'after'/(p.stem+'-1280x720.png')
    if not after.exists():raise ValueError(f'Missing after: {after.name}')
    body.append(f'<section><h3>{html.escape(p.stem)}</h3><div class="pair"><figure><figcaption>改造前 · 1280×720</figcaption><a href="before/{p.name}"><img loading="lazy" src="before/{p.name}"></a></figure><figure><figcaption>改造后 · 1280×720</figcaption><a href="after/{after.name}"><img loading="lazy" src="after/{after.name}"></a></figure></div></section>')
body.append('<h2 id="sizes">1920×1080 / 1440×900 / 1366×768</h2>')
for c in sorted((c for c in checks if c['width']!=1280),key=lambda c:(c['app'],c['route'],-c['width'])):
    p=c['filename'];label=f"{c['app']} / {c['route']} · {c['width']}×{c['height']}"
    body.append(f'<details><summary>{html.escape(label)} — 横向溢出 {max(0,c["scrollWidth"]-c["clientWidth"])}px，缺失图片 {len(c["images"])}</summary><a href="after/{p}"><img loading="lazy" src="after/{p}"></a></details>')
body.append('<h2 id="details">弹窗、日期、更多操作及来源对照</h2>')
routefiles={c['filename'] for c in checks}
for p in sorted((OUT/'after').glob('*.png')):
    if p.name in routefiles:continue
    body.append(f'<details><summary>{html.escape(p.stem)}</summary><img loading="lazy" src="after/{p.name}"></details>')
body.append('</html>')
(OUT/'index.html').write_text('\n'.join(body),encoding='utf-8')

# Overview sheets for review: six views per sheet, original files remain full resolution.
for app in ['portal','admin']:
    files=sorted((OUT/'after').glob(f'{app}-*-1366x768.png'))
    for page,start in enumerate(range(0,len(files),6),1):
        sheet=Image.new('RGB',(1366,3*410),'#e7edf5');draw=ImageDraw.Draw(sheet)
        for i,p in enumerate(files[start:start+6]):
            x=(i%2)*683;y=(i//2)*410
            with Image.open(p) as im:
                im.thumbnail((683,384));sheet.paste(im,(x,y+26))
            draw.text((x+8,y+6),p.stem,fill='#121e37')
        sheet.save(OUT/f'{app}-final-sheet-{page}.jpg',quality=93)
print(f'{len(checks)} route viewport checks; {len(list((OUT/"before").glob("*.png")))} before/after pairs')
