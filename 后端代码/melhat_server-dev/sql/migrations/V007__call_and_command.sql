-- S7: call session and device command. Old intercom/tts tables untouched.

CREATE TABLE IF NOT EXISTS wear_call_session (
  id                  BIGINT(20)    NOT NULL AUTO_INCREMENT,
  kind                VARCHAR(16)   NOT NULL,
  event_id            BIGINT(20)    DEFAULT NULL,
  device_id           BIGINT(20)    NOT NULL,
  sn                  VARCHAR(64)   DEFAULT NULL,
  person_id           BIGINT(20)    DEFAULT NULL,
  site_id             BIGINT(20)    NOT NULL,
  requester_user_id   BIGINT(20)    NOT NULL,
  status              VARCHAR(16)   NOT NULL,
  channel_name        VARCHAR(64)   DEFAULT NULL,
  agora_uid           VARCHAR(64)   DEFAULT NULL,
  video               TINYINT(1)    NOT NULL DEFAULT 0,
  demo                TINYINT(1)    NOT NULL DEFAULT 0,
  expires_at          DATETIME      DEFAULT NULL,
  started_at          DATETIME      DEFAULT NULL,
  connected_at        DATETIME      DEFAULT NULL,
  ended_at            DATETIME      DEFAULT NULL,
  fail_reason         VARCHAR(500)  DEFAULT NULL,
  version             INT(11)       NOT NULL DEFAULT 1,
  create_by           VARCHAR(64)   DEFAULT '',
  create_time         DATETIME      DEFAULT NULL,
  update_by           VARCHAR(64)   DEFAULT '',
  update_time         DATETIME      DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_call_site (site_id, status),
  KEY idx_wear_call_event (event_id),
  KEY idx_wear_call_channel (channel_name),
  KEY idx_wear_call_device (device_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='调度通话会话';

CREATE TABLE IF NOT EXISTS wear_device_command (
  id           BIGINT(20)    NOT NULL AUTO_INCREMENT,
  kind         VARCHAR(16)   NOT NULL,
  device_id    BIGINT(20)    NOT NULL,
  sn           VARCHAR(64)   DEFAULT NULL,
  call_id      BIGINT(20)    DEFAULT NULL,
  event_id     BIGINT(20)    DEFAULT NULL,
  payload      VARCHAR(1000) DEFAULT NULL,
  status       VARCHAR(16)   NOT NULL,
  vendor_msg   VARCHAR(500)  DEFAULT NULL,
  create_by    VARCHAR(64)   DEFAULT '',
  create_time  DATETIME      DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_wear_cmd_device (device_id, id),
  KEY idx_wear_cmd_event (event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='设备指令（TTS等）';
