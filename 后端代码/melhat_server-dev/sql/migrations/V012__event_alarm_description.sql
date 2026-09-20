-- Event-time descriptions supplied by the core, independent of workflow status.
-- Idempotent: preserve existing snapshots, never infer alarms from source IDs.
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='wear_safety_event' AND column_name='alarm_code')=0,
  'ALTER TABLE wear_safety_event ADD COLUMN alarm_code VARCHAR(128) DEFAULT NULL', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='wear_safety_event' AND column_name='alarm_name')=0,
  'ALTER TABLE wear_safety_event ADD COLUMN alarm_name VARCHAR(255) DEFAULT NULL', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='wear_safety_event' AND column_name='alarm_description')=0,
  'ALTER TABLE wear_safety_event ADD COLUMN alarm_description VARCHAR(1000) DEFAULT NULL', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Historical simulator events already hold their actual name in the first audit.
-- Only valid simulator metadata is used; no dependency on today's device state.
UPDATE wear_safety_event e
JOIN (SELECT event_id, MIN(id) AS id FROM wear_event_action WHERE action='simulate' GROUP BY event_id) first_action ON first_action.event_id=e.id
JOIN wear_event_action a ON a.id=first_action.id
SET e.alarm_code=COALESCE(NULLIF(e.alarm_code,''), NULLIF(JSON_UNQUOTE(JSON_EXTRACT(IF(JSON_VALID(a.reason),a.reason,'{}'),'$.scenarioCode')),'null')),
    e.alarm_name=COALESCE(NULLIF(e.alarm_name,''), NULLIF(JSON_UNQUOTE(JSON_EXTRACT(IF(JSON_VALID(a.reason),a.reason,'{}'),'$.label')),'null')),
    e.alarm_description=COALESCE(NULLIF(e.alarm_description,''), NULLIF(JSON_UNQUOTE(JSON_EXTRACT(IF(JSON_VALID(a.reason),a.reason,'{}'),'$.description')),'null'), NULLIF(JSON_UNQUOTE(JSON_EXTRACT(IF(JSON_VALID(a.reason),a.reason,'{}'),'$.label')),'null'))
WHERE e.source='simulator' AND e.demo=1
  AND JSON_UNQUOTE(JSON_EXTRACT(IF(JSON_VALID(a.reason),a.reason,'{}'),'$.tool'))='call-lab';
