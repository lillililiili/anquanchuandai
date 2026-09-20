-- Non-destructive migration for existing databases. Safe to run repeatedly.
-- No records are deleted, reassigned, or inferred from the old hat_id column.
SET @page_fix_sql = IF(
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE()
    AND table_name='sys_dept' AND column_name='dept_code') = 0,
  'ALTER TABLE sys_dept ADD COLUMN dept_code varchar(64) DEFAULT NULL AFTER dept_name',
  'SELECT 1');
PREPARE page_fix_stmt FROM @page_fix_sql;
EXECUTE page_fix_stmt;
DEALLOCATE PREPARE page_fix_stmt;

SET @page_fix_sql = IF(
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE()
    AND table_name='electronic_fence_alarm' AND column_name='fence_id') = 0,
  'ALTER TABLE electronic_fence_alarm ADD COLUMN fence_id bigint DEFAULT NULL AFTER hat_id',
  'SELECT 1');
PREPARE page_fix_stmt FROM @page_fix_sql;
EXECUTE page_fix_stmt;
DEALLOCATE PREPARE page_fix_stmt;

SET @page_fix_sql = IF(
  (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE()
    AND table_name='electronic_fence_alarm' AND index_name='idx_fence_alarm_fence_time') = 0,
  'ALTER TABLE electronic_fence_alarm ADD INDEX idx_fence_alarm_fence_time (fence_id, alarm_start_time)',
  'SELECT 1');
PREPARE page_fix_stmt FROM @page_fix_sql;
EXECUTE page_fix_stmt;
DEALLOCATE PREPARE page_fix_stmt;
