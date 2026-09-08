-- 分体式智能安全帽平台离线演示数据初始化脚本（MySQL 8）
-- 仅清理 create_by='demo' 的业务种子及 business_key 以 demo- 开头的兼容种子。

CREATE TABLE IF NOT EXISTS group_info (
  id bigint NOT NULL AUTO_INCREMENT,
  group_name varchar(100) NOT NULL,
  group_desc varchar(500) DEFAULT NULL,
  safety_count int DEFAULT 0,
  del_flag char(1) DEFAULT '0',
  create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_group_name (group_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS safety_hat_info (
  id bigint NOT NULL AUTO_INCREMENT,
  hat_number varchar(64) NOT NULL,
  bind_user_id bigint DEFAULT NULL, bind_user_name varchar(64) DEFAULT NULL,
  bind_group_id bigint DEFAULT NULL, bind_group varchar(100) DEFAULT NULL,
  bind_time datetime DEFAULT NULL, status varchar(20) DEFAULT 'offline',
  cpu_usage decimal(10,2) DEFAULT 0, storage_usage decimal(10,2) DEFAULT 0,
  electricity_usage decimal(10,2) DEFAULT 0, alarm_count int DEFAULT 0,
  video_url varchar(500) DEFAULT NULL, rtc_play_config text, uid varchar(64) DEFAULT NULL,
  del_flag char(1) DEFAULT '0',
  create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), UNIQUE KEY uk_hat_number (hat_number),
  KEY idx_hat_user (bind_user_id), KEY idx_hat_group (bind_group_id), KEY idx_hat_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS safety_hat_location_record (
  id bigint NOT NULL AUTO_INCREMENT,
  hat_id bigint NOT NULL, hat_number varchar(64) NOT NULL,
  user_id bigint DEFAULT NULL, user_name varchar(64) DEFAULT NULL,
  lng varchar(32) DEFAULT NULL, lat varchar(32) DEFAULT NULL,
  speed varchar(32) DEFAULT NULL, `timestamp` varchar(32) DEFAULT NULL, altitude varchar(32) DEFAULT NULL,
  del_flag int DEFAULT 0,
  create_time datetime DEFAULT NULL, create_by varchar(64) DEFAULT '',
  update_time datetime DEFAULT NULL, update_by varchar(64) DEFAULT '',
  PRIMARY KEY (id), KEY idx_location_hat_time (hat_id, `timestamp`), KEY idx_location_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS electronic_fence (
  id bigint NOT NULL AUTO_INCREMENT,
  fence_name varchar(100) NOT NULL, fence_type varchar(32) DEFAULT NULL, fence_shape varchar(16) DEFAULT '0',
  alert_count int DEFAULT 0, status int DEFAULT 1, del_flag char(1) DEFAULT '0',
  create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_fence_name (fence_name), KEY idx_fence_type_status (fence_type, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS electronic_fence_latitude (
  id bigint NOT NULL AUTO_INCREMENT, fence_id bigint NOT NULL,
  longitude decimal(10,6) DEFAULT NULL, latitude decimal(10,6) DEFAULT NULL,
  create_time datetime DEFAULT NULL, update_time datetime DEFAULT NULL, del_flag int DEFAULT 0,
  create_by varchar(64) DEFAULT '', update_by varchar(64) DEFAULT '',
  PRIMARY KEY (id), KEY idx_fence_latitude_fence (fence_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS electronic_fence_alarm (
  id bigint NOT NULL AUTO_INCREMENT,
  user_id bigint DEFAULT NULL, user_name varchar(64) DEFAULT NULL,
  hat_number varchar(64) DEFAULT NULL, hat_id bigint DEFAULT NULL, fence_id bigint DEFAULT NULL, alarm_type varchar(32) DEFAULT NULL,
  alarm_start_time datetime DEFAULT NULL, alarm_end_time datetime DEFAULT NULL,
  description varchar(1000) DEFAULT NULL, is_handled int DEFAULT 0, handle_time datetime DEFAULT NULL,
  del_flag char(1) DEFAULT '0', create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_fence_alarm_hat_time (hat_id, alarm_start_time), KEY idx_fence_alarm_fence_time (fence_id, alarm_start_time),
  KEY idx_fence_alarm_user (user_id), KEY idx_fence_alarm_type_handled (alarm_type, is_handled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 兼容已由首版演示脚本创建的表：仅在缺列/缺索引时迁移，重复执行无副作用。
-- 当前后端的部门树查询要求 dept_code；旧库可能尚未迁移该字段。
SET @sys_dept_has_dept_code := (
  SELECT COUNT(*) FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'sys_dept' AND column_name = 'dept_code'
);
SET @sys_dept_add_dept_code_sql := IF(
  @sys_dept_has_dept_code = 0,
  'ALTER TABLE sys_dept ADD COLUMN dept_code varchar(64) DEFAULT NULL AFTER dept_name',
  'SET @sys_dept_dept_code_migration_noop = 1'
);
PREPARE sys_dept_dept_code_stmt FROM @sys_dept_add_dept_code_sql;
EXECUTE sys_dept_dept_code_stmt;
DEALLOCATE PREPARE sys_dept_dept_code_stmt;

UPDATE sys_dept
SET dept_code = CONCAT('DEPT-', dept_id)
WHERE del_flag = '0' AND (dept_code IS NULL OR dept_code = '');

SET @sys_dept_has_dept_code_index := (
  SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'sys_dept' AND index_name = 'uk_sys_dept_dept_code'
);
-- 不改写既有非空编码；旧库若已有重复编码，保留原数据并跳过唯一索引，保证重复导入不失败。
SET @sys_dept_has_duplicate_dept_code := (
  SELECT COUNT(*) FROM (
    SELECT dept_code
    FROM sys_dept
    WHERE dept_code IS NOT NULL AND dept_code <> ''
    GROUP BY dept_code
    HAVING COUNT(*) > 1
  ) AS duplicate_dept_codes
);
SET @sys_dept_add_dept_code_index_sql := IF(
  @sys_dept_has_dept_code_index = 0 AND @sys_dept_has_duplicate_dept_code = 0,
  'ALTER TABLE sys_dept ADD UNIQUE KEY uk_sys_dept_dept_code (dept_code)',
  'SET @sys_dept_dept_code_index_migration_noop = 1'
);
PREPARE sys_dept_dept_code_index_stmt FROM @sys_dept_add_dept_code_index_sql;
EXECUTE sys_dept_dept_code_index_stmt;
DEALLOCATE PREPARE sys_dept_dept_code_index_stmt;

SET @fence_alarm_has_fence_id := (
  SELECT COUNT(*) FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'electronic_fence_alarm' AND column_name = 'fence_id'
);
SET @fence_alarm_add_fence_id_sql := IF(
  @fence_alarm_has_fence_id = 0,
  'ALTER TABLE electronic_fence_alarm ADD COLUMN fence_id bigint DEFAULT NULL AFTER hat_id',
  'SET @fence_alarm_column_migration_noop = 1'
);
PREPARE fence_alarm_column_stmt FROM @fence_alarm_add_fence_id_sql;
EXECUTE fence_alarm_column_stmt;
DEALLOCATE PREPARE fence_alarm_column_stmt;
SET @fence_alarm_has_fence_index := (
  SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'electronic_fence_alarm' AND index_name = 'idx_fence_alarm_fence_time'
);
SET @fence_alarm_add_fence_index_sql := IF(
  @fence_alarm_has_fence_index = 0,
  'ALTER TABLE electronic_fence_alarm ADD KEY idx_fence_alarm_fence_time (fence_id, alarm_start_time)',
  'SET @fence_alarm_index_migration_noop = 1'
);
PREPARE fence_alarm_index_stmt FROM @fence_alarm_add_fence_index_sql;
EXECUTE fence_alarm_index_stmt;
DEALLOCATE PREPARE fence_alarm_index_stmt;

CREATE TABLE IF NOT EXISTS real_time_alarm (
  id bigint NOT NULL AUTO_INCREMENT,
  user_id bigint DEFAULT NULL, user_name varchar(64) DEFAULT NULL,
  hat_number varchar(64) DEFAULT NULL, hat_id bigint DEFAULT NULL,
  alarm_type varchar(32) DEFAULT NULL, alarm_level varchar(16) DEFAULT NULL,
  alarm_start_time datetime DEFAULT NULL, alarm_end_time datetime DEFAULT NULL,
  description varchar(1000) DEFAULT NULL, is_handled int DEFAULT 0, handle_time datetime DEFAULT NULL,
  del_flag char(1) DEFAULT '0', create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_realtime_alarm_hat_time (hat_id, alarm_start_time),
  KEY idx_realtime_alarm_user (user_id), KEY idx_realtime_alarm_handled (is_handled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sos_alarm_record (
  id bigint NOT NULL AUTO_INCREMENT,
  user_id bigint DEFAULT NULL, user_name varchar(64) DEFAULT NULL,
  hat_id bigint DEFAULT NULL, hat_number varchar(64) DEFAULT NULL,
  lng varchar(32) DEFAULT NULL, lat varchar(32) DEFAULT NULL, call_time datetime DEFAULT NULL,
  description varchar(1000) DEFAULT NULL, process_status tinyint DEFAULT 0,
  handler varchar(64) DEFAULT NULL, handle_time datetime DEFAULT NULL,
  del_flag char(1) DEFAULT '0', create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_sos_hat_time (hat_id, call_time), KEY idx_sos_user (user_id), KEY idx_sos_process (process_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS file_record (
  id bigint NOT NULL AUTO_INCREMENT,
  file_name varchar(255) NOT NULL, file_type varchar(32) DEFAULT NULL, file_url varchar(500) DEFAULT NULL,
  hat_id bigint DEFAULT NULL, hat_number varchar(64) DEFAULT NULL, user_name varchar(64) DEFAULT NULL,
  file_size decimal(10,2) DEFAULT 0, upload_time datetime DEFAULT NULL,
  del_flag char(1) DEFAULT '0', create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_file_hat_upload (hat_id, upload_time), KEY idx_file_type_upload (file_type, upload_time), KEY idx_file_name (file_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS intercom_record (
  id bigint NOT NULL AUTO_INCREMENT,
  intercom_type varchar(16) DEFAULT NULL, hat_number varchar(500) DEFAULT NULL, participant varchar(500) DEFAULT NULL,
  recipient_count int DEFAULT 0, start_time datetime DEFAULT NULL, end_time datetime DEFAULT NULL,
  duration varchar(32) DEFAULT NULL, record_path varchar(500) DEFAULT NULL,
  del_flag char(1) DEFAULT '0', create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_intercom_type_time (intercom_type, start_time), KEY idx_intercom_start_time (start_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS tts_text_synthesis_broadcast (
  id bigint NOT NULL AUTO_INCREMENT,
  broadcast_type varchar(16) DEFAULT NULL, hat_number varchar(500) DEFAULT NULL, recipient varchar(500) DEFAULT NULL,
  recipient_count int DEFAULT 0, send_time datetime DEFAULT NULL, content text, operator varchar(64) DEFAULT NULL,
  del_flag char(1) DEFAULT '0', create_by varchar(64) DEFAULT '', create_time datetime DEFAULT NULL,
  update_by varchar(64) DEFAULT '', update_time datetime DEFAULT NULL,
  PRIMARY KEY (id), KEY idx_tts_type_time (broadcast_type, send_time), KEY idx_tts_send_time (send_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS demo_compat_record (
  id bigint NOT NULL AUTO_INCREMENT,
  module_key varchar(40) NOT NULL,
  business_key varchar(80) NOT NULL,
  payload json NOT NULL,
  create_time datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  update_time datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id), UNIQUE KEY uk_demo_module_business (module_key, business_key),
  KEY idx_demo_module (module_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

START TRANSACTION;

-- 先删除子记录，范围严格限制为本脚本 create_by='demo' 的种子。
DELETE FROM safety_hat_location_record WHERE create_by = 'demo';
DELETE FROM electronic_fence_latitude WHERE create_by = 'demo';
DELETE FROM electronic_fence_alarm WHERE create_by = 'demo';
DELETE FROM real_time_alarm WHERE create_by = 'demo';
DELETE FROM sos_alarm_record WHERE create_by = 'demo';
DELETE FROM file_record WHERE create_by = 'demo';
DELETE FROM intercom_record WHERE create_by = 'demo';
DELETE FROM tts_text_synthesis_broadcast WHERE create_by = 'demo';
DELETE FROM safety_hat_info WHERE create_by = 'demo';
DELETE FROM electronic_fence WHERE create_by = 'demo';
DELETE FROM group_info WHERE create_by = 'demo';
DELETE FROM demo_compat_record
 WHERE module_key IN ('space', 'module', 'headBand', 'systemHat') AND business_key LIKE 'demo-%';
DELETE FROM sys_user_role
 WHERE user_id IN (SELECT user_id FROM (SELECT user_id FROM sys_user WHERE create_by = 'demo') AS demo_users);
DELETE FROM sys_user WHERE create_by = 'demo';

INSERT INTO group_info (group_name, group_desc, safety_count, del_flag, create_by, create_time, update_by, update_time) VALUES
('巡检一组', '演示：厂区东侧日常巡检', 2, '0', 'demo', NOW(), 'demo', NOW()),
('巡检二组', '演示：厂区西侧日常巡检', 2, '0', 'demo', NOW(), 'demo', NOW()),
('应急保障组', '演示：应急处置与后勤保障', 2, '0', 'demo', NOW(), 'demo', NOW());

INSERT INTO sys_user (dept_id, user_name, nick_name, user_type, email, phonenumber, sex, avatar, password, status, del_flag, create_by, create_time, update_by, update_time, remark) VALUES
(NULL, 'demo01', '演示人员01', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo02', '演示人员02', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo03', '演示人员03', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo04', '演示人员04', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo05', '演示人员05', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo06', '演示人员06', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo07', '演示人员07', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员'),
(NULL, 'demo08', '演示人员08', '00', '', '', '2', '', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '0', '0', 'demo', NOW(), 'demo', NOW(), '离线演示虚构人员');

INSERT INTO safety_hat_info (hat_number, bind_user_id, bind_user_name, bind_group_id, bind_group, bind_time, status, cpu_usage, storage_usage, electricity_usage, alarm_count, video_url, rtc_play_config, uid, del_flag, create_by, create_time, update_by, update_time)
SELECT 'MH-DEMO-001', u.user_id, u.nick_name, g.id, g.group_name, NOW(), '1', 24.50, 31.20, 86.00, 1, 'demo://video/MH-DEMO-001', '{"demo":true}', 'demo-uid-001', '0', 'demo', NOW(), 'demo', NOW() FROM sys_user u CROSS JOIN group_info g WHERE u.user_name = 'demo01' AND u.create_by = 'demo' AND g.group_name = '巡检一组' AND g.create_by = 'demo';
INSERT INTO safety_hat_info (hat_number, bind_user_id, bind_user_name, bind_group_id, bind_group, bind_time, status, cpu_usage, storage_usage, electricity_usage, alarm_count, video_url, rtc_play_config, uid, del_flag, create_by, create_time, update_by, update_time)
SELECT 'MH-DEMO-002', u.user_id, u.nick_name, g.id, g.group_name, NOW(), '1', 32.10, 43.80, 72.00, 2, 'demo://video/MH-DEMO-002', '{"demo":true}', 'demo-uid-002', '0', 'demo', NOW(), 'demo', NOW() FROM sys_user u CROSS JOIN group_info g WHERE u.user_name = 'demo02' AND u.create_by = 'demo' AND g.group_name = '巡检一组' AND g.create_by = 'demo';
INSERT INTO safety_hat_info (hat_number, bind_user_id, bind_user_name, bind_group_id, bind_group, bind_time, status, cpu_usage, storage_usage, electricity_usage, alarm_count, video_url, rtc_play_config, uid, del_flag, create_by, create_time, update_by, update_time)
SELECT 'MH-DEMO-003', u.user_id, u.nick_name, g.id, g.group_name, NOW(), '1', 19.80, 27.60, 64.00, 1, 'demo://video/MH-DEMO-003', '{"demo":true}', 'demo-uid-003', '0', 'demo', NOW(), 'demo', NOW() FROM sys_user u CROSS JOIN group_info g WHERE u.user_name = 'demo03' AND u.create_by = 'demo' AND g.group_name = '巡检二组' AND g.create_by = 'demo';
INSERT INTO safety_hat_info (hat_number, bind_user_id, bind_user_name, bind_group_id, bind_group, bind_time, status, cpu_usage, storage_usage, electricity_usage, alarm_count, video_url, rtc_play_config, uid, del_flag, create_by, create_time, update_by, update_time)
SELECT 'MH-DEMO-004', u.user_id, u.nick_name, g.id, g.group_name, NOW(), '1', 41.30, 38.40, 55.00, 3, 'demo://video/MH-DEMO-004', '{"demo":true}', 'demo-uid-004', '0', 'demo', NOW(), 'demo', NOW() FROM sys_user u CROSS JOIN group_info g WHERE u.user_name = 'demo04' AND u.create_by = 'demo' AND g.group_name = '巡检二组' AND g.create_by = 'demo';
INSERT INTO safety_hat_info (hat_number, bind_user_id, bind_user_name, bind_group_id, bind_group, bind_time, status, cpu_usage, storage_usage, electricity_usage, alarm_count, video_url, rtc_play_config, uid, del_flag, create_by, create_time, update_by, update_time)
SELECT 'MH-DEMO-005', u.user_id, u.nick_name, g.id, g.group_name, NOW(), '0', 8.20, 61.00, 18.00, 0, 'demo://video/MH-DEMO-005', '{"demo":true}', 'demo-uid-005', '0', 'demo', NOW(), 'demo', NOW() FROM sys_user u CROSS JOIN group_info g WHERE u.user_name = 'demo05' AND u.create_by = 'demo' AND g.group_name = '应急保障组' AND g.create_by = 'demo';
INSERT INTO safety_hat_info (hat_number, bind_user_id, bind_user_name, bind_group_id, bind_group, bind_time, status, cpu_usage, storage_usage, electricity_usage, alarm_count, video_url, rtc_play_config, uid, del_flag, create_by, create_time, update_by, update_time)
SELECT 'MH-DEMO-006', u.user_id, u.nick_name, g.id, g.group_name, NOW(), '0', 5.10, 48.20, 9.00, 0, 'demo://video/MH-DEMO-006', '{"demo":true}', 'demo-uid-006', '0', 'demo', NOW(), 'demo', NOW() FROM sys_user u CROSS JOIN group_info g WHERE u.user_name = 'demo06' AND u.create_by = 'demo' AND g.group_name = '应急保障组' AND g.create_by = 'demo';

INSERT INTO safety_hat_location_record (hat_id, hat_number, user_id, user_name, lng, lat, speed, `timestamp`, altitude, del_flag, create_time, create_by, update_time, update_by)
SELECT h.id, h.hat_number, h.bind_user_id, h.bind_user_name,
       CAST(ROUND(117.120000 + (CASE h.hat_number WHEN 'MH-DEMO-001' THEN 0.0000 WHEN 'MH-DEMO-002' THEN 0.0100 WHEN 'MH-DEMO-003' THEN 0.0200 ELSE 0.0300 END) + p.seq * 0.0003, 6) AS CHAR),
       CAST(ROUND(36.650000 + (CASE h.hat_number WHEN 'MH-DEMO-001' THEN 0.0000 WHEN 'MH-DEMO-002' THEN 0.0100 WHEN 'MH-DEMO-003' THEN 0.0200 ELSE 0.0300 END) + p.seq * 0.0002, 6) AS CHAR),
       CAST(2 + p.seq AS CHAR), DATE_FORMAT(DATE_SUB(NOW(), INTERVAL (13 - p.seq) * 5 MINUTE), '%Y-%m-%d %H:%i:%s'),
       CAST(112 + p.seq AS CHAR), 0, NOW(), 'demo', NOW(), 'demo'
  FROM safety_hat_info h
 CROSS JOIN (SELECT 1 seq UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12) p
 WHERE h.create_by = 'demo' AND h.status = '1';

INSERT INTO electronic_fence (fence_name, fence_type, fence_shape, alert_count, status, del_flag, create_by, create_time, update_by, update_time) VALUES
('东侧设备禁入区', '1', '0', 1, 1, '0', 'demo', NOW(), 'demo', NOW()),
('西侧高压警戒区', '2', '0', 1, 1, '0', 'demo', NOW(), 'demo', NOW()),
('仓储作业缓冲区', '1', '0', 1, 1, '0', 'demo', NOW(), 'demo', NOW());

INSERT INTO electronic_fence_latitude (fence_id, longitude, latitude, create_time, update_time, del_flag, create_by, update_by)
SELECT f.id, p.longitude, p.latitude, NOW(), NOW(), 0, 'demo', 'demo'
  FROM electronic_fence f
 CROSS JOIN (SELECT 117.120100 longitude, 36.650100 latitude UNION ALL SELECT 117.123100, 36.650100 UNION ALL SELECT 117.123100, 36.653100 UNION ALL SELECT 117.120100, 36.653100) p
 WHERE f.create_by = 'demo' AND f.fence_name = '东侧设备禁入区';
INSERT INTO electronic_fence_latitude (fence_id, longitude, latitude, create_time, update_time, del_flag, create_by, update_by)
SELECT f.id, p.longitude, p.latitude, NOW(), NOW(), 0, 'demo', 'demo'
  FROM electronic_fence f
 CROSS JOIN (SELECT 117.140100 longitude, 36.670100 latitude UNION ALL SELECT 117.143100, 36.670100 UNION ALL SELECT 117.143100, 36.673100 UNION ALL SELECT 117.140100, 36.673100) p
 WHERE f.create_by = 'demo' AND f.fence_name = '西侧高压警戒区';
INSERT INTO electronic_fence_latitude (fence_id, longitude, latitude, create_time, update_time, del_flag, create_by, update_by)
SELECT f.id, p.longitude, p.latitude, NOW(), NOW(), 0, 'demo', 'demo'
  FROM electronic_fence f
 CROSS JOIN (SELECT 117.160100 longitude, 36.640100 latitude UNION ALL SELECT 117.163100, 36.640100 UNION ALL SELECT 117.163100, 36.643100 UNION ALL SELECT 117.160100, 36.643100) p
 WHERE f.create_by = 'demo' AND f.fence_name = '仓储作业缓冲区';

INSERT INTO real_time_alarm (user_id, user_name, hat_number, hat_id, alarm_type, alarm_level, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, hat_number, id, 'proximity', '高', DATE_SUB(NOW(), INTERVAL 45 MINUTE), NULL, '演示：接近高压区域告警', 0, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-001' AND create_by = 'demo';
INSERT INTO real_time_alarm (user_id, user_name, hat_number, hat_id, alarm_type, alarm_level, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, hat_number, id, 'removal', '中', DATE_SUB(NOW(), INTERVAL 90 MINUTE), DATE_SUB(NOW(), INTERVAL 80 MINUTE), '演示：脱帽告警已确认', 1, DATE_SUB(NOW(), INTERVAL 78 MINUTE), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-002' AND create_by = 'demo';
INSERT INTO real_time_alarm (user_id, user_name, hat_number, hat_id, alarm_type, alarm_level, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, hat_number, id, 'fall', '高', DATE_SUB(NOW(), INTERVAL 150 MINUTE), NULL, '演示：跌倒风险告警待处置', 0, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-003' AND create_by = 'demo';
INSERT INTO real_time_alarm (user_id, user_name, hat_number, hat_id, alarm_type, alarm_level, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, hat_number, id, 'sos', '高', DATE_SUB(NOW(), INTERVAL 20 MINUTE), NULL, '演示：SOS 紧急求助待处置', 0, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-004' AND create_by = 'demo';

INSERT INTO electronic_fence_alarm (user_id, user_name, hat_number, hat_id, fence_id, alarm_type, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT h.bind_user_id, h.bind_user_name, h.hat_number, h.id, f.id, '1', DATE_SUB(NOW(), INTERVAL 35 MINUTE), NULL, '演示：进入东侧设备禁入区', 0, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h CROSS JOIN electronic_fence f WHERE h.hat_number = 'MH-DEMO-001' AND h.create_by = 'demo' AND f.fence_name = '东侧设备禁入区' AND f.create_by = 'demo';
INSERT INTO electronic_fence_alarm (user_id, user_name, hat_number, hat_id, fence_id, alarm_type, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT h.bind_user_id, h.bind_user_name, h.hat_number, h.id, f.id, '2', DATE_SUB(NOW(), INTERVAL 115 MINUTE), DATE_SUB(NOW(), INTERVAL 105 MINUTE), '演示：离开西侧高压警戒区', 1, DATE_SUB(NOW(), INTERVAL 104 MINUTE), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h CROSS JOIN electronic_fence f WHERE h.hat_number = 'MH-DEMO-002' AND h.create_by = 'demo' AND f.fence_name = '西侧高压警戒区' AND f.create_by = 'demo';
INSERT INTO electronic_fence_alarm (user_id, user_name, hat_number, hat_id, fence_id, alarm_type, alarm_start_time, alarm_end_time, description, is_handled, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT h.bind_user_id, h.bind_user_name, h.hat_number, h.id, f.id, '1', DATE_SUB(NOW(), INTERVAL 185 MINUTE), NULL, '演示：仓储缓冲区越界', 0, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h CROSS JOIN electronic_fence f WHERE h.hat_number = 'MH-DEMO-003' AND h.create_by = 'demo' AND f.fence_name = '仓储作业缓冲区' AND f.create_by = 'demo';

INSERT INTO sos_alarm_record (user_id, user_name, hat_id, hat_number, lng, lat, call_time, description, process_status, handler, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, id, hat_number, '117.120800', '36.650600', DATE_SUB(NOW(), INTERVAL 25 MINUTE), '演示：现场需要协助', 0, NULL, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-001' AND create_by = 'demo';
INSERT INTO sos_alarm_record (user_id, user_name, hat_id, hat_number, lng, lat, call_time, description, process_status, handler, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, id, hat_number, '117.136200', '36.665200', DATE_SUB(NOW(), INTERVAL 55 MINUTE), '演示：应急通道需要支援', 0, NULL, NULL, '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-004' AND create_by = 'demo';
INSERT INTO sos_alarm_record (user_id, user_name, hat_id, hat_number, lng, lat, call_time, description, process_status, handler, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, id, hat_number, '117.130600', '36.660400', DATE_SUB(NOW(), INTERVAL 130 MINUTE), '演示：物资补给请求', 1, '演示调度', DATE_SUB(NOW(), INTERVAL 118 MINUTE), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-002' AND create_by = 'demo';
INSERT INTO sos_alarm_record (user_id, user_name, hat_id, hat_number, lng, lat, call_time, description, process_status, handler, handle_time, del_flag, create_by, create_time, update_by, update_time)
SELECT bind_user_id, bind_user_name, id, hat_number, '117.140400', '36.670800', DATE_SUB(NOW(), INTERVAL 210 MINUTE), '演示：发现设备异常', 1, '演示调度', DATE_SUB(NOW(), INTERVAL 198 MINUTE), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info WHERE hat_number = 'MH-DEMO-003' AND create_by = 'demo';

INSERT INTO file_record (file_name, file_type, file_url, hat_id, hat_number, user_name, file_size, upload_time, del_flag, create_by, create_time, update_by, update_time)
SELECT CONCAT('演示巡检影像-', h.hat_number, '.mp4'), 'video', CONCAT('demo://file/', h.hat_number, '/inspection.mp4'), h.id, h.hat_number, h.bind_user_name, 24.50, DATE_SUB(NOW(), INTERVAL 1 HOUR), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-001' AND h.create_by = 'demo';
INSERT INTO file_record (file_name, file_type, file_url, hat_id, hat_number, user_name, file_size, upload_time, del_flag, create_by, create_time, update_by, update_time)
SELECT CONCAT('演示设备照片-', h.hat_number, '.jpg'), 'image', CONCAT('demo://file/', h.hat_number, '/device.jpg'), h.id, h.hat_number, h.bind_user_name, 3.20, DATE_SUB(NOW(), INTERVAL 2 HOUR), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-002' AND h.create_by = 'demo';
INSERT INTO file_record (file_name, file_type, file_url, hat_id, hat_number, user_name, file_size, upload_time, del_flag, create_by, create_time, update_by, update_time)
SELECT CONCAT('演示语音记录-', h.hat_number, '.mp3'), 'audio', CONCAT('demo://file/', h.hat_number, '/voice.mp3'), h.id, h.hat_number, h.bind_user_name, 1.80, DATE_SUB(NOW(), INTERVAL 3 HOUR), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-003' AND h.create_by = 'demo';
INSERT INTO file_record (file_name, file_type, file_url, hat_id, hat_number, user_name, file_size, upload_time, del_flag, create_by, create_time, update_by, update_time)
SELECT CONCAT('演示巡检影像-', h.hat_number, '.mp4'), 'video', CONCAT('demo://file/', h.hat_number, '/inspection.mp4'), h.id, h.hat_number, h.bind_user_name, 28.10, DATE_SUB(NOW(), INTERVAL 4 HOUR), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-004' AND h.create_by = 'demo';
INSERT INTO file_record (file_name, file_type, file_url, hat_id, hat_number, user_name, file_size, upload_time, del_flag, create_by, create_time, update_by, update_time)
SELECT CONCAT('演示离线照片-', h.hat_number, '.jpg'), 'image', CONCAT('demo://file/', h.hat_number, '/offline.jpg'), h.id, h.hat_number, h.bind_user_name, 2.60, DATE_SUB(NOW(), INTERVAL 5 HOUR), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-005' AND h.create_by = 'demo';
INSERT INTO file_record (file_name, file_type, file_url, hat_id, hat_number, user_name, file_size, upload_time, del_flag, create_by, create_time, update_by, update_time)
SELECT CONCAT('演示交接记录-', h.hat_number, '.mp3'), 'audio', CONCAT('demo://file/', h.hat_number, '/handover.mp3'), h.id, h.hat_number, h.bind_user_name, 1.20, DATE_SUB(NOW(), INTERVAL 6 HOUR), '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-006' AND h.create_by = 'demo';

-- 02 群呼/群播显式记录实际帽子对应的人员；03 组呼/组播从一个真实分组聚合其全量帽子和人员。
INSERT INTO intercom_record (intercom_type, hat_number, participant, recipient_count, start_time, end_time, duration, record_path, del_flag, create_by, create_time, update_by, update_time)
SELECT '01', h.hat_number, h.bind_user_name, 1, DATE_SUB(NOW(), INTERVAL 20 MINUTE), DATE_SUB(NOW(), INTERVAL 18 MINUTE), '00:02:00', 'demo://intercom/001', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-001' AND h.create_by = 'demo';
INSERT INTO intercom_record (intercom_type, hat_number, participant, recipient_count, start_time, end_time, duration, record_path, del_flag, create_by, create_time, update_by, update_time)
SELECT '01', h.hat_number, h.bind_user_name, 1, DATE_SUB(NOW(), INTERVAL 50 MINUTE), DATE_SUB(NOW(), INTERVAL 47 MINUTE), '00:03:00', 'demo://intercom/002', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-002' AND h.create_by = 'demo';
INSERT INTO intercom_record (intercom_type, hat_number, participant, recipient_count, start_time, end_time, duration, record_path, del_flag, create_by, create_time, update_by, update_time)
SELECT '02', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 80 MINUTE), DATE_SUB(NOW(), INTERVAL 75 MINUTE), '00:05:00', 'demo://intercom/003', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '巡检一组' GROUP BY g.id;
INSERT INTO intercom_record (intercom_type, hat_number, participant, recipient_count, start_time, end_time, duration, record_path, del_flag, create_by, create_time, update_by, update_time)
SELECT '03', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 110 MINUTE), DATE_SUB(NOW(), INTERVAL 106 MINUTE), '00:04:00', 'demo://intercom/004', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '巡检二组' GROUP BY g.id;
INSERT INTO intercom_record (intercom_type, hat_number, participant, recipient_count, start_time, end_time, duration, record_path, del_flag, create_by, create_time, update_by, update_time)
SELECT '02', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 150 MINUTE), DATE_SUB(NOW(), INTERVAL 144 MINUTE), '00:06:00', 'demo://intercom/005', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '应急保障组' GROUP BY g.id;
INSERT INTO intercom_record (intercom_type, hat_number, participant, recipient_count, start_time, end_time, duration, record_path, del_flag, create_by, create_time, update_by, update_time)
SELECT '03', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 190 MINUTE), DATE_SUB(NOW(), INTERVAL 186 MINUTE), '00:04:00', 'demo://intercom/006', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '巡检一组' GROUP BY g.id;

INSERT INTO tts_text_synthesis_broadcast (broadcast_type, hat_number, recipient, recipient_count, send_time, content, operator, del_flag, create_by, create_time, update_by, update_time)
SELECT '01', h.hat_number, h.bind_user_name, 1, DATE_SUB(NOW(), INTERVAL 15 MINUTE), '演示：请注意东侧作业安全。', '演示调度', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-001' AND h.create_by = 'demo';
INSERT INTO tts_text_synthesis_broadcast (broadcast_type, hat_number, recipient, recipient_count, send_time, content, operator, del_flag, create_by, create_time, update_by, update_time)
SELECT '01', h.hat_number, h.bind_user_name, 1, DATE_SUB(NOW(), INTERVAL 40 MINUTE), '演示：请确认防护装备佩戴状态。', '演示调度', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h WHERE h.hat_number = 'MH-DEMO-002' AND h.create_by = 'demo';
INSERT INTO tts_text_synthesis_broadcast (broadcast_type, hat_number, recipient, recipient_count, send_time, content, operator, del_flag, create_by, create_time, update_by, update_time)
SELECT '02', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 70 MINUTE), '演示：请按计划完成巡检并回传记录。', '演示调度', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '巡检一组' GROUP BY g.id;
INSERT INTO tts_text_synthesis_broadcast (broadcast_type, hat_number, recipient, recipient_count, send_time, content, operator, del_flag, create_by, create_time, update_by, update_time)
SELECT '03', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 100 MINUTE), '演示：西侧高压区已解除警戒。', '演示调度', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '巡检二组' GROUP BY g.id;
INSERT INTO tts_text_synthesis_broadcast (broadcast_type, hat_number, recipient, recipient_count, send_time, content, operator, del_flag, create_by, create_time, update_by, update_time)
SELECT '02', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 140 MINUTE), '演示：请检查应急物资和离线设备。', '演示调度', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '应急保障组' GROUP BY g.id;
INSERT INTO tts_text_synthesis_broadcast (broadcast_type, hat_number, recipient, recipient_count, send_time, content, operator, del_flag, create_by, create_time, update_by, update_time)
SELECT '03', GROUP_CONCAT(h.hat_number ORDER BY h.hat_number), GROUP_CONCAT(h.bind_user_name ORDER BY h.hat_number), COUNT(*), DATE_SUB(NOW(), INTERVAL 180 MINUTE), '演示：当前为本地模拟广播，不会调用外部设备。', '演示调度', '0', 'demo', NOW(), 'demo', NOW() FROM safety_hat_info h JOIN group_info g ON g.id = h.bind_group_id WHERE h.create_by = 'demo' AND g.create_by = 'demo' AND g.group_name = '巡检一组' GROUP BY g.id;

INSERT INTO demo_compat_record (module_key, business_key, payload) VALUES
('space', 'demo-space-01', JSON_OBJECT('demo', TRUE, 'name', '东区作业空间', 'status', '模拟可用')),
('space', 'demo-space-02', JSON_OBJECT('demo', TRUE, 'name', '西区作业空间', 'status', '模拟可用')),
('space', 'demo-space-03', JSON_OBJECT('demo', TRUE, 'name', '仓储作业空间', 'status', '模拟可用')),
('module', 'demo-module-01', JSON_OBJECT('demo', TRUE, 'name', '定位模块', 'status', '模拟在线')),
('module', 'demo-module-02', JSON_OBJECT('demo', TRUE, 'name', '告警模块', 'status', '模拟在线')),
('module', 'demo-module-03', JSON_OBJECT('demo', TRUE, 'name', '媒体模块', 'status', '模拟在线'));

INSERT INTO demo_compat_record (module_key, business_key, payload)
SELECT 'headBand', CONCAT('demo-headband-', RIGHT(h.hat_number, 2)),
       JSON_OBJECT('demo', TRUE, 'hatNumber', h.hat_number, 'deviceNumber', h.hat_number,
                   'deviceName', h.hat_number, 'status', h.status, 'userId', h.bind_user_id,
                   'name', u.nick_name, 'deptId', g.id, 'deptName', g.group_name,
                   'inGroup', g.group_name, 'hatDescription', '本地模拟绑定安全帽')
FROM safety_hat_info h
JOIN sys_user u ON u.user_id = h.bind_user_id AND u.create_by = 'demo'
JOIN group_info g ON g.id = h.bind_group_id AND g.create_by = 'demo'
WHERE h.create_by = 'demo' AND h.hat_number IN ('MH-DEMO-001', 'MH-DEMO-002', 'MH-DEMO-003');

INSERT INTO demo_compat_record (module_key, business_key, payload)
SELECT 'systemHat', CONCAT('demo-systemhat-', RIGHT(h.hat_number, 2)),
       JSON_OBJECT('demo', TRUE, 'userId', h.bind_user_id, 'name', u.nick_name,
                   'deptId', g.id, 'deptName', g.group_name, 'section', g.group_desc,
                   'position', CONCAT(g.group_name, '演示岗位'),
                   'simNumber', CONCAT('SIM-DEMO-', RIGHT(h.hat_number, 3)),
                   'inGroup', g.group_name, 'phone', '本地演示无手机号',
                   'password', '本地演示占位，非凭据', 'hatNumber', h.hat_number,
                   'deviceNumber', h.hat_number, 'status', h.status,
                   'type', '分体式智能安全帽（模拟）', 'delFlag', '0')
FROM safety_hat_info h
JOIN sys_user u ON u.user_id = h.bind_user_id AND u.create_by = 'demo'
JOIN group_info g ON g.id = h.bind_group_id AND g.create_by = 'demo'
WHERE h.create_by = 'demo' AND h.hat_number IN ('MH-DEMO-004', 'MH-DEMO-005', 'MH-DEMO-006');

-- 菜单只发布当前 PC 源码中存在的 Vue 页面；旧若依监控和工具页面没有源码，保持隐藏且停用。
UPDATE sys_menu
SET visible = '1', status = '1', update_by = 'demo', update_time = NOW()
WHERE component IN (
  'monitor/operlog/index', 'monitor/logininfor/index', 'monitor/online/index',
  'monitor/job/index', 'monitor/druid/index', 'monitor/server/index',
  'monitor/cache/index', 'monitor/cache/list', 'tool/build/index',
  'tool/gen/index', 'tool/swagger/index'
);
UPDATE sys_menu
SET visible = '1', status = '1', update_by = 'demo', update_time = NOW()
WHERE parent_id = 0 AND path IN ('monitor', 'tool');
UPDATE sys_menu
SET visible = '1', status = '1', update_by = 'demo', update_time = NOW()
WHERE parent_id = (SELECT menu_id FROM (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'system' LIMIT 1) AS system_parent)
  AND path = 'log';

-- 目录 ID 均从稳定的菜单键查询，避免依赖数据库自增值。
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '业务管理', 0, 1, 'business', NULL, '', 1, 0, 'M', '0', '0', '', 'tree-table', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '安全管理', 0, 2, 'secure', NULL, '', 1, 0, 'M', '0', '0', '', 'shield', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = 0 AND path = 'secure' AND menu_type = 'M');

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);
SET @secure_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'secure' AND menu_type = 'M' LIMIT 1);
SET @system_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'system' AND menu_type = 'M' LIMIT 1);
UPDATE sys_menu SET visible = '0', status = '0', update_by = 'demo', update_time = NOW() WHERE menu_id = @system_menu_id;

-- 业务管理：现有 Vue 组件逐字映射为动态菜单。
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '分组管理', @business_menu_id, 1, 'group', 'group/index', '', 1, 0, 'C', '0', '0', '', 'peoples', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'group' AND component = 'group/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '安全帽运行状态', @business_menu_id, 2, 'hat', 'hat/index', '', 1, 0, 'C', '0', '0', '', 'monitor', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'hat' AND component = 'hat/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '实时监控', @business_menu_id, 3, 'live', 'live/index', '', 1, 0, 'C', '0', '0', '', 'video', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'live' AND component = 'live/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '轨迹回放', @business_menu_id, 4, 'track', 'track/index', '', 1, 0, 'C', '0', '0', '', 'guide', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'track' AND component = 'track/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '电子围栏', @business_menu_id, 5, 'fence', 'fence/index', '', 1, 0, 'C', '0', '0', '', 'map', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'fence' AND component = 'fence/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT 'SOS 告警', @business_menu_id, 6, 'sos', 'sos/index', '', 1, 0, 'C', '0', '0', '', 'warning', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'sos' AND component = 'sos/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '文件记录', @business_menu_id, 7, 'file', 'file/index', '', 1, 0, 'C', '0', '0', '', 'documentation', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'file' AND component = 'file/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '实时对讲', @business_menu_id, 8, 'intercom', 'intercom/index', '', 1, 0, 'C', '0', '0', '', 'phone', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'intercom' AND component = 'intercom/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT 'TTS 广播', @business_menu_id, 9, 'tts', 'tts/index', '', 1, 0, 'C', '0', '0', '', 'message', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'tts' AND component = 'tts/index');

-- 安全管理。
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '安全帽检查', @secure_menu_id, 1, 'helmet', 'secure/helmet/index', '', 1, 0, 'C', '0', '0', '', 's-check', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @secure_menu_id AND path = 'helmet' AND component = 'secure/helmet/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '有限空间检查', @secure_menu_id, 2, 'limited', 'secure/limited/index', '', 1, 0, 'C', '0', '0', '', 's-check', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @secure_menu_id AND path = 'limited' AND component = 'secure/limited/index');

-- 系统管理沿用既有目录，补齐当前源码存在而基础 SQL 未发布的页面。
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '模块管理', @system_menu_id, 9, 'module', 'system/module/index', '', 1, 0, 'C', '0', '0', '', 'component', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'module' AND component = 'system/module/index');
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, update_by, update_time, remark)
SELECT '安全帽档案', @system_menu_id, 10, 'hat-archive', 'system/hat/index', '', 1, 0, 'C', '0', '0', '', 'user', 'demo', NOW(), 'demo', NOW(), 'offline-demo-menu'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'hat-archive' AND component = 'system/hat/index');

SET @business_group_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'group' AND component = 'group/index' LIMIT 1);
SET @business_hat_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'hat' AND component = 'hat/index' LIMIT 1);
SET @business_live_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'live' AND component = 'live/index' LIMIT 1);
SET @business_track_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'track' AND component = 'track/index' LIMIT 1);
SET @business_fence_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'fence' AND component = 'fence/index' LIMIT 1);
SET @business_sos_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'sos' AND component = 'sos/index' LIMIT 1);
SET @business_file_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'file' AND component = 'file/index' LIMIT 1);
SET @business_intercom_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'intercom' AND component = 'intercom/index' LIMIT 1);
SET @business_tts_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'tts' AND component = 'tts/index' LIMIT 1);
SET @secure_helmet_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @secure_menu_id AND path = 'helmet' AND component = 'secure/helmet/index' LIMIT 1);
SET @secure_limited_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @secure_menu_id AND path = 'limited' AND component = 'secure/limited/index' LIMIT 1);
SET @system_user_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'user' AND component = 'system/user/index' LIMIT 1);
SET @system_role_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'role' AND component = 'system/role/index' LIMIT 1);
SET @system_menu_page_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'menu' AND component = 'system/menu/index' LIMIT 1);
SET @system_dept_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'dept' AND component = 'system/dept/index' LIMIT 1);
SET @system_post_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'post' AND component = 'system/post/index' LIMIT 1);
SET @system_dict_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'dict' AND component = 'system/dict/index' LIMIT 1);
SET @system_config_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'config' AND component = 'system/config/index' LIMIT 1);
SET @system_notice_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'notice' AND component = 'system/notice/index' LIMIT 1);
SET @system_module_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'module' AND component = 'system/module/index' LIMIT 1);
SET @system_hat_archive_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @system_menu_id AND path = 'hat-archive' AND component = 'system/hat/index' LIMIT 1);

-- 管理员可访问全部已发布菜单；重复导入时按 role/menu 组合去重。
INSERT INTO sys_role_menu (role_id, menu_id)
SELECT 1, menu_id
FROM (
  SELECT @business_menu_id AS menu_id UNION ALL SELECT @secure_menu_id UNION ALL SELECT @system_menu_id
  UNION ALL SELECT @business_group_id UNION ALL SELECT @business_hat_id UNION ALL SELECT @business_live_id
  UNION ALL SELECT @business_track_id UNION ALL SELECT @business_fence_id UNION ALL SELECT @business_sos_id
  UNION ALL SELECT @business_file_id UNION ALL SELECT @business_intercom_id UNION ALL SELECT @business_tts_id
  UNION ALL SELECT @secure_helmet_id UNION ALL SELECT @secure_limited_id
  UNION ALL SELECT @system_user_id UNION ALL SELECT @system_role_id UNION ALL SELECT @system_menu_page_id
  UNION ALL SELECT @system_dept_id UNION ALL SELECT @system_post_id UNION ALL SELECT @system_dict_id
  UNION ALL SELECT @system_config_id UNION ALL SELECT @system_notice_id UNION ALL SELECT @system_module_id
  UNION ALL SELECT @system_hat_archive_id
) AS demo_menu_ids
WHERE menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_role_menu WHERE role_id = 1 AND menu_id = demo_menu_ids.menu_id);

COMMIT;
