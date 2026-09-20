"""Verify baseline rows unchanged, final counts and supported seed associations."""
import json
from 执行工具 import ROOT,mysql,rows,save,counts
from 校验联调批次 import validate,CHECKS
B=sorted(ROOT.glob('执行批次-*'))[-1]
meta=json.loads((B/'备份验证.json').read_text('utf-8'));man=json.loads((B/'批次清单.json').read_text('utf-8'));before=json.loads((B/'导入前表计数.json').read_text('utf-8'))
scratch=meta['scratchDatabase']
schema=rows("SELECT JSON_OBJECT('table',table_name,'column',column_name,'key',column_key) FROM information_schema.columns WHERE table_schema=DATABASE() ORDER BY table_name,ordinal_position;")
results=[]
for t,n in before.items():
    if not n or t in ['sys_logininfor','sys_oper_log','sys_job_log']: continue
    cols=[r['column'] for r in schema if r['table']==t]
    pk=[r['column'] for r in schema if r['table']==t and r['key']=='PRI']
    if not pk:continue
    where='1=1'
    if t in man['ids']:where='s.`'+pk[0]+'`<'+str(min(man['ids'][t]))
    elif t=='sys_user_role':where='s.user_id<'+str(min(man['ids']['sys_user']))
    on=' AND '.join('s.`'+c+'`=l.`'+c+'`' for c in pk)
    diff=' OR '.join('NOT(CAST(s.`'+c+'` AS BINARY)<=>CAST(l.`'+c+'` AS BINARY))' for c in cols)
    q="SELECT JSON_OBJECT('table','"+t+"','beforeRows',COUNT(*),'changedOrDeleted',SUM(IF(l.`"+pk[0]+"` IS NULL OR ("+diff+"),1,0))) FROM `"+scratch+'`.`'+t+'` s LEFT JOIN `'+t+'` l ON '+on+' WHERE '+where+';'
    r=rows(q)[0];results.append(r)
    assert r['beforeRows']==n,(t,'baseline row count')
    assert not r['changedOrDeleted'],r
save(B/'原有记录逐字段核对.json',results)
validate('melhat_local')
extra={
 '新增帽子兼容映射完整':"SELECT COUNT(*) FROM wear_device d JOIN wear_product_model p ON p.id=d.model_id LEFT JOIN wear_device_legacy_hat m ON m.device_id=d.id LEFT JOIN safety_hat_info h ON h.id=m.hat_id WHERE d.id>11 AND p.type_code='helmet' AND (h.id IS NULL OR h.hat_number<>d.sn OR h.site_id<>d.site_id)",
 '新增媒体文件关联一致':"SELECT COUNT(*) FROM file_record f LEFT JOIN safety_hat_info h ON h.id=f.hat_id WHERE f.id>6 AND (h.id IS NULL OR h.hat_number<>f.hat_number OR f.file_url NOT LIKE 'http://127.0.0.1:18084/profile/QA%')",
 '新账号具备角色和厂站':"SELECT COUNT(*) FROM sys_user u WHERE u.user_name LIKE 'qa_%' AND (NOT EXISTS(SELECT 1 FROM sys_user_role r WHERE r.user_id=u.user_id) OR NOT EXISTS(SELECT 1 FROM wear_site_account s WHERE s.user_id=u.user_id AND s.status='0'))",
 '交接双方有效同厂站':"SELECT COUNT(*) FROM wear_duty_handover h WHERE from_user_id=to_user_id OR NOT EXISTS(SELECT 1 FROM wear_site_account a WHERE a.user_id=h.from_user_id AND a.site_id=h.site_id AND a.status='0') OR NOT EXISTS(SELECT 1 FROM wear_site_account a WHERE a.user_id=h.to_user_id AND a.site_id=h.site_id AND a.status='0') OR (status='confirmed' AND confirmed_at IS NULL)",
 '上报已接受':"SELECT COUNT(*) FROM wear_ingest_raw WHERE process_status<>'accepted' OR error IS NOT NULL",
 '新合成人员演示标识':"SELECT COUNT(*) FROM wear_person WHERE id>9 AND create_by<>'demo'",
 '新合成设备演示标识':"SELECT COUNT(*) FROM wear_device WHERE id>11 AND create_by<>'demo'",
 '新事件演示标识':"SELECT COUNT(*) FROM wear_safety_event WHERE id>4 AND demo<>1",
}
r=rows('\n'.join("SELECT JSON_OBJECT('check','"+n+"','violations',("+q+"));" for n,q in extra.items()))
assert not any(x['violations'] for x in r),r
save(B/'补充业务校验.json',r)
save(B/'最终表计数.json',counts())
print(json.dumps({'preservedTables':len(results),'preservedRows':sum(r['beforeRows'] for r in results),'changedOriginalRows':0,'finalBusinessChecks':len(CHECKS)+len(extra)},ensure_ascii=False))
