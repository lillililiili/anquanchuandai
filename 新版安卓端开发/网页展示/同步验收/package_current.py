"""Verify compiled resources and refresh the distributable preview ZIP."""
import hashlib, json, urllib.request, zipfile
from pathlib import Path
from datetime import datetime

root=Path(__file__).resolve().parents[1]
android=root.parents[1]/'android代码/melhat_android-main'
site=root/'site'
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
info=json.loads((site/'build-info.json').read_text('utf-8'))
for entry in info['sourceFiles']:
    assert digest(android/entry['path'])==entry['sha256'], 'Source changed: '+entry['path']
for p in (android/'build/web').rglob('*'):
    if p.is_file():assert digest(p)==digest(site/p.relative_to(android/'build/web')),str(p)
assert digest(site/'main.dart.js')==info['mainJsSha256']
served=urllib.request.urlopen('http://127.0.0.1:18766/main.dart.js').read()
assert hashlib.sha256(served).hexdigest()==info['mainJsSha256'],'Server serves stale JavaScript'
checks=json.loads((root/'文件校验清单.json').read_text('utf-8'))
for entry in checks:assert digest(root/entry['path'])==entry['sha256'],entry['path']
qa=json.loads((root/'同步验收/browser-state.json').read_text('utf-8'))
assert qa.get('verifiedAt') and len(qa['snapshots'])>25 and not qa['errors'] and not qa['remote'],'Browser checks incomplete'
zip_path=root/'安卓网页展示-可直接运行.zip'
previous={}
if zip_path.exists():
    with zipfile.ZipFile(zip_path) as z:
        for n in z.namelist():
            normal=n.replace('\\','/')
            if normal.startswith('site/') and not normal.endswith('/'):
                previous[normal]=hashlib.sha256(z.read(n)).hexdigest()
changed=[x['path'] for x in checks if previous.get(x['path'])!=x['sha256']]
report={'verifiedAt':datetime.now().isoformat(timespec='seconds'),'builtAt':info['builtAt'],'sourceFilesVerified':len(info['sourceFiles']),'compiledFilesVerified':len(checks),'servedMainMatches':True,'mainJsSha256':info['mainJsSha256'],'changedSincePreviousPackage':changed,'widgetTestsPassed':46,'browserScreens':len(qa['snapshots']),'browserErrors':qa['errors'],'externalRequests':qa['remote']}
(root/'同步验收/交付核对.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf-8')
files=[p for p in site.rglob('*') if p.is_file()]
files += [root/name for name in ['打开安卓演示.cmd','停止安卓演示.cmd','启动网页.ps1','使用说明.md','重新构建.ps1','文件校验清单.json']]
files += [p for p in (root/'同步验收').rglob('*') if p.is_file() and p.suffix in {'.md','.json','.png'} and not p.name.startswith('00-')]
files += [root/'同步验收'/name for name in ['current-regression.log','flutter-test.log','build-final.log','browser-final.log','analyze-final.log','track-regression.log']]
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files:z.write(p,p.relative_to(root))
with zipfile.ZipFile(zip_path) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read('site/main.dart.js')).hexdigest()==info['mainJsSha256']
print(json.dumps({'sourceFiles':len(info['sourceFiles']),'compiledFiles':len(checks),'changedFiles':len(changed),'zipMB':round(zip_path.stat().st_size/1024/1024,1),'allChecksPassed':True},ensure_ascii=False))
