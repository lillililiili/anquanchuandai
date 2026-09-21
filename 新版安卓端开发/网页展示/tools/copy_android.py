"""Read Android source into this display project. Never builds in the source tree."""
from pathlib import Path
import shutil,hashlib,json,datetime
ROOT=Path(__file__).resolve().parents[1]
ANDROID=ROOT.parents[1]/'android代码/melhat_android-main'
DEST=ROOT/'展示源码'
assert ROOT in DEST.resolve().parents
assert not DEST.exists(), 'Snapshot already exists; do not overwrite display adaptations'
files=[]
for name in ['lib','assets','web','packages','test']:
    for f in (ANDROID/name).rglob('*'):
        if f.is_file():files.append(f)
for name in ['pubspec.yaml','pubspec.lock','analysis_options.yaml']:
    files.append(ANDROID/name)
hashes=[]
for f in files:
    rel=f.relative_to(ANDROID);target=DEST/rel
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(f,target)
    hashes.append({'path':rel.as_posix(),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
evidence=ROOT/'同步验收/20260921';evidence.mkdir(parents=True,exist_ok=True)
(evidence/'主项目只读快照.json').write_text(json.dumps({'source':str(ANDROID),'capturedAt':datetime.datetime.now().astimezone().isoformat(),'files':hashes},ensure_ascii=False,indent=2),'utf-8')
print('Copied',len(files),'files to isolated display source:',DEST)
