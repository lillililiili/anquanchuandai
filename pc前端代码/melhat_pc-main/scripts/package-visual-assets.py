from pathlib import Path
from PIL import Image
import json, shutil
root=Path.cwd()
output=root/'output/visual-upgrade'
manifest=json.loads((output/'assets.json').read_text(encoding='utf-8-sig'))
for item in manifest:
    name=item['name']
    original=output/'originals'/f'{name}.png'
    if not original.is_file():
        raise FileNotFoundError(f'Missing original asset: {original}')
    im=Image.open(original)
    if name=='brand-logo':
        im=im.convert('RGBA')
        assert im.getchannel('A').getextrema()[0]==0, 'Logo must have a true alpha channel'
        im.resize((512,512),Image.Resampling.LANCZOS).save(root/'public/visuals/brand-logo.png',optimize=True)
        for size in [16,32,48,180]:
            im.resize((size,size),Image.Resampling.LANCZOS).save(root/'public'/('apple-touch-icon.png' if size==180 else f'favicon-{size}.png'),optimize=True)
        im.resize((64,64),Image.Resampling.LANCZOS).save(root/'public/favicon.png',optimize=True)
        im.save(root/'public/favicon.ico',sizes=[(16,16),(32,32),(48,48)])
        item['runtime']='public/visuals/brand-logo.png'
    else:
        width=1536 if name=='login-hero' else 1600 if name=='screen-bg' else 480 if name.startswith('empty-') else 840
        im.thumbnail((width,width),Image.Resampling.LANCZOS)
        target=root/'public/visuals'/f'{name}.webp'
        im.convert('RGB').save(target,'WEBP',quality=86,method=6)
        item['runtime']=str(target.relative_to(root)).replace('\\','/')
    item['original']=f'originals/{name}.png'
    item['bytes']=(root/item['runtime']).stat().st_size
    item.pop('source',None)
(output/'assets.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps([{'name':i['name'],'KB':round(i['bytes']/1024,1)} for i in manifest],ensure_ascii=False))
