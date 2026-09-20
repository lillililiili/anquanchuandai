from pathlib import Path
import zipfile,re,json,difflib
base=Path(r'C:\Users\黄建凯\Desktop\分体式安全帽代码')
root=Path(r'E:\沉积岩\anquanchuandai')
out=root/'tmp'/'original-comparison'
out.mkdir(parents=True,exist_ok=True)
for label,folder,name in [('pc','pc前端代码','melhat_pc-main'),('server','后端代码','melhat_server-dev')]:
    z=zipfile.ZipFile(base/folder/(name+'.zip'))
    original={}
    for n in z.namelist():
        if n.endswith('/'):continue
        parts=n.split('/')
        if name in parts: rel='/'.join(parts[parts.index(name)+1:])
        else: rel='/'.join(parts[1:])
        if not rel or any(p in {'.git','node_modules','target','dist','build','backups','output','.idea','.playwright-cli','logs'} for p in rel.split('/')):continue
        original[rel]=z.read(n)
    current={p.relative_to(root/folder/name).as_posix():p for p in (root/folder/name).rglob('*') if p.is_file() and not any(x in {'.git','node_modules','target','dist','build','backups','output','.idea','.playwright-cli','logs'} for x in p.relative_to(root/folder/name).parts)}
    result={'unchanged':[],'changed':[],'added':sorted(set(current)-set(original)),'removed':sorted(set(original)-set(current)),'script_changed':[],'bindings_changed':{}}
    diffs=[]
    for rel,data in original.items():
        if rel not in current:continue
        now=current[rel].read_bytes()
        if data==now:result['unchanged'].append(rel);continue
        try:a=data.decode('utf-8-sig').replace('\r\n','\n');b=now.decode('utf-8-sig').replace('\r\n','\n')
        except UnicodeDecodeError:result['changed'].append(rel);continue
        if a==b:result['unchanged'].append(rel);continue
        result['changed'].append(rel)
        if rel.endswith('.vue'):
            sa='\n'.join(re.findall(r'<script[^>]*>(.*?)</script>',a,re.S));sb='\n'.join(re.findall(r'<script[^>]*>(.*?)</script>',b,re.S))
            if re.sub(r'\s','',sa)!=re.sub(r'\s','',sb):
                result['script_changed'].append(rel)
                diffs.append('\nFILE '+rel+' SCRIPT\n'+''.join(difflib.unified_diff(sa.splitlines(True),sb.splitlines(True),n=3)))
            import collections
            pattern=r'(?:@[\w.:\-]+|v-model[\w.:\-]*|v-if|v-else-if|v-for|v-hasPermi|:disabled)\s*=\s*"[^"]*"'
            aa=collections.Counter(re.findall(pattern,a.split('<script')[0]));bb=collections.Counter(re.findall(pattern,b.split('<script')[0]))
            if aa!=bb:result['bindings_changed'][rel]={'removed':list((aa-bb).elements()),'added':list((bb-aa).elements())}
        elif Path(rel).suffix in {'.java','.js','.ts','.yml','.yaml','.xml','.json','.properties'} and 'lock' not in rel:
            diffs.append('\nFILE '+rel+'\n'+''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),n=3)))
    (out/(label+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/(label+'-diff.txt')).write_text('\n'.join(diffs),encoding='utf-8')
    print(label,{k:len(v) for k,v in result.items()})
    print('CHANGED',json.dumps(result['changed'],ensure_ascii=False));print('ADDED',json.dumps(result['added'],ensure_ascii=False));print('REMOVED',json.dumps(result['removed'],ensure_ascii=False));print('SCRIPT',json.dumps(result['script_changed'],ensure_ascii=False))
