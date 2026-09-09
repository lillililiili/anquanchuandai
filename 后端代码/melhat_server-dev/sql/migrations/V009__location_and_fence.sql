-- S10: person location uses helmet samples; geo fence engine. Old electronic_fence untouched.

CREATE TABLE IF NOT EXISTS wear_geo_fence (
  id                 BIGINT(20)    NOT NULL AUTO_INCREMENT,
  site_id            BIGINT(20)    NOT NULL,
  name               VARCHAR(128)  NOT NULL,
  polygon_json       TEXT          NOT NULL,
  enabled            TINYINT(1)    NOT NULL DEFAULT 1,
  apply_mode         VARCHAR(16)   NOT NULL DEFAULT 'all_site',
  time_start         VARCHAR(8)    DEFAULT NULL,
  time_end           VARCHAR(8)    DEFAULT NULL,
  enter_enabled      TINYINT(1)    NOT NULL DEFAULT 1,
  leave_enabled      TINYINT(1)    NOT NULL DEFAULT 1,
  debounce_seconds   INT(11)       NOT NULL DEFAULT 60,
  rule_version       INT(11)       NOT NULL DEFAULT 1,
  demo               TINYINT(1)    NOT NULL DEFAULT 0,
  version            INT(11)       NOT NULL DEFAULT 1,
  create_by          VARCHAR(64)   DEFAULT '',
  create_time        DATETIME      DEFAULT NULL,
  update_by          VARCHAR(64)   DEFAULT '',
  update_time        DATETIME      DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_fence_site (site_id, enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='平台围栏规则';

CREATE TABLE IF NOT EXISTS wear_geo_fence_person (
  id          BIGINT(20) NOT NULL AUTO_INCREMENT,
  fence_id    BIGINT(20) NOT NULL,
  person_id   BIGINT(20) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_fence_person (fence_id, person_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='围栏适用人员';

CREATE TABLE IF NOT EXISTS wear_geo_fence_state (
  id                 BIGINT(20) NOT NULL AUTO_INCREMENT,
  fence_id           BIGINT(20) NOT NULL,
  person_id          BIGINT(20) NOT NULL,
  inside             TINYINT(1) NOT NULL DEFAULT 0,
  candidate_inside   TINYINT(1) DEFAULT NULL,
  since              DATETIME   DEFAULT NULL,
  last_eval_at       DATETIME   DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_fence_state (fence_id, person_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='围栏进出驻留状态';

SET @db := DATABASE();
SET @sql := (
  SELECT IF(
    COUNT(*) = 0,
    'ALTER TABLE wear_safety_event ADD COLUMN fence_id BIGINT(20) DEFAULT NULL, ADD COLUMN fence_action VARCHAR(16) DEFAULT NULL',
    'SELECT 1'
  )
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'wear_safety_event' AND COLUMN_NAME = 'fence_id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @site_a := (SELECT id FROM wear_site WHERE site_code = 'SITE-DEMO-A' LIMIT 1);
INSERT INTO wear_geo_fence (site_id, name, polygon_json, enabled, apply_mode, enter_enabled, leave_enabled,
  debounce_seconds, rule_version, demo, version, create_by, create_time)
SELECT @site_a, '东区演示围栏',
       '[{"lng":117.10,"lat":36.10},{"lng":117.14,"lat":36.10},{"lng":117.14,"lat":36.14},{"lng":117.10,"lat":36.14}]',
       1, 'all_site', 1, 1, 0, 1, 1, 1, 'demo', NOW()
  FROM DUAL
 WHERE @site_a IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM wear_geo_fence WHERE name = '东区演示围栏' AND create_by = 'demo');

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '人员位置', @business_menu_id, 0, 'locations', 'locations/index', '', 1, 0, 'C', '0', '0', 'wear:location:list', 'guide', 'demo', NOW(), 'S10'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'locations');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '围栏规则', @business_menu_id, 0, 'geo-fences', 'geo-fences/index', '', 1, 0, 'C', '0', '0', 'wear:fence:list', 'international', 'demo', NOW(), 'S10'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'geo-fences');

INSERT IGNORE INTO sys_role_menu (role_id, menu_id)
SELECT r.role_id, m.menu_id
  FROM sys_role r
  JOIN sys_menu m ON m.path IN ('locations', 'geo-fences') AND m.create_by = 'demo'
 WHERE r.role_key IN ('wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
