-- S4: assignment, device current holder, audit, idempotency, site transfer.

SET @exist := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = 'wear_device'
     AND COLUMN_NAME = 'current_assignment_id'
);
SET @sql := IF(@exist = 0,
  'ALTER TABLE wear_device ADD COLUMN current_assignment_id BIGINT NULL COMMENT ''当前有效领用'' AFTER asset_status, ADD KEY idx_wear_device_current_asg (current_assignment_id)',
  'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS wear_assignment (
  id              BIGINT(20)   NOT NULL AUTO_INCREMENT,
  device_id       BIGINT(20)   NOT NULL,
  person_id       BIGINT(20)   NOT NULL,
  site_id         BIGINT(20)   NOT NULL,
  issued_at       DATETIME     NOT NULL,
  returned_at     DATETIME     DEFAULT NULL,
  issued_by       VARCHAR(64)  NOT NULL DEFAULT '',
  returned_by     VARCHAR(64)  DEFAULT NULL,
  return_reason   VARCHAR(500) DEFAULT NULL,
  return_kind     VARCHAR(16)  DEFAULT NULL COMMENT 'normal/recover',
  version         INT(11)      NOT NULL DEFAULT 1,
  create_by       VARCHAR(64)  DEFAULT '',
  create_time     DATETIME     DEFAULT NULL,
  update_by       VARCHAR(64)  DEFAULT '',
  update_time     DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_asg_device (device_id, returned_at),
  KEY idx_wear_asg_person (person_id, returned_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='设备领用区间，不覆盖历史';

CREATE TABLE IF NOT EXISTS wear_asset_audit (
  id             BIGINT(20)   NOT NULL AUTO_INCREMENT,
  action         VARCHAR(32)  NOT NULL,
  device_id      BIGINT(20)   DEFAULT NULL,
  assignment_id  BIGINT(20)   DEFAULT NULL,
  person_id      BIGINT(20)   DEFAULT NULL,
  operator       VARCHAR(64)  NOT NULL DEFAULT '',
  summary        VARCHAR(1000) DEFAULT NULL,
  create_time    DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_audit_device (device_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='资产领还审计';

CREATE TABLE IF NOT EXISTS wear_idempotency (
  id           BIGINT(20)   NOT NULL AUTO_INCREMENT,
  scope        VARCHAR(64)  NOT NULL,
  idem_key     VARCHAR(64)  NOT NULL,
  resource_id  BIGINT(20)   NOT NULL,
  create_time  DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_idempotency (scope, idem_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='写操作幂等';

CREATE TABLE IF NOT EXISTS wear_device_site_transfer (
  id          BIGINT(20)  NOT NULL AUTO_INCREMENT,
  device_id   BIGINT(20)  NOT NULL,
  from_site_id BIGINT(20) DEFAULT NULL,
  to_site_id   BIGINT(20) DEFAULT NULL,
  operator    VARCHAR(64) NOT NULL DEFAULT '',
  create_time DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_transfer_device (device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='无领用设备的厂站调拨';

INSERT INTO wear_assignment (device_id, person_id, site_id, issued_at, issued_by, version, create_by, create_time)
SELECT d.id, p.id, d.site_id, NOW(), 'demo', 1, 'demo', NOW()
  FROM wear_device d
  JOIN wear_person p ON p.person_code = 'P-DEMO-001'
 WHERE d.sn IN ('MH-DEMO-001', 'BL-DEMO-001') AND d.manufacturer_code = 'MELHAT'
   AND NOT EXISTS (
        SELECT 1 FROM wear_assignment a
         WHERE a.device_id = d.id AND a.returned_at IS NULL AND a.create_by = 'demo'
   );

UPDATE wear_device d
  JOIN wear_assignment a ON a.device_id = d.id AND a.returned_at IS NULL AND a.create_by = 'demo'
   SET d.asset_status = 'issued', d.current_assignment_id = a.id
 WHERE d.sn IN ('MH-DEMO-001', 'BL-DEMO-001') AND d.manufacturer_code = 'MELHAT';
