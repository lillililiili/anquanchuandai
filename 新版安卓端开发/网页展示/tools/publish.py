from pathlib import Path
import json,hashlib,shutil,datetime
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'展示源码';BUILD=SRC/'build/web';SITE=ROOT/'site'
assert (BUILD/'main.dart.js').is_file()
backup=ROOT/'历史备份/site-20260918'
if not backup.exists() and SITE.exists():
    assert SITE.resolve()==ROOT.resolve()/'site' and ROOT.resolve() in backup.resolve().parents
    backup.parent.mkdir(exist_ok=True)
    shutil.move(str(SITE),str(backup))
SITE.mkdir(exist_ok=True)
shutil.copytree(BUILD,SITE,dirs_exist_ok=True)
html=(SRC/'web/index.html').read_text('utf-8').replace('$FLUTTER_BASE_HREF','./')
(SITE/'index.html').write_text(html,'utf-8')
f=SITE/'assets/FontManifest.json';manifest=json.loads(f.read_text('utf-8'));manifest=[r for r in manifest if r['family']!='Roboto'];manifest.append({'family':'Roboto','fonts':[{'asset':'../fonts/NotoSansCJKsc-Regular.otf'}]});f.write_text(json.dumps(manifest),'utf-8')
baseline=json.loads((ROOT/'同步验收/20260921/主项目只读快照.json').read_text('utf-8'))
info={'builtAt':datetime.datetime.now().astimezone().isoformat(),'source':baseline['source'],'sourceCapturedAt':baseline['capturedAt'],'sourceFiles':baseline['files'],'isolatedBuild':True,'entrypoint':'展示源码/lib/web_preview/main.dart','callLabEnabled':True,'dataMode':'local frozen snapshot; no external requests','mainJsSha256':hashlib.sha256((SITE/'main.dart.js').read_bytes()).hexdigest()}
(SITE/'build-info.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),'utf-8')
print('Published isolated Android static build:',SITE)
