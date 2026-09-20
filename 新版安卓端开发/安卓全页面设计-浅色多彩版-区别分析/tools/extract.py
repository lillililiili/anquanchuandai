from pathlib import Path
import json, re, hashlib, zipfile, xml.etree.ElementTree as ET
from html.parser import HTMLParser
from PIL import Image, ImageOps, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parents[1]
REF=ROOT/'新版安卓端开发/安卓全页面设计-浅色多彩版'
CUR=ROOT/'新版安卓端开发/安卓全页面设计-当前预览版'
APP=ROOT/'android代码/melhat_android-main'
EV=OUT/'证据'; EV.mkdir(exist_ok=True)
class Parser(HTMLParser):
    def __init__(self): super().__init__(); self.text=[]; self.links=[]
    def handle_data(self,data):
        if data.strip(): self.text.append(data.strip())
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='a': self.links.append(a.get('href',''))

refs=json.loads((REF/'manifest.json').read_text('utf-8-sig'))
cur=json.loads((CUR/'manifest.json').read_text('utf-8-sig'))
records=[]
for r in refs:
    p=Parser(); p.feed((REF/f"pages/{r['id']}.html").read_text('utf-8-sig'))
    records.append(dict(**r,text=p.text,links=p.links))
(EV/'参考稿逐页文本.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),'utf-8')
(EV/'参考稿逐页文本.txt').write_text('\n\n'.join(r['id']+' '+r['title']+'\n'+' | '.join(r['text']) for r in records),'utf-8')
old=json.loads((CUR/'源码校验.json').read_text('utf-8-sig'))
hashes=[]
for f,h in old.items():
    path=APP/f
    now=hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
    hashes.append({'path':f,'capture_sha256':h,'current_sha256':now,'match':h==now})
(EV/'截图源码一致性.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),'utf-8')
doc=ROOT/'新版安卓端开发/智能穿戴管理平台-整体设计方案.docx'
with zipfile.ZipFile(doc) as z:
    tree=ET.fromstring(z.read('word/document.xml'))
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
paras=[''.join(p.itertext()) for p in []]
paras=[''.join(t.text or '' for t in p.findall('.//w:t',ns)) for p in tree.findall('.//w:p',ns)]
(EV/'客户方案提取.txt').write_text('\n'.join(p for p in paras if p.strip()),'utf-8')
for f in (APP/'lib/wear').rglob('*.dart'):
    dst=EV/'源码摘录'/f.relative_to(APP/'lib/wear'); dst.parent.mkdir(parents=True,exist_ok=True)
    dst.with_suffix('.txt').write_text('\n'.join(f'{i}: {l}' for i,l in enumerate(f.read_text('utf-8-sig').splitlines(),1)),'utf-8')
print(json.dumps({'refs':len(refs),'captures':len(cur['items']),'hashes':len(hashes),'changed':[h['path'] for h in hashes if not h['match']],'doc_paras':len(paras)},ensure_ascii=False))
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
for start in range(1,41,2):
    cols=[]
    for n in range(start,start+2):
        sid=f'{n:02}'
        for base,tag in [(REF,'设计'),(CUR,'当前')]:
            src=next((base/'页面图片').glob(f'{sid}-*.png')) if base==REF else base/f'页面图片/{sid}.jpg'
            im=Image.open(src).convert('RGB')
            im=im.resize((390,round(im.height*390/im.width)))
            col=Image.new('RGB',(410,im.height+48),'#e0e7ef')
            ImageDraw.Draw(col).text((10,10),f'{sid} {tag}',font=font,fill='black')
            col.paste(im,(10,45)); cols.append(col)
    sheet=Image.new('RGB',(1640,max(x.height for x in cols)),'#e0e7ef')
    for i,col in enumerate(cols): sheet.paste(col,(i*410,0))
    sheet.save(EV/f'对照{start:02}-{start+1:02}.jpg',quality=90)
