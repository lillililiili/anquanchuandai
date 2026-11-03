-- DM8 explicit schema. No source data.
CREATE TABLE fuda_alarm_journal_state (
 id INT NOT NULL PRIMARY KEY,
 committed_sequence BIGINT NOT NULL,
 retained_floor BIGINT NOT NULL,
 backfill_completed_at BIGINT
);
INSERT INTO fuda_alarm_journal_state(id,committed_sequence,retained_floor) SELECT 1,0,0 FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM fuda_alarm_journal_state WHERE id=1);
CREATE TABLE fuda_alarm_journal (
 export_sequence BIGINT NOT NULL PRIMARY KEY,
 event_id VARCHAR(128) NOT NULL,
 event_hash CHAR(64) NOT NULL,
 device_key VARCHAR(160) NOT NULL,
 scope_hash CHAR(64) NOT NULL,
 internal_device_id VARCHAR(128) NOT NULL,
 recorded_at BIGINT NOT NULL,
 body CLOB NOT NULL,
 CONSTRAINT fuda_alarm_event UNIQUE (event_hash)
);
CREATE INDEX fuda_alarm_scope ON fuda_alarm_journal(scope_hash, export_sequence);
CREATE INDEX fuda_alarm_device ON fuda_alarm_journal(internal_device_id, export_sequence);
