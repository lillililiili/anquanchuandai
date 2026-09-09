-- S2: person, team, contractor, space. Idempotent enough for the local test db.

CREATE TABLE IF NOT EXISTS wear_contractor (
  id            BIGINT(20)   NOT NULL AUTO_INCREMENT,
  name          VARCHAR(128) NOT NULL,
  status        CHAR(1)      NOT NULL DEFAULT '0' COMMENT '0正常 1停用',
  del_flag      CHAR(1)      NOT NULL DEFAULT '0',
  create_by     VARCHAR(64)  DEFAULT '',
  create_time   DATETIME     DEFAULT NULL,
  update_by     VARCHAR(64)  DEFAULT '',
  update_time   DATETIME     DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='承包商（不是厂站）';

CREATE TABLE IF NOT EXISTS wear_team (
  id            BIGINT(20)   NOT NULL AUTO_INCREMENT,
  site_id       BIGINT(20)   NOT NULL,
  name          VARCHAR(128) NOT NULL,
  status        CHAR(1)      NOT NULL DEFAULT '0',
  del_flag      CHAR(1)      NOT NULL DEFAULT '0',
  create_by     VARCHAR(64)  DEFAULT '',
  create_time   DATETIME     DEFAULT NULL,
  update_by     VARCHAR(64)  DEFAULT '',
  update_time   DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_team_site (site_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='班组（隶属厂站，不是厂站权限）';

CREATE TABLE IF NOT EXISTS wear_person (
  id               BIGINT(20)   NOT NULL AUTO_INCREMENT,
  person_code      VARCHAR(64)  NOT NULL COMMENT '工号/外部标识',
  name             VARCHAR(64)  NOT NULL,
  org_dept_id      BIGINT(20)   DEFAULT NULL COMMENT '若依部门，仅单位',
  team_id          BIGINT(20)   DEFAULT NULL,
  contractor_id    BIGINT(20)   DEFAULT NULL,
  account_user_id  BIGINT(20)   DEFAULT NULL COMMENT '可选登录账号',
  status           CHAR(1)      NOT NULL DEFAULT '0' COMMENT '0在职 1停用',
  valid_from       DATE         DEFAULT NULL,
  valid_to         DATE         DEFAULT NULL,
  version          INT(11)      NOT NULL DEFAULT 1,
  del_flag         CHAR(1)      NOT NULL DEFAULT '0',
  create_by        VARCHAR(64)  DEFAULT '',
  create_time      DATETIME     DEFAULT NULL,
  update_by        VARCHAR(64)  DEFAULT '',
  update_time      DATETIME     DEFAULT NULL,
  remark           VARCHAR(500) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_person_code (person_code),
  UNIQUE KEY uk_wear_person_account (account_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='现场人员，独立于登录账号';

CREATE TABLE IF NOT EXISTS wear_person_site (
  id            BIGINT(20)  NOT NULL AUTO_INCREMENT,
  person_id     BIGINT(20)  NOT NULL,
  site_id       BIGINT(20)  NOT NULL,
  status        CHAR(1)     NOT NULL DEFAULT '0' COMMENT '0有效 1调离',
  create_by     VARCHAR(64) DEFAULT '',
  create_time   DATETIME    DEFAULT NULL,
  update_by     VARCHAR(64) DEFAULT '',
  update_time   DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_person_site (person_id, site_id),
  KEY idx_wear_person_site_site (site_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='人员厂站授权';

CREATE TABLE IF NOT EXISTS wear_space (
  id            BIGINT(20)   NOT NULL AUTO_INCREMENT,
  site_id       BIGINT(20)   NOT NULL,
  parent_id     BIGINT(20)   DEFAULT NULL,
  space_type    VARCHAR(16)  NOT NULL COMMENT 'area/facility/floor',
  name          VARCHAR(128) NOT NULL,
  status        CHAR(1)      NOT NULL DEFAULT '0',
  version       INT(11)      NOT NULL DEFAULT 1,
  del_flag      CHAR(1)      NOT NULL DEFAULT '0',
  create_by     VARCHAR(64)  DEFAULT '',
  create_time   DATETIME     DEFAULT NULL,
  update_by     VARCHAR(64)  DEFAULT '',
  update_time   DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_space_site (site_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='区域资料，非实时定位';

INSERT INTO wear_contractor (name, status, del_flag, create_by, create_time)
SELECT '演示承包商甲', '0', '0', 'demo', NOW()
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM wear_contractor WHERE name = '演示承包商甲' AND create_by = 'demo');

INSERT INTO wear_team (site_id, name, status, del_flag, create_by, create_time)
SELECT s.id, 'A站巡检班', '0', '0', 'demo', NOW()
  FROM wear_site s WHERE s.site_code = 'SITE-DEMO-A'
    AND NOT EXISTS (SELECT 1 FROM wear_team t WHERE t.name = 'A站巡检班' AND t.create_by = 'demo');
INSERT INTO wear_team (site_id, name, status, del_flag, create_by, create_time)
SELECT s.id, 'B站巡检班', '0', '0', 'demo', NOW()
  FROM wear_site s WHERE s.site_code = 'SITE-DEMO-B'
    AND NOT EXISTS (SELECT 1 FROM wear_team t WHERE t.name = 'B站巡检班' AND t.create_by = 'demo');

INSERT INTO wear_person (person_code, name, team_id, contractor_id, account_user_id, status, version, del_flag, create_by, create_time, remark)
SELECT CONCAT('P-DEMO-0', SUBSTRING(u.user_name, 5)), u.nick_name, t.id, NULL, u.user_id, '0', 1, '0', 'demo', NOW(), 'S2 由演示账号映射'
  FROM sys_user u
  JOIN wear_team t ON t.create_by = 'demo' AND (
        (u.user_name IN ('demo01','demo02','demo03') AND t.name = 'A站巡检班')
     OR (u.user_name IN ('demo04','demo05','demo06') AND t.name = 'B站巡检班')
  )
 WHERE u.user_name IN ('demo01','demo02','demo03','demo04','demo05','demo06') AND u.create_by = 'demo'
   AND NOT EXISTS (SELECT 1 FROM wear_person p WHERE p.person_code = CONCAT('P-DEMO-0', SUBSTRING(u.user_name, 5)));

INSERT INTO wear_person (person_code, name, team_id, contractor_id, account_user_id, status, version, del_flag, create_by, create_time, remark)
SELECT 'P-DEMO-NOACCT', '演示人员01', t.id, c.id, NULL, '0', 1, '0', 'demo', NOW(), 'S2 无登录账号，姓名与 P-DEMO-001 重复'
  FROM wear_team t CROSS JOIN wear_contractor c
 WHERE t.name = 'A站巡检班' AND t.create_by = 'demo' AND c.name = '演示承包商甲' AND c.create_by = 'demo'
   AND NOT EXISTS (SELECT 1 FROM wear_person p WHERE p.person_code = 'P-DEMO-NOACCT');

INSERT INTO wear_person (person_code, name, team_id, status, version, del_flag, create_by, create_time, valid_to, remark)
SELECT 'P-DEMO-EXPIRED', '过期人员', t.id, '0', 1, '0', 'demo', NOW(), DATE('2020-01-01'), 'S2 有效期已过，选择器不可选'
  FROM wear_team t WHERE t.name = 'A站巡检班' AND t.create_by = 'demo'
    AND NOT EXISTS (SELECT 1 FROM wear_person p WHERE p.person_code = 'P-DEMO-EXPIRED');

INSERT IGNORE INTO wear_person_site (person_id, site_id, status, create_by, create_time)
SELECT p.id, t.site_id, '0', 'demo', NOW()
  FROM wear_person p JOIN wear_team t ON t.id = p.team_id
 WHERE p.create_by = 'demo';

INSERT INTO wear_space (site_id, parent_id, space_type, name, status, version, del_flag, create_by, create_time)
SELECT s.id, NULL, 'area', '东区作业区', '0', 1, '0', 'demo', NOW()
  FROM wear_site s WHERE s.site_code = 'SITE-DEMO-A'
    AND NOT EXISTS (SELECT 1 FROM wear_space x WHERE x.name = '东区作业区' AND x.create_by = 'demo');
INSERT INTO wear_space (site_id, parent_id, space_type, name, status, version, del_flag, create_by, create_time)
SELECT s.id, NULL, 'area', '循环水泵房', '0', 1, '0', 'demo', NOW()
  FROM wear_site s WHERE s.site_code = 'SITE-DEMO-A'
    AND NOT EXISTS (SELECT 1 FROM wear_space x WHERE x.name = '循环水泵房' AND x.create_by = 'demo');

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '人员', @business_menu_id, 0, 'people', 'people/index', '', 1, 0, 'C', '0', '0', 'wear:person:list', 'user', 'demo', NOW(), 'S2'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'people');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '区域资料', @business_menu_id, 0, 'spaces', 'spaces/index', '', 1, 0, 'C', '0', '0', 'wear:space:list', 'tree', 'demo', NOW(), 'S2'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'spaces');

INSERT IGNORE INTO sys_role_menu (role_id, menu_id)
SELECT r.role_id, m.menu_id
  FROM sys_role r
  JOIN sys_menu m ON m.menu_type IN ('M', 'C')
   AND (m.path = 'business' OR m.parent_id = @business_menu_id)
 WHERE r.role_key IN ('wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
