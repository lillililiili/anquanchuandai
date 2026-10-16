"""Export the approved Sketch business artboards and their reusable artwork.

Source paths/paints are preserved; these SVGs are NOT native Sketch screenshots.
The HTML reference viewer shares the embedded source fonts with the application.
"""
from pathlib import Path
from io import BytesIO
from PIL import Image
import base64, copy, hashlib, html, importlib.util, json, math, re, sys, zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('source', ROOT / 'scripts/extract-ui-spec.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)
OUT = ROOT / 'shared/ui-spec/portal'
PUBLIC = ROOT / 'pc前台项目/public/assets/sketch'
REFERENCES = ROOT / 'pc前台项目/ui-reference'
BLENDS = ['normal', 'darken', 'multiply', 'color-burn', 'lighten', 'screen',
          'color-dodge', 'overlay', 'soft-light', 'hard-light', 'difference',
          'exclusion', 'hue', 'saturation', 'color', 'luminosity', 'plus-lighter']


def rgba(c):
    return 'rgba(' + ','.join(str(round(c[k]*255)) for k in ['red','green','blue']) + ',' + s.number(c['alpha']) + ')'


def layer_matrix(layer):
    """Rotate about the frame center, then flip along the parent axes.

    Applying the flips before rotation reverses the top background fade:
    its transparent inner edge becomes the opaque edge of a 189px band.
    """
    f = layer['frame']; w, h = f['width'], f['height']
    angle = -math.radians(layer.get('rotation', 0))
    cosine, sine = math.cos(angle), math.sin(angle)
    sx = -1 if layer.get('isFlippedHorizontal') else 1
    sy = -1 if layer.get('isFlippedVertical') else 1
    a, b, c, d = sx*cosine, sy*sine, -sx*sine, sy*cosine
    return (a, b, c, d, f['x']+w/2-a*w/2-c*h/2, f['y']+h/2-b*w/2-d*h/2)


def shape_paths(layer, matrix=(1, 0, 0, 1, 0, 0)):
    paths = []
    for child in layer.get('layers', []):
        if not child.get('isVisible', True): continue
        child_matrix = s.multiply(matrix, layer_matrix(child))
        if child.get('points'): paths.append(s.geometry(child, child_matrix))
        elif child['_class'] == 'shapeGroup': paths.extend(shape_paths(child, child_matrix))
    return paths


class Exporter:
    def __init__(self, archive, inline_images=True):
        self.archive = archive
        self.inline_images = inline_images
        self.image_refs = {}
        self.image_cache = {}
        self.warnings = set()

    def image(self, ref):
        if ref in self.image_cache:
            return self.image_cache[ref]
        data = self.archive.read(ref)
        digest = hashlib.sha256(data).hexdigest()
        self.image_refs[ref] = {'sha256': digest, 'bytes': len(data)}
        target = REFERENCES / 'images' / Path(ref).name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        if self.inline_images:
            mime = 'image/jpeg' if data[:2] == b'\xff\xd8' else 'image/png'
            # Lossless transport encoding only: preserve every decoded RGBA byte.
            # Keep the untouched original in the reference viewer/provenance.
            original = Image.open(BytesIO(data)).convert('RGBA')
            buffer = BytesIO()
            original.save(buffer, format='WEBP', lossless=True, exact=True, method=6)
            encoded = buffer.getvalue()
            if len(encoded) < len(data):
                assert Image.open(BytesIO(encoded)).convert('RGBA').tobytes() == original.tobytes()
                self.image_refs[ref]['transport'] = {'format':'webp-lossless','bytes':len(encoded),'sha256':hashlib.sha256(encoded).hexdigest(),'rgbaExact':True}
                data, mime = encoded, 'image/webp'
            self.image_cache[ref] = 'data:' + mime + ';base64,' + base64.b64encode(data).decode()
            return self.image_cache[ref]
        return '/ui-reference/images/' + target.name

    def paint(self, paint, uid, frame):
        ctx = paint.get('contextSettings', {})
        opacity = ctx.get('opacity', 1)
        if paint.get('fillType', 0) == 0:
            return '', rgba(paint['color']), opacity
        if paint.get('fillType') == 1:
            g = paint['gradient']; a = s.point(g['from']); b = s.point(g['to'])
            stops = ''.join(f'<stop offset="{p["position"]}" stop-color="{rgba(p["color"])}"/>' for p in g['stops'])
            if g['gradientType'] == 0:
                tag = f'<linearGradient id="{uid}" x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}">{stops}</linearGradient>'
            else:
                # Sketch's radial major axis is the from/to vector in layer pixels.
                w,h = frame['width'],frame['height']; dx=(b[0]-a[0])*w; dy=(b[1]-a[1])*h
                radius=math.hypot(dx,dy); angle=math.degrees(math.atan2(dy,dx))
                ratio=g.get('elipseLength') or 1
                tag = f'<radialGradient id="{uid}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="{radius}" gradientTransform="translate({a[0]*w} {a[1]*h}) rotate({angle}) scale(1 {ratio})">{stops}</radialGradient>'
            return '<defs>'+tag+'</defs>', 'url(#'+uid+')', opacity
        if paint.get('fillType') == 4 and paint.get('image'):
            href=self.image(paint['image']['_ref'])
            tag=f'<pattern id="{uid}" patternContentUnits="objectBoundingBox" width="1" height="1"><image href="{href}" width="1" height="1" preserveAspectRatio="xMidYMid slice"/></pattern>'
            return '<defs>'+tag+'</defs>', 'url(#'+uid+')', opacity
        self.warnings.add('unsupported fill type '+str(paint.get('fillType')))
        return '', rgba(paint['color']), opacity

    def geometry(self, n, attrs):
        f=n['frame']
        if n['_class']=='shapeGroup':
            return '<path d="'+' '.join(shape_paths(n))+'" '+attrs+'/>'
        if n.get('points'):
            return '<path d="'+s.geometry(n)+'" '+attrs+'/>'
        if n['_class']=='oval':
            return f'<ellipse cx="{f["width"]/2}" cy="{f["height"]/2}" rx="{f["width"]/2}" ry="{f["height"]/2}" {attrs}/>'
        return f'<rect width="{f["width"]}" height="{f["height"]}" {attrs}/>'

    def render(self, n, root=False, text=True, clip=False):
        if not n.get('isVisible', True): return ''
        st=n.get('style', {}); f=n['frame']; cls=n['_class']; uid='s'+n['do_objectID']
        transform='' if root else ' transform="matrix('+' '.join(s.number(v) for v in layer_matrix(n))+')"'
        ctx=st.get('contextSettings', {}); blend=ctx.get('blendMode',0)
        attrs=f' opacity="{ctx.get("opacity",1)}" style="mix-blend-mode:{BLENDS[blend] if blend<len(BLENDS) else "normal"}"'
        fills=[p for p in st.get('fills',[]) if p.get('isEnabled')]
        borders=[p for p in st.get('borders',[]) if p.get('isEnabled')]
        body=''
        if clip:
            # SVG clipPath accepts geometry directly. A <g> wrapper makes the
            # clip empty in Chromium, hiding every original bitmap below it.
            # Carry the Sketch transform on the geometry itself instead.
            return self.geometry(n,'fill="white"'+transform)
        elif cls=='bitmap':
            body=f'<image href="{self.image(n["image"]["_ref"])}" width="{f["width"]}" height="{f["height"]}" preserveAspectRatio="none"/>'
        elif cls=='text':
            if not text:return ''
            t=n['attributedString']; spans=[]; align='left'
            for run in t['attributes']:
                a=run['attributes']; font=a.get('MSAttributedStringFontAttribute',{}).get('attributes',{}); para=a.get('paragraphStyle',{})
                size=font.get('size',14); height=para.get('maximumLineHeight') or para.get('minimumLineHeight') or size*1.2
                name=font.get('name',''); weight=900 if 'Heavy' in name else 700 if 'Bold' in name else 500 if 'Medium' in name or 'Semibold' in name else 400
                color=rgba(fills[0]['color']) if fills and fills[0]['fillType']==0 else rgba(a.get('MSAttributedStringColorAttribute',{'red':1,'green':1,'blue':1,'alpha':1}))
                align={0:'left',1:'right',2:'center'}.get(para.get('alignment'),'left')
                # Sketch run offsets use UTF-16, as do JavaScript strings.
                raw=t['string'].encode('utf-16-le')[run['location']*2:(run['location']+run['length'])*2].decode('utf-16-le')
                gradient=''
                if fills and fills[0]['fillType']==1:
                    g=fills[0]['gradient']; stops=','.join(rgba(p['color'])+' '+str(p['position']*100)+'%' for p in g['stops'])
                    gradient=f'background:linear-gradient(180deg,{stops});background-clip:text;-webkit-background-clip:text;color:transparent;'
                spans.append(f'<span style="font: {weight} {size}px/{height}px Arial,\'UI Source Han\',sans-serif;color:{color};letter-spacing:{a.get("kerning",0)}px;{gradient}">{html.escape(raw)}</span>')
            body=f'<foreignObject width="{f["width"]+2}" height="{f["height"]+4}"><div xmlns="http://www.w3.org/1999/xhtml" style="margin:0;white-space:pre-wrap;text-align:{align}">'+''.join(spans)+'</div></foreignObject>'
        elif cls in ['shapePath','rectangle','oval','triangle','shapeGroup']:
            rule='evenodd' if st.get('windingRule')==1 else 'nonzero'
            for i,p in enumerate(fills):
                defs,fill,opacity=self.paint(p,uid+'f'+str(i),f)
                body+=defs+self.geometry(n,f'fill="{fill}" opacity="{opacity}" fill-rule="{rule}"')
            for i,p in enumerate(borders):
                defs,stroke,opacity=self.paint(p,uid+'b'+str(i),f)
                body+=defs+self.geometry(n,f'fill="none" stroke="{stroke}" stroke-width="{p["thickness"]}" opacity="{opacity}"')
            if cls=='shapeGroup' and not fills and not borders:
                body=''.join(self.render(c,text=text) for c in n.get('layers',[]))
        else:
            mask=None
            for child in n.get('layers',[]):
                if child.get('shouldBreakMaskChain'): mask=None
                if not child.get('isVisible',True):continue
                if child.get('hasClippingMask'):
                    mask='clip-'+child['do_objectID']
                    body+=f'<defs><clipPath id="{mask}">{self.render(child,clip=True)}</clipPath></defs>'
                    continue
                part=self.render(child,text=text)
                body+=f'<g clip-path="url(#{mask})">{part}</g>' if mask and not child.get('hasClippingMask') else part
        blur=st.get('blur',{})
        if blur.get('isEnabled') and blur.get('type')==0:
            body=f'<defs><filter id="{uid}blur" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="{blur.get("radius",0)/2}"/></filter></defs><g filter="url(#{uid}blur)">{body}</g>'
        return f'<g{transform}{attrs}>{body}</g>'

    def svg(self,n,text=False):
        f=n['frame']
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{f["width"]}" height="{f["height"]}" viewBox="0 0 {f["width"]} {f["height"]}">'+self.render(n,root=True,text=text)+'</svg>'


def seamless_navigation_title(svg):
    """Union the mirrored title halves, preserving the source outline and paints.

    Their overlapping even-odd subpaths cut a transparent seam through the title.
    This presentation adaptation is explicitly requested for the portal header.
    """
    outlines = iter([
        'M0 0 L522 0.0000107 L506.5687542 31.4887268 '
        'C501.2496802 42.3430575 491.5843137 49 481.1442233 49 '
        'L40.8557767 48.9999893 '
        'C30.4156863 48.9999893 20.7503198 42.3430468 15.4312458 31.4887161 '
        'L5.7677084 11.7694054 Z',
        'M0 0 L455.5772825 0.0000107 L442.8717369 29.7020402 '
        'C437.801105 41.5560196 427.6860702 49 416.6493719 49 '
        'L38.9279106 48.9999893 '
        'C27.8912123 48.9999893 17.7761775 41.5560089 12.7055456 29.7020295 Z',
    ])
    assert len(re.findall(r'<path d="[^"]+"', svg)) == 2, 'Title artwork changed'
    return re.sub(r'<path d="[^"]+"', lambda _: f'<path d="{next(outlines)}"', svg)


def main():
    assert hashlib.sha256(s.SOURCE.read_bytes()).hexdigest()==s.EXPECTED, 'Sketch source changed'
    OUT.mkdir(parents=True,exist_ok=True); PUBLIC.mkdir(parents=True,exist_ok=True); REFERENCES.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(s.SOURCE) as z:
        doc=json.loads(z.read('document.json')); page=json.loads(z.read(doc['pages'][0]['_ref']+'.json'))
        flat=list(s.walk(page)); index={n['do_objectID']:n for n,_,_ in flat}
        boards=[n for n in page['layers'] if n['_class']=='artboard']
        evidence=[]
        for board in boards:
            for n,path,visible in s.walk(board):
                if not visible:continue
                evidence.append({'id':n['do_objectID'],'board':board['name'],'path':path,'class':n['_class'],'frame':n['frame'],
                                 'style':n.get('style',{}),'text':n.get('attributedString'),'image':n.get('image'),
                                 'radii':sorted(set(p.get('cornerRadius',0) for p in n.get('points',[])))})
        (OUT/'business-layers.json').write_text(json.dumps(evidence,ensure_ascii=False,separators=(',',':')),'utf-8')
        exp=Exporter(z); assets=[]
        def asset(name,n):
            svg=exp.svg(n)
            if name=='navigation-title.svg':svg=seamless_navigation_title(svg)
            data=svg.encode('utf-8'); (PUBLIC/name).write_bytes(data)
            assets.append({'file':name,'id':n['do_objectID'],'name':n['name'],'frame':n['frame'],'sha256':hashlib.sha256(data).hexdigest()})
            if name=='navigation-title.svg':assets[-1]['adaptation']='Merged mirrored halves into continuous outlines to remove the center seam; original gradients, opacity and outer silhouette preserved.'
        asset('business-background.svg',index['3197994C-12B8-437E-855E-893B62166CA5'])
        nav=index['41C718E0-27EF-48AB-9240-CBCF77F2041D']
        frame=copy.deepcopy(nav); frame['layers']=[c for c in nav['layers'] if c['_class'] in ['shapePath','shapeGroup']]
        # Split title and edge decoration to preserve the 522px title at every viewport.
        title=copy.deepcopy(frame); title['frame'].update(width=522,height=70)
        title['layers']=[copy.deepcopy(c) for c in frame['layers'] if c['_class']=='shapeGroup']
        for c in title['layers']:c['frame']['x']-=699
        asset('navigation-title.svg',title)
        parents={c['do_objectID']:n for n,_,_ in s.walk(nav) for c in n.get('layers',[])}
        for name,label in [('navigation-active.svg','智慧监盘'),('navigation-idle.svg','运行管理')]:
            text_node=next(n for n,_,v in s.walk(nav) if v and n['_class']=='text' and n.get('attributedString',{}).get('string')==label)
            asset(name,parents[text_node['do_objectID']])
        asset('section-heading.svg',index['67A52F67-DEAE-4ACB-9801-70CE6BB99902'])
        asset('filter-action.svg',index['6B237A78-EF80-44D0-964B-971401C13790'])
        asset('navigation-artwork.svg',frame)
        (OUT/'assets.json').write_text(json.dumps({'sourceSha256':s.EXPECTED,'assets':assets,'images':exp.image_refs,'rendererWarnings':sorted(exp.warnings)},ensure_ascii=False,indent=2),'utf-8')
        # Inline SVG viewer: font files and source bitmaps resolve locally in Vite.
        ref=Exporter(z,False); links=[]
        for i,board in enumerate(boards):
            filename=f'reference-{i+1}.html'
            content='<html lang="zh-CN"><meta charset="utf-8"><link rel="stylesheet" href="/src/portal-reference-fonts.css"><style>html,body{margin:0;background:#121e37}svg{display:block}</style>'+ref.svg(board,True)+'</html>'
            (REFERENCES/filename).write_text(content,'utf-8')
            links.append({'name':board['name'],'id':board['do_objectID'],'file':filename,'frame':board['frame']})
        (OUT/'references.json').write_text(json.dumps(links,ensure_ascii=False,indent=2),'utf-8')
        (OUT/'renderer-notes.json').write_text(json.dumps({'warnings':sorted(ref.warnings),'limitations':['SVG reconstruction, not a native Sketch render','Text line breaking and radial blur rasterization require visual comparison','Artwork uses original paths, enabled fills, opacity, transforms and clipping']},ensure_ascii=False,indent=2),'utf-8')
        print(json.dumps({'businessLayers':len(evidence),'assets':len(assets),'references':len(links),'warnings':sorted(exp.warnings|ref.warnings)},ensure_ascii=False))


if __name__=='__main__':main()
