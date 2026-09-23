-- Run only after an event-table backup. Preserves independent call/command histories.
START TRANSACTION;
CREATE TEMPORARY TABLE unnamed_event_ids AS
SELECT id FROM wear_safety_event WHERE
  (TRIM(COALESCE(alarm_name,''))='' AND TRIM(COALESCE(alarm_code,''))='')
  OR TRIM(COALESCE(alarm_name,''))='告警名称未提供';
DELETE a FROM wear_event_action a JOIN unnamed_event_ids n ON n.id=a.event_id;
DELETE i FROM wear_event_inbox i JOIN unnamed_event_ids n ON n.id=i.event_id;
DELETE l FROM wear_event_legacy l JOIN unnamed_event_ids n ON n.id=l.event_id;
UPDATE wear_call_session c JOIN unnamed_event_ids n ON n.id=c.event_id SET c.event_id=NULL;
UPDATE wear_device_command c JOIN unnamed_event_ids n ON n.id=c.event_id SET c.event_id=NULL;
DELETE e FROM wear_safety_event e JOIN unnamed_event_ids n ON n.id=e.id;
UPDATE wear_safety_event e LEFT JOIN wear_device d ON d.id=e.device_id LEFT JOIN wear_product_model m ON m.id=d.model_id SET e.device_type=m.type_code;
UPDATE wear_safety_event SET severity=CASE
  WHEN event_type='sos' THEN 'emergency'
  WHEN device_type IN ('helmet','belt','watch') AND alarm_code IN (CONCAT(device_type,'.battery'),CONCAT(device_type,'.low_battery')) THEN 'warning'
  ELSE 'abnormal' END;
-- Legacy text-only submissions must obtain a photo before they can finish.
INSERT INTO wear_event_action(event_id,action,actor,reason,from_status,to_status,create_time)
SELECT id,'reopen','system','分级流程迁移：请补拍现场照片后提交','pending_review','handling',NOW()
FROM wear_safety_event WHERE severity='abnormal' AND status='pending_review';
UPDATE wear_safety_event SET status='handling',version=version+1,update_by='system',update_time=NOW()
WHERE severity='abnormal' AND status='pending_review';
SELECT COUNT(*) AS deleted_unnamed_events FROM unnamed_event_ids;
DROP TEMPORARY TABLE unnamed_event_ids;
COMMIT;
