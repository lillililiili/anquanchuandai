-- S5: unified safety event, actions, inbox, legacy id map. Old alarm tables untouched.

CREATE TABLE IF NOT EXISTS wear_safety_event (
  id                 BIGINT(20)     NOT NULL AUTO_INCREMENT,
  source             VARCHAR(32)    NOT NULL,
  source_event_id    VARCHAR(64)    NOT NULL,
  event_type         VARCHAR(32)    NOT NULL,
  severity           VARCHAR(8)     NOT NULL,
  status             VARCHAR(24)    NOT NULL,
  occurred_at        DATETIME       NOT NULL,
  received_at        DATETIME       NOT NULL,
  person_id          BIGINT(20)     DEFAULT NULL,
  person_code        VARCHAR(64)    DEFAULT NULL,
  person_name        VARCHAR(64)    DEFAULT NULL,
  device_id          BIGINT(20)     DEFAULT NULL,
  sn                 VARCHAR(64)    DEFAULT NULL,
  site_id            BIGINT(20)     NOT NULL,
  location_lat       DECIMAL(10,7)  DEFAULT NULL,
  location_lng       DECIMAL(10,7)  DEFAULT NULL,
  location_quality   VARCHAR(16)    NOT NULL DEFAULT 'unknown',
  claimant_user_id   BIGINT(20)     DEFAULT NULL,
  repeat_count       INT(11)        NOT NULL DEFAULT 0,
  escalated          TINYINT(1)     NOT NULL DEFAULT 0,
  rule_version       VARCHAR(16)    NOT NULL DEFAULT 's5-1',
  demo               TINYINT(1)     NOT NULL DEFAULT 0,
  version            INT(11)        NOT NULL DEFAULT 1,
  create_by          VARCHAR(64)    DEFAULT '',
  create_time        DATETIME       DEFAULT NULL,
  update_by          VARCHAR(64)    DEFAULT '',
  update_time        DATETIME       DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_event_source (source, source_event_id),
  KEY idx_wear_event_site_status (site_id, status, occurred_at),
  KEY idx_wear_event_updated (update_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='统一安全事件';

CREATE TABLE IF NOT EXISTS wear_event_action (
  id           BIGINT(20)   NOT NULL AUTO_INCREMENT,
  event_id     BIGINT(20)   NOT NULL,
  action       VARCHAR(16)  NOT NULL,
  actor        VARCHAR(64)  NOT NULL DEFAULT '',
  reason       VARCHAR(500) DEFAULT NULL,
  from_status  VARCHAR(24)  DEFAULT NULL,
  to_status    VARCHAR(24)  DEFAULT NULL,
  create_time  DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_event_action (event_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='事件处置动作';

CREATE TABLE IF NOT EXISTS wear_event_inbox (
  id          BIGINT(20)  NOT NULL AUTO_INCREMENT,
  user_id     BIGINT(20)  NOT NULL,
  event_id    BIGINT(20)  NOT NULL,
  acked       TINYINT(1)  NOT NULL DEFAULT 0,
  create_time DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_event_inbox (user_id, event_id),
  KEY idx_wear_event_inbox_event (event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='事件通知待办';

CREATE TABLE IF NOT EXISTS wear_event_legacy (
  id          BIGINT(20)  NOT NULL AUTO_INCREMENT,
  source_kind VARCHAR(16) NOT NULL,
  old_id      BIGINT(20)  NOT NULL,
  event_id    BIGINT(20)  NOT NULL,
  create_time DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_event_legacy (source_kind, old_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='旧告警ID映射，S5不切流';

INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, remark)
SELECT NULL, 'siteA_reviewer', 'A站复核员', '00', '', '', '2', '',
       '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'S5 仅厂站A复核'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_user WHERE user_name = 'siteA_reviewer');
INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, remark)
SELECT NULL, 'siteA_team_lead', 'A站班组长', '00', '', '', '2', '',
       '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'S5 仅厂站A班组长'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_user WHERE user_name = 'siteA_team_lead');

INSERT IGNORE INTO sys_user_role (user_id, role_id)
SELECT u.user_id, r.role_id FROM sys_user u JOIN sys_role r ON r.role_key = 'wear_reviewer' WHERE u.user_name = 'siteA_reviewer';
INSERT IGNORE INTO sys_user_role (user_id, role_id)
SELECT u.user_id, r.role_id FROM sys_user u JOIN sys_role r ON r.role_key = 'wear_team_lead' WHERE u.user_name = 'siteA_team_lead';

INSERT IGNORE INTO wear_site_account (site_id, user_id, status, create_by, create_time)
SELECT s.id, u.user_id, '0', 'demo', NOW()
  FROM wear_site s JOIN sys_user u ON u.user_name IN ('siteA_reviewer', 'siteA_team_lead')
 WHERE s.site_code = 'SITE-DEMO-A';

INSERT INTO wear_safety_event (
  source, source_event_id, event_type, severity, status, occurred_at, received_at,
  person_id, person_code, person_name, device_id, sn, site_id,
  location_quality, repeat_count, escalated, rule_version, demo, version, create_by, create_time, update_time)
SELECT 'simulator', 'seed-sos-a', 'sos', 'high', 'open', NOW(), NOW(),
       p.id, p.person_code, p.name, d.id, d.sn, d.site_id,
       'unknown', 0, 0, 's5-1', 1, 1, 'demo', NOW(), NOW()
  FROM wear_person p
  JOIN wear_device d ON d.sn = 'MH-DEMO-001' AND d.manufacturer_code = 'MELHAT'
 WHERE p.person_code = 'P-DEMO-001'
   AND NOT EXISTS (SELECT 1 FROM wear_safety_event e WHERE e.source = 'simulator' AND e.source_event_id = 'seed-sos-a');

INSERT INTO wear_safety_event (
  source, source_event_id, event_type, severity, status, occurred_at, received_at,
  person_id, person_code, person_name, device_id, sn, site_id,
  location_quality, repeat_count, escalated, rule_version, demo, version, create_by, create_time, update_time)
SELECT 'simulator', 'seed-fence-a', 'geofence', 'low', 'open', NOW(), NOW(),
       p.id, p.person_code, p.name, d.id, d.sn, d.site_id,
       'unknown', 0, 0, 's5-1', 1, 1, 'demo', NOW(), NOW()
  FROM wear_person p
  JOIN wear_device d ON d.sn = 'MH-DEMO-001' AND d.manufacturer_code = 'MELHAT'
 WHERE p.person_code = 'P-DEMO-001'
   AND NOT EXISTS (SELECT 1 FROM wear_safety_event e WHERE e.source = 'simulator' AND e.source_event_id = 'seed-fence-a');

INSERT INTO wear_safety_event (
  source, source_event_id, event_type, severity, status, occurred_at, received_at,
  person_id, person_code, person_name, device_id, sn, site_id,
  location_quality, repeat_count, escalated, rule_version, demo, version, create_by, create_time, update_time)
SELECT 'simulator', 'seed-sos-b', 'sos', 'high', 'open', NOW(), NOW(),
       NULL, NULL, NULL, NULL, NULL, s.id,
       'unknown', 0, 0, 's5-1', 1, 1, 'demo', NOW(), NOW()
  FROM wear_site s
 WHERE s.site_code = 'SITE-DEMO-B'
   AND NOT EXISTS (SELECT 1 FROM wear_safety_event e WHERE e.source = 'simulator' AND e.source_event_id = 'seed-sos-b');

INSERT INTO wear_safety_event (
  source, source_event_id, event_type, severity, status, occurred_at, received_at,
  person_id, person_code, person_name, device_id, sn, site_id,
  location_quality, repeat_count, escalated, rule_version, demo, version, create_by, create_time, update_time)
SELECT 'simulator', 'seed-closed-a', 'geofence', 'low', 'closed', DATE_SUB(NOW(), INTERVAL 2 HOUR), DATE_SUB(NOW(), INTERVAL 2 HOUR),
       p.id, p.person_code, p.name, d.id, d.sn, d.site_id,
       'unknown', 0, 0, 's5-1', 1, 1, 'demo', DATE_SUB(NOW(), INTERVAL 2 HOUR), NOW()
  FROM wear_person p
  JOIN wear_device d ON d.sn = 'MH-DEMO-001' AND d.manufacturer_code = 'MELHAT'
 WHERE p.person_code = 'P-DEMO-001'
   AND NOT EXISTS (SELECT 1 FROM wear_safety_event e WHERE e.source = 'simulator' AND e.source_event_id = 'seed-closed-a');

INSERT INTO wear_event_action (event_id, action, actor, reason, from_status, to_status, create_time)
SELECT e.id, 'close', 'demo', 'seed closed', 'handling', 'closed', NOW()
  FROM wear_safety_event e
 WHERE e.source = 'simulator' AND e.source_event_id = 'seed-closed-a'
   AND NOT EXISTS (SELECT 1 FROM wear_event_action a WHERE a.event_id = e.id AND a.action = 'close' AND a.actor = 'demo');

INSERT IGNORE INTO wear_event_inbox (user_id, event_id, acked, create_time)
SELECT a.user_id, e.id, IF(e.status = 'closed', 1, 0), NOW()
  FROM wear_safety_event e
  JOIN wear_site_account a ON a.site_id = e.site_id AND a.status = '0'
 WHERE e.source = 'simulator' AND e.source_event_id IN ('seed-sos-a', 'seed-fence-a', 'seed-sos-b', 'seed-closed-a');

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '安全事件', @business_menu_id, 0, 'events', 'events/index', '', 1, 0, 'C', '0', '0', 'wear:event:list', 'message', 'demo', NOW(), 'S5'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'events');

INSERT IGNORE INTO sys_role_menu (role_id, menu_id)
SELECT r.role_id, m.menu_id
  FROM sys_role r
  JOIN sys_menu m ON m.path = 'events' AND m.create_by = 'demo'
 WHERE r.role_key IN ('wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
