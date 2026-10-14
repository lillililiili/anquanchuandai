"""Replace legacy paint literals with semantic Sketch tokens; leave geometry intact."""
from pathlib import Path
import colorsys,json,re
ROOT=Path(__file__).resolve().parents[1]
color_re=re.compile(r'#[0-9a-fA-F]{3,8}\b|rgba?\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+(?:\s*,\s*[\d.]+)?\s*\)')
records=[]
def rgb(s):
 if s.startswith('#'):
  x=s[1:]
  if len(x) in [3,4]:x=''.join(c*2 for c in x)
  if len(x) not in [6,8]:return None
  return [int(x[i:i+2],16) for i in [0,2,4]]+[int(x[6:8],16)/255 if len(x)==8 else 1]
 n=[float(v) for v in re.findall(r'[\d.]+',s)];return n[:3]+[n[3] if len(n)>3 else 1]
def role(s,prop,selector):
 c=rgb(s)
 if not c:return s
 r,g,b,a=c;h,l,sat=colorsys.rgb_to_hls(r/255,g/255,b/255);h*=360
 if a==0:return 'transparent'
 foreground=prop in ['color','fill','stroke','text-decoration-color','caret-color','accent-color']
 semantic='red' if (h<12 or h>=340) and sat>.3 else 'orange' if 12<=h<42 and sat>.3 else 'yellow' if 42<=h<80 and sat>.3 else 'green' if 80<=h<170 and sat>.3 else None
 if 'shadow' in prop:
  return 'var(--theme-shadow-modal)' if a>.25 else 'var(--theme-shadow-soft)'
 if foreground:
  if semantic:return f'var(--theme-{semantic})'
  if l>.92:return 'var(--theme-heading)'
  if sat>.5 and 165<=h<205 and l>.5:return 'var(--theme-accent)'
  if sat>.5 and 165<=h<275 and .35<l<.65:return 'var(--theme-primary)'
  if 'disabled' in selector:return 'var(--theme-disabled)'
  if 'muted' in selector or 'small' in selector or 'placeholder' in selector:return 'var(--theme-muted)'
  return 'var(--theme-text)' if l<.5 or l>.7 else 'var(--theme-muted)'
 if 'border' in prop or 'outline' in prop:
  if semantic:return f'var(--theme-{semantic})'
  return 'var(--theme-divider)' if sat<.15 or a<=.15 else 'var(--theme-border-disabled)' if a<.3 else 'var(--theme-border)'
 if 'background' in prop:
  if semantic:return f'var(--theme-tag-{semantic})'
  if 'disabled' in selector:return 'var(--theme-input-disabled-bg)'
  if any(v in selector for v in ['selected','active']):return 'var(--theme-selected)'
  if any(v in selector for v in ['primary','bar b','bar > b','progress-fill']):return 'var(--theme-primary)'
  if a<1 and r<35 and g<35 and b<35:return 'var(--theme-overlay-shade)'
  return 'var(--theme-bg)' if l<.1 else 'var(--theme-card)'
 return s
def css_text(text,path):
 def rule(m):
  selector,body=m.group(1),m.group(2)
  def declaration(d):
   prop,value=d.group(1),d.group(2)
   if prop.startswith('--'):return d.group(0)
   def replace(c):
    new=role(c.group(),prop,selector)
    if new!=c.group():records.append({'file':str(path.relative_to(ROOT)),'selector':selector.strip()[-160:],'property':prop,'before':c.group(),'after':new})
    return new
   value=color_re.sub(replace,value)
   if prop=='font-size' and 'screen' not in str(path) and '.screen' not in selector:
    size=re.fullmatch(r'\s*(\d+)px\s*',value)
    if size and int(size[1])<25:value=str(min([12,14,16,18,24],key=lambda s:abs(s-int(size[1]))))+'px'
   return prop+':'+value
  body=re.sub(r'([\w-]+)\s*:([^;{}]+)',declaration,body)
  return selector+'{'+body+'}'
 return re.sub(r'([^{}]+)\{([^{}]*)\}',rule,text)
for folder in ['pc前台项目/src/styles','pc后台项目/styles']:
 for path in (ROOT/folder).rglob('*.css'):
  if 'spec-' in path.name or path.name in ['tokens.css','001-tokens.css','003-tokens.css']:continue
  text=path.read_text('utf-8');path.write_text(css_text(text,path),'utf-8')
for path in (ROOT/'pc后台项目').rglob('*.vue'):
 if 'node_modules' in path.parts:continue
 text=path.read_text('utf-8');text=re.sub(r'(<style[^>]*>)(.*?)(</style>)',lambda m:m[1]+css_text(m[2],path)+m[3],text,flags=re.S);path.write_text(text,'utf-8')
(ROOT/'shared/ui-spec/evidence/legacy-paint-mapping.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),'utf-8')
print('Legacy paint declarations normalized:',len(records))
