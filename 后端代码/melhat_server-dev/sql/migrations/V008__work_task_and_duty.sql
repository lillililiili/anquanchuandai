-- S9: work task, duty handover, event task match columns. Old /todo/tasks untouched.

CREATE TABLE IF NOT EXISTS wear_work_task (
  id                   BIGINT(20)    NOT NULL AUTO_INCREMENT,
  site_id              BIGINT(20)    NOT NULL,
  title                VARCHAR(128)  NOT NULL,
  work_type            VARCHAR(16)   NOT NULL,
  space_id             BIGINT(20)    DEFAULT NULL,
  planned_start        DATETIME      DEFAULT NULL,
  planned_end          DATETIME      DEFAULT NULL,
  actual_start         DATETIME      DEFAULT NULL,
  actual_end           DATETIME      DEFAULT NULL,
  status               VARCHAR(16)   NOT NULL,
  owner_user_id        BIGINT(20)    DEFAULT NULL,
  guardian_person_id   BIGINT(20)    DEFAULT NULL,
  ticket_required      TINYINT(1)    NOT NULL DEFAULT 0,
  ticket_no            VARCHAR(64)   DEFAULT NULL,
  ticket_status        VARCHAR(16)   NOT NULL DEFAULT 'none',
  demo                 TINYINT(1)    NOT NULL DEFAULT 0,
  version              INT(11)       NOT NULL DEFAULT 1,
  create_by            VARCHAR(64)   DEFAULT '',
  create_time          DATETIME      DEFAULT NULL,
  update_by            VARCHAR(64)   DEFAULT '',
  update_time          DATETIME      DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_task_site (site_id, status),
  KEY idx_wear_task_owner (owner_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='最小作业任务';

CREATE TABLE IF NOT EXISTS wear_work_task_member (
  id          BIGINT(20)  NOT NULL AUTO_INCREMENT,
  task_id     BIGINT(20)  NOT NULL,
  person_id   BIGINT(20)  NOT NULL,
  create_time DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_task_member (task_id, person_id),
  KEY idx_wear_task_member_person (person_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='作业任务成员';

CREATE TABLE IF NOT EXISTS wear_work_task_requirement (
  id          BIGINT(20)  NOT NULL AUTO_INCREMENT,
  task_id     BIGINT(20)  NOT NULL,
  type_code   VARCHAR(32) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_task_req (task_id, type_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='作业装备要求';

CREATE TABLE IF NOT EXISTS wear_work_task_action (
  id           BIGINT(20)   NOT NULL AUTO_INCREMENT,
  task_id      BIGINT(20)   NOT NULL,
  action       VARCHAR(16)  NOT NULL,
  actor        VARCHAR(64)  NOT NULL DEFAULT '',
  reason       VARCHAR(500) DEFAULT NULL,
  from_status  VARCHAR(16)  DEFAULT NULL,
  to_status    VARCHAR(16)  DEFAULT NULL,
  create_time  DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_task_action (task_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='作业任务动作';

CREATE TABLE IF NOT EXISTS wear_duty_handover (
  id              BIGINT(20)    NOT NULL AUTO_INCREMENT,
  site_id         BIGINT(20)    NOT NULL,
  from_user_id    BIGINT(20)    NOT NULL,
  to_user_id      BIGINT(20)    NOT NULL,
  status          VARCHAR(16)   NOT NULL,
  payload_json    VARCHAR(2000) DEFAULT NULL,
  comment         VARCHAR(500)  DEFAULT NULL,
  confirmed_at    DATETIME      DEFAULT NULL,
  version         INT(11)       NOT NULL DEFAULT 1,
  create_by       VARCHAR(64)   DEFAULT '',
  create_time     DATETIME      DEFAULT NULL,
  update_by       VARCHAR(64)   DEFAULT '',
  update_time     DATETIME      DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_handover_site (site_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='值班交接';

ALTER TABLE wear_safety_event
  ADD COLUMN task_id BIGINT(20) DEFAULT NULL,
  ADD COLUMN task_match VARCHAR(16) NOT NULL DEFAULT 'none';

SET @site_a := (SELECT id FROM wear_site WHERE site_code = 'SITE-DEMO-A' LIMIT 1);
SET @person := (SELECT id FROM wear_person WHERE person_code = 'P-DEMO-001' LIMIT 1);
SET @space := (SELECT id FROM wear_space WHERE name = '东区作业区' AND create_by = 'demo' LIMIT 1);
SET @duty := (SELECT user_id FROM sys_user WHERE user_name = 'siteA_duty' LIMIT 1);

INSERT INTO wear_work_task (site_id, title, work_type, space_id, planned_start, planned_end, actual_start, status,
  owner_user_id, guardian_person_id, ticket_required, ticket_no, ticket_status, demo, version, create_by, create_time)
SELECT @site_a, '东区巡检', 'patrol', @space, DATE_SUB(NOW(), INTERVAL 2 HOUR), DATE_ADD(NOW(), INTERVAL 10 HOUR),
       DATE_SUB(NOW(), INTERVAL 2 HOUR), 'in_progress', @duty, @person, 0, NULL, 'none', 1, 1, 'demo', NOW()
  FROM DUAL
 WHERE @site_a IS NOT NULL AND @duty IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM wear_work_task WHERE title = '东区巡检' AND create_by = 'demo');

INSERT INTO wear_work_task (site_id, title, work_type, space_id, planned_start, planned_end, status,
  owner_user_id, ticket_required, ticket_no, ticket_status, demo, version, create_by, create_time)
SELECT @site_a, '高处待核实票', 'height', @space, DATE_ADD(NOW(), INTERVAL 1 HOUR), DATE_ADD(NOW(), INTERVAL 5 HOUR),
       'draft', @duty, 1, NULL, 'unverified', 1, 1, 'demo', NOW()
  FROM DUAL
 WHERE @site_a IS NOT NULL AND @duty IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM wear_work_task WHERE title = '高处待核实票' AND create_by = 'demo');

INSERT INTO wear_work_task_member (task_id, person_id, create_time)
SELECT t.id, @person, NOW()
  FROM wear_work_task t
 WHERE t.title = '东区巡检' AND t.create_by = 'demo' AND @person IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM wear_work_task_member m WHERE m.task_id = t.id AND m.person_id = @person);

INSERT INTO wear_work_task_requirement (task_id, type_code)
SELECT t.id, 'helmet' FROM wear_work_task t WHERE t.title = '东区巡检' AND t.create_by = 'demo'
  AND NOT EXISTS (SELECT 1 FROM wear_work_task_requirement r WHERE r.task_id = t.id AND r.type_code = 'helmet');
INSERT INTO wear_work_task_requirement (task_id, type_code)
SELECT t.id, 'belt' FROM wear_work_task t WHERE t.title = '东区巡检' AND t.create_by = 'demo'
  AND NOT EXISTS (SELECT 1 FROM wear_work_task_requirement r WHERE r.task_id = t.id AND r.type_code = 'belt');

UPDATE wear_safety_event e
   JOIN wear_work_task t ON t.title = '东区巡检' AND t.create_by = 'demo' AND t.site_id = e.site_id
   SET e.task_id = t.id, e.task_match = 'matched'
 WHERE e.person_id = @person AND e.status <> 'closed' AND e.task_match = 'none'
   AND e.occurred_at BETWEEN t.planned_start AND t.planned_end;

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '值班台', @business_menu_id, 0, 'duty', 'duty/index', '', 1, 0, 'C', '0', '0', 'wear:duty:query', 'dashboard', 'demo', NOW(), 'S9'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'duty');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '作业任务', @business_menu_id, 0, 'work-tasks', 'work-tasks/index', '', 1, 0, 'C', '0', '0', 'wear:task:list', 'job', 'demo', NOW(), 'S9'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'work-tasks');

INSERT IGNORE INTO sys_role_menu (role_id, menu_id)
SELECT r.role_id, m.menu_id
  FROM sys_role r
  JOIN sys_menu m ON m.path IN ('duty', 'work-tasks') AND m.create_by = 'demo'
 WHERE r.role_key IN ('wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
