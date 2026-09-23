-- Apply before deploying the manual SOS backend. No historical events are changed.
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='wear_safety_event' AND column_name='reporter_user_id')=0,
  'ALTER TABLE wear_safety_event ADD COLUMN reporter_user_id BIGINT DEFAULT NULL COMMENT ''Manual SOS reporting account''', 'SELECT 1');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
