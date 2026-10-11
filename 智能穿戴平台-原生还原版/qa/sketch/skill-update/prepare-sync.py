"""Prepare a reviewable, hash-checked list for the authorized Desktop skill update."""
import hashlib, json
from pathlib import Path
base=Path(__file__).parent
desktop=Path('C:/Users/19221/Desktop/data')
names=['AGENTS.md','使用说明.md','personal-ui-framework/SKILL.md']
names += ['personal-ui-framework/references/'+n for n in ['合并提示词.md','完整性核对.md','合并提示词-历史未核实版.md','Sketch核实参数.md','Sketch证据.json','修订校验.json']]
digest=lambda b: hashlib.sha256(b).hexdigest()
rows=[]
for name in names:
    source=base/'data'/name
    target=desktop/name
    before=target.read_bytes() if target.exists() else None
    if before is not None:
        backup=base/'before-data'/name
        backup.parent.mkdir(parents=True,exist_ok=True)
        backup.write_bytes(before)
    rows.append({'relativePath':name,'source':str(source),'destination':str(target),'oldSha256':digest(before) if before is not None else None,'newSha256':digest(source.read_bytes())})
(base/'sync-manifest.json').write_text(json.dumps({'targetRoot':str(desktop),'files':rows},ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared',len(rows),'file updates with backups for',sum(r['oldSha256'] is not None for r in rows),'existing files')
