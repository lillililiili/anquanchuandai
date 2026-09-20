"""Execute once, only after successful restoration and rehearsal."""
import json, hashlib
from datetime import datetime
from 执行工具 import ROOT, mysql, rows, save
from 校验联调批次 import validate

B=sorted(ROOT.glob('执行批次-*'))[-1]
meta=json.loads((B/'备份验证.json').read_text('utf-8'))
man=json.loads((B/'批次清单.json').read_text('utf-8'))
before=json.loads((B/'导入前表计数.json').read_text('utf-8'))
assert meta['restoreVerified']
assert not (B/'已提交.json').exists(),'Batch already committed; do not repeat'
for name,entry in meta['files'].items():assert hashlib.sha256((B/name).read_bytes()).hexdigest()==entry['sha256']
validate(meta['scratchDatabase'])
ts=list(man['counts'])
actual=rows('\n'.join("SELECT JSON_OBJECT('table','"+t+"','count',COUNT(*)) FROM `"+t+"`;" for t in ts))
assert all(x['count']==before[x['table']] for x in actual),'Baseline changed; regenerate from a fresh backup'
mysql((B/'导入.sql').read_text('utf-8'))
save(B/'已提交.json',{'at':datetime.now().astimezone().isoformat(),'database':'melhat_local','batch':man['batch'],'sqlSha256':hashlib.sha256((B/'导入.sql').read_bytes()).hexdigest()})
validate('melhat_local')
result=rows('\n'.join("SELECT JSON_OBJECT('table','"+t+"','count',COUNT(*)) FROM `"+t+"`;" for t in ts))
assert all(r['count']==before[r['table']]+man['counts'][r['table']] for r in result)
save(B/'基础导入后表计数.json',result)
print('COMMITTED and validated: '+man['batch'])
