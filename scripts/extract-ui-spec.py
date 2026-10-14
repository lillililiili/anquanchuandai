"""Extract source geometry and evidence from the approved Sketch, without editing it."""
from pathlib import Path
import collections, hashlib, html, json, math, re, sys, zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'shared/ui-spec'
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r'D:\wx_chat\xwechat_files\wxid_x9ztlatrmfbm22_4b89\msg\file\2026-10\UI规范.sketch')
EXPECTED = '20ee13bff161045011c20cb5c4fda6d8128a6e74c97d8dec7c61f378d137c36f'

def walk(layer, path='', visible=True):
    path = path + '/' + layer.get('name', '')
    visible = visible and layer.get('isVisible', True)
    yield layer, path, visible
    for child in layer.get('layers', []):
        yield from walk(child, path, visible)

def color(c):
    return {'hex': '#' + ''.join(f'{round(c[k]*255):02X}' for k in ['red','green','blue']), 'alpha': c['alpha']}

def paint(layer, key):
    return [{**{'type': p['fillType'], 'color': color(p['color']), 'opacity': p.get('contextSettings', {}).get('opacity', 1)}, **({'width': p['thickness'], 'position': p.get('position')} if key == 'borders' else {})} for p in layer.get('style', {}).get(key, []) if p.get('isEnabled')]

def number(n):
    return f'{n:.7f}'.rstrip('0').rstrip('.') or '0'

def point(s):
    return [float(n) for n in s.strip('{}').split(',')]

def matrix(layer):
    f = layer['frame']; w, h = f['width'], f['height']
    angle = -math.radians(layer.get('rotation', 0)); c, s = math.cos(angle), math.sin(angle)
    sx = -1 if layer.get('isFlippedHorizontal') else 1
    sy = -1 if layer.get('isFlippedVertical') else 1
    a,b,c2,d = c*sx,s*sx,-s*sy,c*sy
    return (a,b,c2,d,f['x']+w/2-a*w/2-c2*h/2,f['y']+h/2-b*w/2-d*h/2)

def multiply(a,b):
    return (a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5])

def geometry(layer, mat=(1,0,0,1,0,0)):
    f=layer['frame']; w,h=f['width'],f['height']
    def pt(s):
        x,y=point(s); x*=w; y*=h
        return number(mat[0]*x+mat[2]*y+mat[4])+' '+number(mat[1]*x+mat[3]*y+mat[5])
    pts=layer.get('points', [])
    if not pts: return ''
    # Sketch stores rectangle corner radii separately from its anchor points.
    # Carry those radii into SVG instead of silently producing sharp corners.
    if layer['_class']=='rectangle' and len(pts)==4 and any(p.get('cornerRadius',0) for p in pts):
        vertices=[(point(p['point'])[0]*w,point(p['point'])[1]*h) for p in pts]
        def xy(p):return number(mat[0]*p[0]+mat[2]*p[1]+mat[4])+' '+number(mat[1]*p[0]+mat[3]*p[1]+mat[5])
        corners=[]
        for i,v in enumerate(vertices):
            previous=vertices[(i-1)%4];following=vertices[(i+1)%4]
            a=(previous[0]-v[0],previous[1]-v[1]);b=(following[0]-v[0],following[1]-v[1]);al=math.hypot(*a);bl=math.hypot(*b)
            r=min(pts[i].get('cornerRadius',0),al/2,bl/2)
            start=(v[0]+a[0]*r/al,v[1]+a[1]*r/al);end=(v[0]+b[0]*r/bl,v[1]+b[1]*r/bl)
            clockwise=int((a[0]*b[1]-a[1]*b[0])*(mat[0]*mat[3]-mat[1]*mat[2])<0)
            corners.append((start,end,r,clockwise))
        data=['M'+xy(corners[0][0])]
        for start,end,r,sweep in corners:
            data.append('L'+xy(start))
            data.append(f'A{number(r)} {number(r)} 0 0 {sweep} '+xy(end) if r else 'L'+xy(end))
        return ' '.join(data)+'Z'
    data=['M'+pt(pts[0]['point'])]
    for previous,current in zip(pts,pts[1:]+([pts[0]] if layer.get('isClosed') else [])):
        if previous.get('hasCurveFrom') or current.get('hasCurveTo'):
            data.append('C'+pt(previous['curveFrom'] if previous.get('hasCurveFrom') else previous['point'])+' '+pt(current['curveTo'] if current.get('hasCurveTo') else current['point'])+' '+pt(current['point']))
        else: data.append('L'+pt(current['point']))
    if layer.get('isClosed'): data.append('Z')
    return ' '.join(data)

def shape_paths(layer, mat=(1,0,0,1,0,0)):
    paths=[]
    for child in layer.get('layers',[]):
        if not child.get('isVisible',True): continue
        cm=multiply(mat,matrix(child))
        if child.get('points'): paths.append(geometry(child,cm))
        elif child['_class']=='shapeGroup': paths.extend(shape_paths(child,cm))
    return paths

def svg_layer(layer, root=False, clip=False):
    if not layer.get('isVisible',True):return ''
    style=layer.get('style',{}); f=layer['frame']; cls=layer['_class']
    opacity=style.get('contextSettings',{}).get('opacity',1)
    transform='' if root else ' transform="matrix('+ ' '.join(number(n) for n in matrix(layer)) + ')"'
    fills=[p for p in style.get('fills',[]) if p.get('isEnabled')]
    borders=[p for p in style.get('borders',[]) if p.get('isEnabled')]
    fill='none'; fill_opacity=1
    if fills:
        fill='currentColor'; fill_opacity=fills[0]['color']['alpha']*fills[0].get('contextSettings',{}).get('opacity',1)
    attrs=f' fill="{fill}" fill-opacity="{number(fill_opacity)}" fill-rule="'+('evenodd' if style.get('windingRule')==1 else 'nonzero')+'"'
    if clip: attrs=' fill="white"'
    if borders and not clip:
        b=borders[0];attrs+=f' stroke="currentColor" stroke-width="{number(b["thickness"])}" stroke-opacity="{number(b["color"]["alpha"])}"'
    tag=''
    if cls=='shapeGroup' and fills:
        tag='<path d="'+' '.join(shape_paths(layer))+'"'+attrs+'/>'
    elif cls in ['shapePath','rectangle','oval','triangle']:
        if layer.get('points'): tag='<path d="'+geometry(layer)+'"'+attrs+'/>'
        elif cls=='oval': tag=f'<ellipse cx="{number(f["width"]/2)}" cy="{number(f["height"]/2)}" rx="{number(f["width"]/2)}" ry="{number(f["height"]/2)}"{attrs}/>'
        else: tag=f'<rect width="{number(f["width"])}" height="{number(f["height"])}"{attrs}/>'
    else:
        children=[]; mask=None
        for child in layer.get('layers',[]):
            if child.get('shouldBreakMaskChain'): mask=None
            if child.get('hasClippingMask'):
                mask='clip-'+child['do_objectID']; children.append(f'<defs><clipPath id="{mask}">{svg_layer(child,clip=True)}</clipPath></defs>')
            rendered=svg_layer(child)
            children.append(f'<g clip-path="url(#{mask})">{rendered}</g>' if mask and not child.get('hasClippingMask') else rendered)
        tag=''.join(children)
    return f'<g{transform} opacity="{number(opacity)}">{tag}</g>'

def main():
    digest=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if digest!=EXPECTED: raise SystemExit('Source changed: review the new source before extracting.')
    OUT.mkdir(parents=True,exist_ok=True); (OUT/'fonts').mkdir(exist_ok=True); (OUT/'evidence').mkdir(exist_ok=True)
    with zipfile.ZipFile(SOURCE) as archive:
        doc=json.loads(archive.read('document.json')); page=json.loads(archive.read(doc['pages'][0]['_ref']+'.json'))
        flattened=list(walk(page)); index={n['do_objectID']:n for n,_,_ in flattened}
        colors=json.loads((ROOT/'智能穿戴平台-原生还原版/qa/sketch/reference/color-evidence.json').read_text('utf-8'))['colorSpecificationRows']
        for row in colors:
            for swatch in row['swatches']:
                actual=paint(index[swatch['id']],'fills'); assert actual[0]['color']==swatch['fills'][0]['color'],row['label']
        (OUT/'evidence/colors.json').write_text(json.dumps(colors,ensure_ascii=False,indent=2),'utf-8')
        fonts=[]
        for reference in doc['fontReferences']:
            if reference.get('fontData') and reference['fontFamilyName']=='Source Han Sans CN':
                name=reference['postscriptNames'][0]+'.otf'; data=archive.read(reference['fontData']['_ref']); (OUT/'fonts'/name).write_bytes(data)
                fonts.append({'file':name,'sourceRef':reference['fontData']['_ref'],'sha256':hashlib.sha256(data).hexdigest()})
        candidates={}
        # Component library wins over duplicates on business artboards.
        for section in ['Icons-filled','面性图标','描边图标']:
            board=next(n for n in page['layers'] if n['name']==section)
            for n,path,visible in walk(board):
                if n['_class'] in ['group','shapeGroup'] and re.fullmatch('[a-z][a-z0-9-]+',n['name']) and 12<=n['frame']['width']<=64 and 12<=n['frame']['height']<=64 and visible:
                    candidates[n['name']]=(n,path)
        (OUT/'evidence/icon-catalog.json').write_text(json.dumps({k:{'id':n['do_objectID'],'path':p,'width':n['frame']['width'],'height':n['frame']['height']} for k,(n,p) in candidates.items()},ensure_ascii=False,indent=2),'utf-8')
        aliases=json.loads((OUT/'icon-aliases.json').read_text('utf-8'))
        names=set(aliases.values())
        missing=names-candidates.keys()
        if missing: raise SystemExit('Missing source icons: '+str(sorted(missing)))
        symbols={}; proof={}
        for name in sorted(names):
            n,path=candidates[name]; body=svg_layer(n,root=True); f=n['frame']
            symbols[name]={'viewBox':f'0 0 {number(f["width"])} {number(f["height"])}','body':body}
            proof[name]={'id':n['do_objectID'],'path':path,'geometrySha256':hashlib.sha256(json.dumps(n,sort_keys=True).encode()).hexdigest()}
        (OUT/'icons.json').write_text(json.dumps(symbols,ensure_ascii=False,separators=(',',':')),'utf-8')
        (OUT/'evidence/icons.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),'utf-8')
        inventory=[]
        for board in page['layers']:
            if board['_class']!='group' or board['name'] in ['Icons-filled','面性图标','描边图标']:continue
            for n,path,visible in walk(board):
                if not visible:continue
                st=n.get('style',{}); text=n.get('attributedString',{})
                if n['_class']=='text' or paint(n,'fills') or paint(n,'borders'):
                    inventory.append({'id':n['do_objectID'],'path':path,'class':n['_class'],'frame':n['frame'],'fills':paint(n,'fills'),'borders':paint(n,'borders'),'opacity':st.get('contextSettings',{}).get('opacity',1),'radii':sorted(set(p.get('cornerRadius',0) for p in n.get('points',[]))),'text':text,'shadows':[s for s in st.get('shadows',[]) if s.get('isEnabled')]})
        (OUT/'evidence/components.json').write_text(json.dumps(inventory,ensure_ascii=False,separators=(',',':')),'utf-8')
        manifest={'source':SOURCE.name,'sha256':digest,'pageCount':1,'layerCount':len(flattened),'groups':[{'name':n['name'],'id':n['do_objectID'],'layers':sum(1 for _ in walk(n))} for n in page['layers'] if n['_class']=='group'],'artboards':[{'name':n['name'],'id':n['do_objectID'],'frame':n['frame']} for n in page['layers'] if n['_class']=='artboard'],'colors':len(colors),'fonts':fonts,'iconCount':len(symbols),'inventoryCount':len(inventory),'adaptations':['原稿缺少直接对应项时使用同库语义近似图标，见 icon-aliases.json','大屏指标字号和画布比例保留现状','品牌与业务图片保留现有资源']}
        (OUT/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),'utf-8')
        print(json.dumps({k:manifest[k] for k in ['layerCount','colors','iconCount','inventoryCount']},ensure_ascii=False))

if __name__=='__main__':main()
