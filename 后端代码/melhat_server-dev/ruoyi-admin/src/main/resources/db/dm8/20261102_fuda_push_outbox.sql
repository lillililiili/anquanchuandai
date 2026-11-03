-- DM8 explicit schema. No source data.
CREATE TABLE fuda_push_outbox (
 sequence BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
 event_id VARCHAR(80) NOT NULL,
 destination_key CHAR(64) NOT NULL,
 destination_id VARCHAR(64) NOT NULL,
 ledger_device_id VARCHAR(128) NOT NULL,
 device_type VARCHAR(24) NOT NULL,
 device_id VARCHAR(64) NOT NULL,
 device_key CHAR(64) NOT NULL,
 event_type VARCHAR(16) NOT NULL,
 body CLOB NOT NULL,
 status VARCHAR(16) NOT NULL,
 attempts INT NOT NULL DEFAULT 0,
 next_attempt_at BIGINT NOT NULL,
 lease_token VARCHAR(36),
 lease_until BIGINT,
 created_at BIGINT NOT NULL,
 completed_at BIGINT,
 last_attempt_at BIGINT,
 last_outcome VARCHAR(64),
 last_http_status INT,
 CONSTRAINT fuda_push_event UNIQUE (event_id)
);
CREATE INDEX fuda_push_due ON fuda_push_outbox(destination_key,status,next_attempt_at);
CREATE INDEX fuda_push_device ON fuda_push_outbox(destination_key,device_key,sequence,status);
