"""Source-only component previews. Coordinates, paths, colors and text come from Sketch.

These are inspectable SVG exports, not screenshots produced by the macOS Sketch renderer.
They are dev-only evidence; no source labels or descriptions enter product pages.
"""
import importlib.util, json, html, zipfile
from pathlib import Path
spec = importlib.util.spec_from_file_location('source', Path(__file__).with_name('extract-ui-spec.py'))
s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)

def css_color(c):
    return s.color(c)['hex']

def render(n, root=False):
    if not n.get('isVisible', True): return ''
    f=n['frame']; st=n.get('style', {}); cls=n['_class']; w=f['width']; h=f['height']
    transform='' if root else ' transform="matrix('+ ' '.join(s.number(v) for v in s.matrix(n))+')"'
    opacity=st.get('contextSettings',{}).get('opacity',1)
    if cls=='text':
        t=n['attributedString']; spans=[]
        for a in t['attributes']:
            at=a['attributes']; font=at.get('MSAttributedStringFontAttribute',{}).get('attributes',{}); para=at.get('paragraphStyle',{})
            size=font.get('size',14); height=para.get('maximumLineHeight') or para.get('minimumLineHeight') or size*1.45
            weight=700 if 'Bold' in font.get('name','') else 500 if 'Medium' in font.get('name','') else 400
            color=at.get('MSAttributedStringColorAttribute',{'red':1,'green':1,'blue':1,'alpha':1})
            align={0:'left',1:'right',2:'center'}.get(para.get('alignment'), 'left')
            text=t['string'][a['location']:a['location']+a['length']]
            spans.append(f'<span style="font: {weight} {size}px/{height}px Arial,\'UI Source Han\',sans-serif;color:{css_color(color)};opacity:{color["alpha"]};letter-spacing:{at.get("kerning",0)}px">{html.escape(text)}</span>')
        body=f'<foreignObject width="{w}" height="{h+2}"><div xmlns="http://www.w3.org/1999/xhtml" style="margin:0;padding:0;white-space:pre-wrap;text-align:{align};height:{h}px">'+''.join(spans)+'</div></foreignObject>'
    elif cls in ['shapePath','rectangle','oval','triangle','shapeGroup']:
        body=s.svg_layer(n,root=True)
        # The actual enabled fill/border belong to this paint layer.
        fills=[p for p in st.get('fills',[]) if p.get('isEnabled')]; borders=[p for p in st.get('borders',[]) if p.get('isEnabled')]
        if fills: body=body.replace('fill="currentColor"',f'fill="{css_color(fills[0]["color"])}"')
        if borders:body=body.replace('stroke="currentColor"',f'stroke="{css_color(borders[0]["color"])}"')
    else:body=''.join(render(c) for c in n.get('layers',[]))
    return f'<g{transform} opacity="{opacity}">{body}</g>'

with zipfile.ZipFile(s.SOURCE) as z:
    doc=json.loads(z.read('document.json')); page=json.loads(z.read(doc['pages'][0]['_ref']+'.json'))
flat=list(s.walk(page)); parents={c['do_objectID']:n for n,_,_ in flat for c in n.get('layers',[])}
lookup={n['do_objectID']:(n,p) for n,p,v in flat if v}
# Pick containing component groups by source paint ID; states remain separate.
ids=['4HFYwkQ-FC6Gp4FBgQYsn','xXg75oJxJl_WGdmtTTFuN','wFGy3DfrBzcg5MhEENjKM','A2OOwHqxrDM9sRhfmcp8W','CkstYJO3Hiokoedmyf64Z','t4_AdXg-GSXV4b5IZwBEI','vtlVFKvKZ4Sh3tlRTk-cz','I0Y7nDcT1zSenZWCzO4cL','VThA-ge8SrGF2fZV7JafD','YkUSGQ69TR712LBDSGBvs','D1Y8tE-ndrB_DsfKhfE7C','g__GhdR1d9dK-EQIOHb7m','i8ZDtnIG6HRxJI076cCjY','3k6gBRbiF_I2Ti3k5B7Nc']
references=[]
for id in ids:
    n=parents[id]
    if lookup[n['do_objectID']][1].startswith('/页面 1/开关') or n['name']=='bg':n=parents[n['do_objectID']]
    f=n['frame'];path=lookup[n['do_objectID']][1]
    references.append({'id':n['do_objectID'],'paintId':id,'path':path,'width':f['width'],'height':f['height'],'svg':f'<svg xmlns="http://www.w3.org/2000/svg" width="{f["width"]}" height="{f["height"]}" viewBox="0 0 {f["width"]} {f["height"]}">'+render(n,True)+'</svg>'})
(s.OUT/'evidence/reference-components.json').write_text(json.dumps(references,ensure_ascii=False,separators=(',',':')),'utf-8')
# A concise independent map for controls rather than a dump of design annotations.
measurements=[]
for n,path,v in flat:
    if not v or not any('/'+b+'/' in path for b in ['按钮','选择器','日期选择器','输入框','复选框','单选框','开关','标签','文字提示']):continue
    if n['_class']=='group' and n['frame']['width']<=650 and n['frame']['height']<=400:
        paints=[{'id':c['do_objectID'],'frame':c['frame'],'fills':s.paint(c,'fills'),'borders':s.paint(c,'borders'),'radii':sorted(set(p.get('cornerRadius',0) for p in c.get('points',[])))} for c in n.get('layers',[]) if c.get('isVisible',True) and (s.paint(c,'fills') or s.paint(c,'borders'))]
        texts=[{'id':c['do_objectID'],'frame':c['frame'],'text':c.get('attributedString')} for c in n.get('layers',[]) if c.get('isVisible',True) and c['_class']=='text']
        if paints or texts:measurements.append({'id':n['do_objectID'],'path':path,'frame':n['frame'],'paints':paints,'texts':texts})
(s.OUT/'evidence/control-measurements.json').write_text(json.dumps(measurements,ensure_ascii=False,separators=(',',':')),'utf-8')
print(f'{len(references)} source previews; {len(measurements)} measured control groups')
