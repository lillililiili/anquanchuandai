-- A work task is the shared inspection group. Never store progress per phone.
CREATE TABLE IF NOT EXISTS wear_inspection_record (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 task_id BIGINT NOT NULL,
 sequence_no INT NOT NULL,
 request_id VARCHAR(64) NOT NULL,
 actor_user_id BIGINT NOT NULL,
 actor_name VARCHAR(100) NOT NULL,
 recorded_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 UNIQUE KEY uk_inspection_sequence (task_id, sequence_no),
 UNIQUE KEY uk_inspection_request (task_id, request_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS wear_inspection_report (
 id VARCHAR(36) NOT NULL PRIMARY KEY,
 task_id BIGINT NOT NULL,
 request_id VARCHAR(64) NOT NULL,
 actor_user_id BIGINT NOT NULL,
 actor_name VARCHAR(100) NOT NULL,
 location VARCHAR(200) NOT NULL,
 description VARCHAR(1000) NOT NULL,
 payload_hash VARCHAR(64) NOT NULL,
 reported_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 UNIQUE KEY uk_inspection_report_request (task_id, request_id),
 KEY idx_inspection_report_task (task_id, reported_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS wear_inspection_media (
 id VARCHAR(36) NOT NULL PRIMARY KEY,
 report_id VARCHAR(36) NOT NULL,
 storage_name VARCHAR(60) NOT NULL,
 media_type VARCHAR(50) NOT NULL,
 byte_size BIGINT NOT NULL,
 KEY idx_inspection_media_report (report_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
