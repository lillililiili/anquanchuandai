-- S1: physical sites, account grants, hat.site_id
-- Idempotent enough to re-run on the local test database.
-- Demo users share the well-known RuoYi hash for admin123; not a production secret.

SET @exist := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = 'safety_hat_info'
     AND COLUMN_NAME = 'site_id'
);
SET @sql := IF(@exist = 0,
  'ALTER TABLE safety_hat_info ADD COLUMN site_id BIGINT NULL COMMENT ''所属厂站'' AFTER id, ADD KEY idx_hat_site_id (site_id)',
  'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS wear_site (
  id            BIGINT(20)   NOT NULL AUTO_INCREMENT COMMENT '厂站ID',
  site_code     VARCHAR(64)  NOT NULL COMMENT '厂站编码',
  name          VARCHAR(128) NOT NULL COMMENT '厂站名称',
  status        CHAR(1)      NOT NULL DEFAULT '0' COMMENT '0正常 1停用',
  timezone      VARCHAR(64)  NOT NULL DEFAULT 'Asia/Shanghai' COMMENT '显示时区',
  version       INT(11)      NOT NULL DEFAULT 1 COMMENT '乐观锁',
  del_flag      CHAR(1)      NOT NULL DEFAULT '0' COMMENT '0存在 2删除',
  create_by     VARCHAR(64)  DEFAULT '' COMMENT '创建者',
  create_time   DATETIME     DEFAULT NULL COMMENT '创建时间',
  update_by     VARCHAR(64)  DEFAULT '' COMMENT '更新者',
  update_time   DATETIME     DEFAULT NULL COMMENT '更新时间',
  remark        VARCHAR(500) DEFAULT NULL COMMENT '备注',
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_site_code (site_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='物理厂站';

CREATE TABLE IF NOT EXISTS wear_site_account (
  id            BIGINT(20)   NOT NULL AUTO_INCREMENT COMMENT '授权ID',
  site_id       BIGINT(20)   NOT NULL COMMENT '厂站ID',
  user_id       BIGINT(20)   NOT NULL COMMENT '登录账号',
  status        CHAR(1)      NOT NULL DEFAULT '0' COMMENT '0有效 1撤销',
  create_by     VARCHAR(64)  DEFAULT '' COMMENT '创建者',
  create_time   DATETIME     DEFAULT NULL COMMENT '创建时间',
  update_by     VARCHAR(64)  DEFAULT '' COMMENT '更新者',
  update_time   DATETIME     DEFAULT NULL COMMENT '更新时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_site_user (site_id, user_id),
  KEY idx_wear_site_account_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='账号厂站授权';

INSERT INTO sys_role (role_id, role_name, role_key, role_sort, data_scope, menu_check_strictly, dept_check_strictly, status, del_flag, create_by, create_time, remark)
SELECT 201, '平台管理员', 'wear_platform_admin', 21, '1', 1, 1, '0', '0', 'demo', NOW(), 'S1 智能穿戴角色'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_role WHERE role_key = 'wear_platform_admin');
INSERT INTO sys_role (role_id, role_name, role_key, role_sort, data_scope, menu_check_strictly, dept_check_strictly, status, del_flag, create_by, create_time, remark)
SELECT 202, '设备管理员', 'wear_device_admin', 22, '1', 1, 1, '0', '0', 'demo', NOW(), 'S1 智能穿戴角色'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_role WHERE role_key = 'wear_device_admin');
INSERT INTO sys_role (role_id, role_name, role_key, role_sort, data_scope, menu_check_strictly, dept_check_strictly, status, del_flag, create_by, create_time, remark)
SELECT 203, '值班员', 'wear_duty', 23, '1', 1, 1, '0', '0', 'demo', NOW(), 'S1 智能穿戴角色'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_role WHERE role_key = 'wear_duty');
INSERT INTO sys_role (role_id, role_name, role_key, role_sort, data_scope, menu_check_strictly, dept_check_strictly, status, del_flag, create_by, create_time, remark)
SELECT 204, '安全复核员', 'wear_reviewer', 24, '1', 1, 1, '0', '0', 'demo', NOW(), 'S1 智能穿戴角色'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_role WHERE role_key = 'wear_reviewer');
INSERT INTO sys_role (role_id, role_name, role_key, role_sort, data_scope, menu_check_strictly, dept_check_strictly, status, del_flag, create_by, create_time, remark)
SELECT 205, '班组长', 'wear_team_lead', 25, '1', 1, 1, '0', '0', 'demo', NOW(), 'S1 智能穿戴角色'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_role WHERE role_key = 'wear_team_lead');
INSERT INTO sys_role (role_id, role_name, role_key, role_sort, data_scope, menu_check_strictly, dept_check_strictly, status, del_flag, create_by, create_time, remark)
SELECT 206, '只读', 'wear_readonly', 26, '1', 1, 1, '0', '0', 'demo', NOW(), 'S1 智能穿戴角色'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_role WHERE role_key = 'wear_readonly');

INSERT INTO wear_site (site_code, name, status, timezone, version, del_flag, create_by, create_time, remark)
SELECT 'SITE-DEMO-A', '演示厂站A', '0', 'Asia/Shanghai', 1, '0', 'demo', NOW(), 'S1 反向权限测试'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM wear_site WHERE site_code = 'SITE-DEMO-A');
INSERT INTO wear_site (site_code, name, status, timezone, version, del_flag, create_by, create_time, remark)
SELECT 'SITE-DEMO-B', '演示厂站B', '0', 'Asia/Shanghai', 1, '0', 'demo', NOW(), 'S1 反向权限测试'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM wear_site WHERE site_code = 'SITE-DEMO-B');

INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, remark)
SELECT NULL, 'wear_admin', '穿戴平台管理员', '00', '', '', '2', '',
       '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'S1 两站管理员'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_user WHERE user_name = 'wear_admin');
INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, remark)
SELECT NULL, 'siteA_duty', 'A站值班员', '00', '', '', '2', '',
       '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'S1 仅厂站A'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_user WHERE user_name = 'siteA_duty');
INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, remark)
SELECT NULL, 'siteB_duty', 'B站值班员', '00', '', '', '2', '',
       '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'S1 仅厂站B'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_user WHERE user_name = 'siteB_duty');
INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, remark)
SELECT NULL, 'siteA_readonly', 'A站只读', '00', '', '', '2', '',
       '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'S1 仅厂站A只读'
  FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_user WHERE user_name = 'siteA_readonly');

INSERT IGNORE INTO sys_user_role (user_id, role_id)
SELECT u.user_id, r.role_id FROM sys_user u JOIN sys_role r ON r.role_key = 'wear_platform_admin' WHERE u.user_name = 'wear_admin';
INSERT IGNORE INTO sys_user_role (user_id, role_id)
SELECT u.user_id, r.role_id FROM sys_user u JOIN sys_role r ON r.role_key = 'wear_duty' WHERE u.user_name = 'siteA_duty';
INSERT IGNORE INTO sys_user_role (user_id, role_id)
SELECT u.user_id, r.role_id FROM sys_user u JOIN sys_role r ON r.role_key = 'wear_duty' WHERE u.user_name = 'siteB_duty';
INSERT IGNORE INTO sys_user_role (user_id, role_id)
SELECT u.user_id, r.role_id FROM sys_user u JOIN sys_role r ON r.role_key = 'wear_readonly' WHERE u.user_name = 'siteA_readonly';

INSERT IGNORE INTO wear_site_account (site_id, user_id, status, create_by, create_time)
SELECT s.id, u.user_id, '0', 'demo', NOW()
  FROM wear_site s CROSS JOIN sys_user u
 WHERE s.site_code IN ('SITE-DEMO-A', 'SITE-DEMO-B')
   AND u.user_name IN ('wear_admin', 'admin');

INSERT IGNORE INTO wear_site_account (site_id, user_id, status, create_by, create_time)
SELECT s.id, u.user_id, '0', 'demo', NOW()
  FROM wear_site s JOIN sys_user u ON u.user_name IN ('siteA_duty', 'siteA_readonly')
 WHERE s.site_code = 'SITE-DEMO-A';

INSERT IGNORE INTO wear_site_account (site_id, user_id, status, create_by, create_time)
SELECT s.id, u.user_id, '0', 'demo', NOW()
  FROM wear_site s JOIN sys_user u ON u.user_name = 'siteB_duty'
 WHERE s.site_code = 'SITE-DEMO-B';

UPDATE safety_hat_info h
   JOIN wear_site s ON s.site_code = 'SITE-DEMO-A'
   SET h.site_id = s.id
 WHERE h.hat_number IN ('MH-DEMO-001', 'MH-DEMO-002', 'MH-DEMO-003')
   AND h.create_by = 'demo';

UPDATE safety_hat_info h
   JOIN wear_site s ON s.site_code = 'SITE-DEMO-B'
   SET h.site_id = s.id
 WHERE h.hat_number IN ('MH-DEMO-004', 'MH-DEMO-005', 'MH-DEMO-006')
   AND h.create_by = 'demo';
