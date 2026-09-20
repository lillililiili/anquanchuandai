"""Read-only relational and business checks for this fixture batch."""
import json,sys
from 执行工具 import ROOT, mysql, rows, save
B=sorted(ROOT.glob('执行批次-*'))[-1]
MAN=json.loads((B/'批次清单.json').read_text('utf-8'))

CHECKS={
'人员账号引用':"SELECT COUNT(*) FROM wear_person p LEFT JOIN sys_user u ON u.user_id=p.account_user_id WHERE p.account_user_id IS NOT NULL AND u.user_id IS NULL",
'人员班组和主站':"SELECT COUNT(*) FROM wear_person p JOIN wear_team t ON t.id=p.team_id WHERE NOT EXISTS(SELECT 1 FROM wear_person_site s WHERE s.person_id=p.id AND s.site_id=t.site_id)",
'空间父子同厂站':"SELECT COUNT(*) FROM wear_space s LEFT JOIN wear_space p ON p.id=s.parent_id WHERE s.parent_id IS NOT NULL AND (p.id IS NULL OR p.site_id<>s.site_id)",
'型号合法':"SELECT COUNT(*) FROM wear_device d LEFT JOIN wear_product_model m ON m.id=d.model_id WHERE m.id IS NULL OR m.type_code NOT IN ('helmet','belt')",
'领用无孤儿':"SELECT COUNT(*) FROM wear_assignment a LEFT JOIN wear_device d ON d.id=a.device_id LEFT JOIN wear_person p ON p.id=a.person_id LEFT JOIN wear_site s ON s.id=a.site_id WHERE d.id IS NULL OR p.id IS NULL OR s.id IS NULL",
'领用时间顺序':"SELECT COUNT(*) FROM wear_assignment WHERE returned_at<issued_at",
'设备领用时间不重叠':"SELECT COUNT(*) FROM wear_assignment a JOIN wear_assignment b ON a.device_id=b.device_id AND a.id<b.id WHERE a.issued_at<COALESCE(b.returned_at,'2999-01-01') AND b.issued_at<COALESCE(a.returned_at,'2999-01-01')",
'同人同类型领用不重叠':"SELECT COUNT(*) FROM wear_assignment a JOIN wear_assignment b ON a.person_id=b.person_id AND a.id<b.id JOIN wear_device da ON da.id=a.device_id JOIN wear_device db ON db.id=b.device_id JOIN wear_product_model ma ON ma.id=da.model_id JOIN wear_product_model mb ON mb.id=db.model_id WHERE ma.type_code=mb.type_code AND a.issued_at<COALESCE(b.returned_at,'2999-01-01') AND b.issued_at<COALESCE(a.returned_at,'2999-01-01')",
'当前领用指针':"SELECT COUNT(*) FROM wear_device d LEFT JOIN wear_assignment a ON a.id=d.current_assignment_id WHERE (d.asset_status='issued' AND (a.id IS NULL OR a.device_id<>d.id OR a.returned_at IS NOT NULL)) OR (d.asset_status<>'issued' AND d.current_assignment_id IS NOT NULL)",
'有效领用人员同厂站':"SELECT COUNT(*) FROM wear_assignment a JOIN wear_device d ON d.id=a.device_id JOIN wear_person p ON p.id=a.person_id WHERE a.returned_at IS NULL AND (d.site_id<>a.site_id OR p.status<>'0' OR p.valid_to<CURDATE() OR NOT EXISTS(SELECT 1 FROM wear_person_site s WHERE s.person_id=p.id AND s.site_id=a.site_id AND s.status='0'))",
'历史采样发生在有效领用内':"SELECT COUNT(*) FROM wear_device_sample s WHERE NOT EXISTS(SELECT 1 FROM wear_assignment a WHERE a.device_id=s.device_id AND a.issued_at<=s.occurred_at AND (a.returned_at IS NULL OR a.returned_at>s.occurred_at))",
'遥测范围及时间':"SELECT COUNT(*) FROM wear_device_sample WHERE lat NOT BETWEEN -90 AND 90 OR lng NOT BETWEEN -180 AND 180 OR battery NOT BETWEEN 0 AND 100 OR occurred_at>NOW() OR received_at<occurred_at",
'安全带不伪造遥测':"SELECT COUNT(*) FROM wear_device d JOIN wear_product_model m ON m.id=d.model_id WHERE m.type_code='belt' AND (d.online IS NOT NULL OR d.battery IS NOT NULL OR d.last_telemetry_at IS NOT NULL)",
'任务成员同厂站':"SELECT COUNT(*) FROM wear_work_task_member m JOIN wear_work_task t ON t.id=m.task_id WHERE NOT EXISTS(SELECT 1 FROM wear_person_site p WHERE p.person_id=m.person_id AND p.site_id=t.site_id AND p.status='0')",
'任务负责人授权':"SELECT COUNT(*) FROM wear_work_task t WHERE t.owner_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM wear_site_account s WHERE s.user_id=t.owner_user_id AND s.site_id=t.site_id AND s.status='0')",
'任务监护人授权':"SELECT COUNT(*) FROM wear_work_task t WHERE t.guardian_person_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM wear_person_site s WHERE s.person_id=t.guardian_person_id AND s.site_id=t.site_id AND s.status='0')",
'任务时间状态':"SELECT COUNT(*) FROM wear_work_task WHERE planned_end<planned_start OR actual_end<actual_start OR (status='ended' AND actual_end IS NULL) OR (status IN ('in_progress','paused') AND actual_start IS NULL)",
'装备要求随作业类型':"SELECT COUNT(*) FROM wear_work_task t WHERE t.id>2 AND ((t.work_type='height' AND NOT EXISTS(SELECT 1 FROM wear_work_task_requirement r WHERE r.task_id=t.id AND r.type_code='belt')) OR (t.work_type<>'height' AND EXISTS(SELECT 1 FROM wear_work_task_requirement r WHERE r.task_id=t.id AND r.type_code='belt')))",
'新事件快照符合历史领用':"SELECT COUNT(*) FROM wear_safety_event e WHERE e.id>4 AND NOT EXISTS(SELECT 1 FROM wear_assignment a WHERE a.device_id=e.device_id AND a.person_id=e.person_id AND a.site_id=e.site_id AND a.issued_at<=e.occurred_at AND (a.returned_at IS NULL OR a.returned_at>e.occurred_at))",
'事件风险和状态枚举':"SELECT COUNT(*) FROM wear_safety_event WHERE status NOT IN ('open','claimed','handling','pending_review','closed') OR severity<>IF(event_type IN ('sos','fall','impact'),'high','low') OR (severity='low' AND status='pending_review')",
'事件关联任务匹配':"SELECT COUNT(*) FROM wear_safety_event e LEFT JOIN wear_work_task t ON t.id=e.task_id WHERE e.task_id IS NOT NULL AND (t.id IS NULL OR t.site_id<>e.site_id OR NOT EXISTS(SELECT 1 FROM wear_work_task_member m WHERE m.task_id=t.id AND m.person_id=e.person_id))",
'事件动作完整':"SELECT COUNT(*) FROM wear_safety_event e WHERE e.id>4 AND e.status<>'open' AND NOT EXISTS(SELECT 1 FROM wear_event_action a WHERE a.event_id=e.id AND a.to_status=e.status)",
'收件箱无越站派发':"SELECT COUNT(*) FROM wear_event_inbox i JOIN wear_safety_event e ON e.id=i.event_id WHERE NOT EXISTS(SELECT 1 FROM wear_site_account s WHERE s.user_id=i.user_id AND s.site_id=e.site_id AND s.status='0')",
'围栏人员同厂站':"SELECT COUNT(*) FROM wear_geo_fence_person p JOIN wear_geo_fence f ON f.id=p.fence_id WHERE NOT EXISTS(SELECT 1 FROM wear_person_site s WHERE s.person_id=p.person_id AND s.site_id=f.site_id AND s.status='0')",
'合成通话不假装接通':"SELECT COUNT(*) FROM wear_call_session WHERE demo<>1 OR connected_at IS NOT NULL OR ended_at<started_at OR status NOT IN ('ended','failed','timed_out')",
'通话型号能力':"SELECT COUNT(*) FROM wear_call_session c JOIN wear_device d ON d.id=c.device_id JOIN wear_product_model m ON m.id=d.model_id WHERE JSON_CONTAINS(JSON_EXTRACT(m.capabilities,'$.actions'),'\"intercom\"')=0 OR (c.video=1 AND JSON_CONTAINS(JSON_EXTRACT(m.capabilities,'$.actions'),'\"video\"')=0)",
'通话人员历史归属':"SELECT COUNT(*) FROM wear_call_session c WHERE NOT EXISTS(SELECT 1 FROM wear_assignment a WHERE a.device_id=c.device_id AND a.person_id=c.person_id AND a.site_id=c.site_id AND a.issued_at<=c.started_at AND (a.returned_at IS NULL OR a.returned_at>c.started_at))",
'事件通话关联':"SELECT COUNT(*) FROM wear_call_session c LEFT JOIN wear_safety_event e ON e.id=c.event_id WHERE (c.event_id IS NOT NULL AND (e.id IS NULL OR e.device_id<>c.device_id OR e.person_id<>c.person_id OR e.site_id<>c.site_id OR c.started_at<e.occurred_at)) OR (c.kind='sos' AND (e.id IS NULL OR e.event_type<>'sos'))",
'模拟播报不声称真实下发':"SELECT COUNT(*) FROM wear_device_command WHERE create_by LIKE 'qa_%' AND status<>'accepted'",
}

def validate(db):
    queries=[]
    for name,q in CHECKS.items():queries.append("SELECT JSON_OBJECT('check',"+"'"+name+"'"+",'violations',("+q+"));")
    result=rows('\n'.join(queries),db)
    save(B/('校验-'+db+'.json'),result)
    failures=[r for r in result if r['violations']]
    print(json.dumps({'database':db,'checks':len(result),'failures':failures},ensure_ascii=False))
    if failures:raise RuntimeError('Business validation failed')
    return result

if __name__=='__main__': validate(sys.argv[1] if len(sys.argv)>1 else 'melhat_local')
