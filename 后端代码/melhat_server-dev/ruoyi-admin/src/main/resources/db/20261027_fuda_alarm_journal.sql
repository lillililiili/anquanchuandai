-- Append-only export evidence. No demo rows, no automatic retention, and no AUTO_INCREMENT watermark.
CREATE TABLE IF NOT EXISTS fuda_alarm_journal_state (
 id INT NOT NULL PRIMARY KEY,
 committed_sequence BIGINT NOT NULL,
 retained_floor BIGINT NOT NULL,
 backfill_completed_at BIGINT
);
INSERT INTO fuda_alarm_journal_state (id, committed_sequence, retained_floor)
 VALUES (1, 0, 0) ON DUPLICATE KEY UPDATE id=id;
CREATE TABLE IF NOT EXISTS fuda_alarm_journal (
 export_sequence BIGINT NOT NULL PRIMARY KEY,
 event_id VARCHAR(128) NOT NULL,
 event_hash CHAR(64) NOT NULL,
 device_key VARCHAR(160) NOT NULL,
 scope_hash CHAR(64) NOT NULL,
 internal_device_id VARCHAR(128) NOT NULL,
 recorded_at BIGINT NOT NULL,
 body LONGTEXT NOT NULL,
 UNIQUE KEY fuda_alarm_event(event_hash),
 INDEX fuda_alarm_scope(scope_hash, export_sequence),
 INDEX fuda_alarm_device(internal_device_id, export_sequence)
);
