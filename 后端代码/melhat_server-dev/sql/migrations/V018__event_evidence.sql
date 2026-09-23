ALTER TABLE wear_safety_event MODIFY COLUMN severity VARCHAR(16) NOT NULL;
ALTER TABLE wear_safety_event ADD COLUMN device_type VARCHAR(32) NULL AFTER device_id;
CREATE TABLE IF NOT EXISTS wear_event_media (
  id VARCHAR(36) PRIMARY KEY,
  event_id BIGINT NOT NULL,
  submission_version INT NOT NULL,
  actor_user_id BIGINT NOT NULL,
  media_type VARCHAR(32) NOT NULL,
  byte_size BIGINT NOT NULL,
  create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_event_media_submission (event_id,submission_version,actor_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
