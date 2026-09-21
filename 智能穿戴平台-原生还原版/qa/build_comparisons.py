"""Build inspection sheets from reference rasters and browser screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

root=Path(__file__).resolve().parent
references=Path('C:/Users/黄建凯/AppData/Local/Temp/wearable-pdf-inspection')
pages=json.loads((root/'page-checks.json').read_text(encoding='utf-8'))
for index,p in enumerate(pages,1):
    source=Image.open(references/f'page-{index:02}.png').convert('RGB')
    actual=Image.open(root/(p['name']+'.png')).convert('RGB')
    assert source.size==actual.size==(1672,941),(index,source.size,actual.size)
    comparison=Image.new('RGB',(3344,973),'#001b30')
    comparison.paste(source,(0,32)); comparison.paste(actual,(1672,32))
    draw=ImageDraw.Draw(comparison)
    draw.text((16,8),f'{index:02} PDF REFERENCE',fill='white')
    draw.text((1688,8),f'{index:02} IMPLEMENTATION / {p["route"]}',fill='white')
    comparison.save(root/f'comparison-{index:02}.png')
for start,end in [(1,6),(7,12),(13,17)]:
    contact=Image.new('RGB',(1672,3*256),'#001b30')
    for n,index in enumerate(range(start,end+1)):
        im=Image.open(root/f'comparison-{index:02}.png').resize((836,244))
        contact.paste(im,((n%2)*836,(n//2)*256))
    contact.save(root/f'comparison-contact-{start:02}-{end:02}.png')
for index,box,name in [(2,(1150,164,1663,684),'overview-status'),(4,(209,77,1098,465),'person-equipment'),(14,(1093,137,1648,915),'verification')]:
    source=Image.open(references/f'page-{index:02}.png').crop(box)
    actual=Image.open(root/(pages[index-1]['name']+'.png')).crop(box)
    im=Image.new('RGB',(source.width*2,source.height))
    im.paste(source,(0,0)); im.paste(actual,(source.width,0))
    im.save(root/f'focus-{name}.png')
print('17 full-view comparisons, 3 contact sheets, 3 focused comparisons written.')
names=['登录','综合总览','人员与装备','人员详情','作业列表','作业监护','视频墙','单路监看','现场资料','实时定位','历史轨迹','电子围栏','告警列表','核验详情','调度通信','SOS协同','统计追溯']
cards=''.join(f'<article><h2>{n:02} · {name}</h2><a href="comparison-{n:02}.png" target="_blank"><img src="comparison-{n:02}.png" loading="lazy" alt="{name}：左侧PDF，右侧实现"></a><a href="../index.html#/{pages[n-1]["route"]}" target="_blank">打开对应页面 →</a></article>' for n,name in enumerate(names,1))
(root/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>17页视觉对照</title><style>body{margin:0;padding:32px;background:#001b30;color:#e7f2ff;font:16px/1.8 system-ui}header{max-width:1200px;margin:auto}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(500px,1fr));gap:24px}article{background:#052a43;border:1px solid #1c4e6d;padding:18px;border-radius:6px}img{width:100%;height:auto;display:block}a{color:#53c8ff}h1,h2{margin:0 0 14px}h2{font-size:19px}</style><header><h1>智能穿戴平台 · 17页视觉对照</h1><p>每幅图左侧为 PDF，右侧为实际浏览器画面。点击图片查看原尺寸；基准视口 1672×941。生成素材与原图存在差异，详情见项目根目录 design-qa.md。</p><p><a href="../index.html">打开平台</a></p></header><main>'+cards+'</main></html>',encoding='utf-8')
