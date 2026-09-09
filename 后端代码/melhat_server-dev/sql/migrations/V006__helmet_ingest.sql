-- S6: helmet ingest raw, samples, adapter alerts, device last_telemetry_at.

SET @exist := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = 'wear_device'
     AND COLUMN_NAME = 'last_telemetry_at'
);
SET @sql := IF(@exist = 0,
  'ALTER TABLE wear_device ADD COLUMN last_telemetry_at DATETIME NULL COMMENT ''已采纳遥测发生时间'' AFTER last_reported_at',
  'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS wear_ingest_raw (
  id              BIGINT(20)    NOT NULL AUTO_INCREMENT,
  path            VARCHAR(64)   NOT NULL,
  helmet_sn       VARCHAR(64)   DEFAULT NULL,
  device_id       BIGINT(20)    DEFAULT NULL,
  message_key     VARCHAR(128)  DEFAULT NULL,
  received_at     DATETIME      NOT NULL,
  payload_json    MEDIUMTEXT,
  auth_ok         TINYINT(1)    NOT NULL DEFAULT 1,
  process_status  VARCHAR(16)   NOT NULL,
  error           VARCHAR(500)  DEFAULT NULL,
  create_time     DATETIME      DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_ingest_key (message_key),
  KEY idx_wear_ingest_device (device_id, received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='安全帽回调原始报文';

CREATE TABLE IF NOT EXISTS wear_device_sample (
  id                BIGINT(20)     NOT NULL AUTO_INCREMENT,
  device_id         BIGINT(20)     NOT NULL,
  occurred_at       DATETIME       NOT NULL,
  received_at       DATETIME       NOT NULL,
  lat               DECIMAL(10,7)  DEFAULT NULL,
  lng               DECIMAL(10,7)  DEFAULT NULL,
  altitude          VARCHAR(32)    DEFAULT NULL,
  speed             VARCHAR(32)    DEFAULT NULL,
  battery           DECIMAL(8,2)   DEFAULT NULL,
  online            VARCHAR(8)     DEFAULT NULL,
  location_quality  VARCHAR(16)    NOT NULL DEFAULT 'unknown',
  create_time       DATETIME       DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_wear_sample_device_time (device_id, occurred_at),
  KEY idx_wear_sample_device (device_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='设备遥测样本';

CREATE TABLE IF NOT EXISTS wear_adapter_alert (
  id          BIGINT(20)   NOT NULL AUTO_INCREMENT,
  kind        VARCHAR(32)  NOT NULL,
  summary     VARCHAR(1000) DEFAULT NULL,
  create_time DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_adapter_alert (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='适配层失败告警';
