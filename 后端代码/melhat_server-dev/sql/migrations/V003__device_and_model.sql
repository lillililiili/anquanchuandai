-- S3: product type/model, device ledger, legacy hat mapping. Idempotent for local test db.

CREATE TABLE IF NOT EXISTS wear_product_type (
  code          VARCHAR(32)  NOT NULL,
  name          VARCHAR(64)  NOT NULL,
  status        CHAR(1)      NOT NULL DEFAULT '0',
  create_by     VARCHAR(64)  DEFAULT '',
  create_time   DATETIME     DEFAULT NULL,
  PRIMARY KEY (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='产品类型（不是能力来源）';

CREATE TABLE IF NOT EXISTS wear_product_model (
  id                 BIGINT(20)   NOT NULL AUTO_INCREMENT,
  type_code          VARCHAR(32)  NOT NULL,
  model_code         VARCHAR(64)  NOT NULL,
  manufacturer_code  VARCHAR(64)  NOT NULL,
  name               VARCHAR(128) NOT NULL,
  protocol_version   VARCHAR(64)  DEFAULT NULL,
  capabilities       TEXT         NOT NULL COMMENT 'JSON: attributes/events/actions',
  status             CHAR(1)      NOT NULL DEFAULT '0',
  version            INT(11)      NOT NULL DEFAULT 1,
  del_flag           CHAR(1)      NOT NULL DEFAULT '0',
  create_by          VARCHAR(64)  DEFAULT '',
  create_time        DATETIME     DEFAULT NULL,
  update_by          VARCHAR(64)  DEFAULT '',
  update_time        DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_product_model_code (model_code),
  KEY idx_wear_product_model_type (type_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='产品型号与能力';

CREATE TABLE IF NOT EXISTS wear_device (
  id                 BIGINT(20)    NOT NULL AUTO_INCREMENT,
  manufacturer_code  VARCHAR(64)   NOT NULL,
  sn                 VARCHAR(64)   NOT NULL,
  model_id           BIGINT(20)    NOT NULL,
  site_id            BIGINT(20)    DEFAULT NULL,
  asset_status       VARCHAR(16)   NOT NULL DEFAULT 'unassigned' COMMENT 'unassigned/in_stock/maintenance/disabled/scrapped',
  external_code      VARCHAR(64)   DEFAULT NULL COMMENT '厂商标识，如帽号，不是平台ID',
  online             CHAR(1)       DEFAULT NULL COMMENT '连接状态，空=未知',
  battery            DECIMAL(10,2) DEFAULT NULL,
  last_reported_at   DATETIME      DEFAULT NULL,
  version            INT(11)       NOT NULL DEFAULT 1,
  del_flag           CHAR(1)       NOT NULL DEFAULT '0',
  create_by          VARCHAR(64)   DEFAULT '',
  create_time        DATETIME      DEFAULT NULL,
  update_by          VARCHAR(64)   DEFAULT '',
  update_time        DATETIME      DEFAULT NULL,
  remark             VARCHAR(500)  DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_device_mfr_sn (manufacturer_code, sn),
  KEY idx_wear_device_site (site_id),
  KEY idx_wear_device_model (model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='通用设备台账';

CREATE TABLE IF NOT EXISTS wear_device_legacy_hat (
  id         BIGINT(20) NOT NULL AUTO_INCREMENT,
  device_id  BIGINT(20) NOT NULL,
  hat_id     BIGINT(20) NOT NULL,
  create_by  VARCHAR(64) DEFAULT '',
  create_time DATETIME DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_legacy_device (device_id),
  UNIQUE KEY uk_wear_legacy_hat (hat_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='旧安全帽ID映射，S11前不切流';

INSERT INTO wear_product_type (code, name, status, create_by, create_time)
SELECT 'helmet', '安全帽', '0', 'demo', NOW() FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM wear_product_type WHERE code = 'helmet');
INSERT INTO wear_product_type (code, name, status, create_by, create_time)
SELECT 'belt', '安全带', '0', 'demo', NOW() FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM wear_product_type WHERE code = 'belt');

INSERT INTO wear_product_model (type_code, model_code, manufacturer_code, name, protocol_version, capabilities, status, version, del_flag, create_by, create_time)
SELECT 'helmet', 'HAT-MH-CAM', 'MELHAT', '演示摄像安全帽', 'demo-hat-v1',
       '{"protocolVersion":"demo-hat-v1","attributes":["battery","online","gnss"],"events":["sos","fall"],"actions":["tts","intercom","video"]}',
       '0', 1, '0', 'demo', NOW() FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM wear_product_model WHERE model_code = 'HAT-MH-CAM');
INSERT INTO wear_product_model (type_code, model_code, manufacturer_code, name, protocol_version, capabilities, status, version, del_flag, create_by, create_time)
SELECT 'helmet', 'HAT-MH-NOV', 'MELHAT', '演示无视频安全帽', 'demo-hat-v1',
       '{"protocolVersion":"demo-hat-v1","attributes":["battery","online","gnss"],"events":["sos"],"actions":["tts"]}',
       '0', 1, '0', 'demo', NOW() FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM wear_product_model WHERE model_code = 'HAT-MH-NOV');
INSERT INTO wear_product_model (type_code, model_code, manufacturer_code, name, protocol_version, capabilities, status, version, del_flag, create_by, create_time)
SELECT 'belt', 'BELT-STD', 'MELHAT', '演示安全带', 'demo-belt-v1',
       '{"protocolVersion":"demo-belt-v1","attributes":["online"],"events":["unbuckled","impact"],"actions":[]}',
       '0', 1, '0', 'demo', NOW() FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM wear_product_model WHERE model_code = 'BELT-STD');

INSERT INTO wear_device (manufacturer_code, sn, model_id, site_id, asset_status, external_code, version, del_flag, create_by, create_time, remark)
SELECT 'MELHAT', h.hat_number, m.id, h.site_id, 'in_stock', h.hat_number, 1, '0', 'demo', NOW(), 'S3 由演示帽子映射'
  FROM safety_hat_info h
  JOIN wear_product_model m ON m.model_code = 'HAT-MH-CAM' AND m.create_by = 'demo'
 WHERE h.hat_number IN ('MH-DEMO-001','MH-DEMO-002','MH-DEMO-003','MH-DEMO-004','MH-DEMO-005','MH-DEMO-006')
   AND h.create_by = 'demo'
   AND NOT EXISTS (SELECT 1 FROM wear_device d WHERE d.manufacturer_code = 'MELHAT' AND d.sn = h.hat_number);

INSERT INTO wear_device_legacy_hat (device_id, hat_id, create_by, create_time)
SELECT d.id, h.id, 'demo', NOW()
  FROM wear_device d
  JOIN safety_hat_info h ON h.hat_number = d.sn AND h.create_by = 'demo'
 WHERE d.create_by = 'demo' AND d.sn LIKE 'MH-DEMO-00%'
   AND NOT EXISTS (SELECT 1 FROM wear_device_legacy_hat x WHERE x.device_id = d.id);

INSERT INTO wear_device (manufacturer_code, sn, model_id, site_id, asset_status, external_code, version, del_flag, create_by, create_time, remark)
SELECT 'MELHAT', 'MH-DEMO-NOV-A', m.id, s.id, 'in_stock', 'MH-DEMO-NOV-A', 1, '0', 'demo', NOW(), 'S3 无视频型号'
  FROM wear_product_model m
  JOIN wear_site s ON s.site_code = 'SITE-DEMO-A'
 WHERE m.model_code = 'HAT-MH-NOV'
   AND NOT EXISTS (SELECT 1 FROM wear_device d WHERE d.manufacturer_code = 'MELHAT' AND d.sn = 'MH-DEMO-NOV-A');

INSERT INTO wear_device (manufacturer_code, sn, model_id, site_id, asset_status, external_code, version, del_flag, create_by, create_time, remark)
SELECT 'MELHAT', 'BL-DEMO-001', m.id, s.id, 'in_stock', 'BL-DEMO-001', 1, '0', 'demo', NOW(), 'S3 演示安全带 A'
  FROM wear_product_model m
  JOIN wear_site s ON s.site_code = 'SITE-DEMO-A'
 WHERE m.model_code = 'BELT-STD'
   AND NOT EXISTS (SELECT 1 FROM wear_device d WHERE d.manufacturer_code = 'MELHAT' AND d.sn = 'BL-DEMO-001');
INSERT INTO wear_device (manufacturer_code, sn, model_id, site_id, asset_status, external_code, version, del_flag, create_by, create_time, remark)
SELECT 'MELHAT', 'BL-DEMO-002', m.id, s.id, 'in_stock', 'BL-DEMO-002', 1, '0', 'demo', NOW(), 'S3 演示安全带 B'
  FROM wear_product_model m
  JOIN wear_site s ON s.site_code = 'SITE-DEMO-B'
 WHERE m.model_code = 'BELT-STD'
   AND NOT EXISTS (SELECT 1 FROM wear_device d WHERE d.manufacturer_code = 'MELHAT' AND d.sn = 'BL-DEMO-002');

INSERT INTO wear_device (manufacturer_code, sn, model_id, site_id, asset_status, external_code, version, del_flag, create_by, create_time, remark)
SELECT 'MELHAT', 'MH-UNASSIGNED', m.id, NULL, 'unassigned', 'MH-UNASSIGNED', 1, '0', 'demo', NOW(), 'S3 未分配，仅平台管理员可见'
  FROM wear_product_model m
 WHERE m.model_code = 'HAT-MH-CAM'
   AND NOT EXISTS (SELECT 1 FROM wear_device d WHERE d.manufacturer_code = 'MELHAT' AND d.sn = 'MH-UNASSIGNED');

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);
INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '设备台账', @business_menu_id, 0, 'devices', 'devices/index', '', 1, 0, 'C', '0', '0', 'wear:device:list', 'monitor', 'demo', NOW(), 'S3'
WHERE @business_menu_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'devices');

INSERT IGNORE INTO sys_role_menu (role_id, menu_id)
SELECT r.role_id, m.menu_id
  FROM sys_role r
  JOIN sys_menu m ON m.path = 'devices' AND m.create_by = 'demo'
 WHERE r.role_key IN ('wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
