-- Run after V016. One existing work task is a group; its inspection items share records.
CREATE TABLE IF NOT EXISTS wear_inspection_item (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 task_id BIGINT NOT NULL,
 title VARCHAR(128) NOT NULL,
 location VARCHAR(200) NOT NULL DEFAULT '',
 instruction VARCHAR(500) NOT NULL DEFAULT '',
 sort_order INT NOT NULL DEFAULT 0,
 KEY idx_inspection_item_task (task_id, sort_order, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS wear_inspection_group (
 task_id BIGINT NOT NULL PRIMARY KEY,
 current_item_id BIGINT DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='wear_inspection_record' AND column_name='item_id')=0,
 'ALTER TABLE wear_inspection_record ADD item_id BIGINT NULL, ADD UNIQUE KEY uk_inspection_item_record (task_id,item_id)', 'SELECT 1');
PREPARE inspection_stmt FROM @ddl; EXECUTE inspection_stmt; DEALLOCATE PREPARE inspection_stmt;
SET @ddl = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='wear_inspection_report' AND column_name='item_id')=0,
 'ALTER TABLE wear_inspection_report ADD item_id BIGINT NULL, ADD KEY idx_inspection_item_report (task_id,item_id)', 'SELECT 1');
PREPARE inspection_stmt FROM @ddl; EXECUTE inspection_stmt; DEALLOCATE PREPARE inspection_stmt;
-- Existing work remains the initial inspection item; do not invent completed work or records.
INSERT INTO wear_inspection_item(task_id,title,location,sort_order)
 SELECT t.id,t.title,COALESCE(s.name,''),1 FROM wear_work_task t LEFT JOIN wear_space s ON s.id=t.space_id
 WHERE t.work_type='patrol' AND NOT EXISTS(SELECT 1 FROM wear_inspection_item i WHERE i.task_id=t.id);
