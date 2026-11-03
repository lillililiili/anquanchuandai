-- DM8 explicit schema. No source data.
CREATE TABLE admin_ledger (
 id SMALLINT NOT NULL PRIMARY KEY,
 body CLOB NOT NULL,
 updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE wearable_meta (
 id SMALLINT NOT NULL PRIMARY KEY,
 revision BIGINT NOT NULL,
 next_id BIGINT NOT NULL
);
CREATE TABLE wearable_site (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 code VARCHAR(128),
 name VARCHAR(128),
 time_zone VARCHAR(64),
 enabled BIT,
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE TABLE wearable_organization (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 code VARCHAR(128),
 name VARCHAR(128),
 area_id VARCHAR(128),
 parent_id VARCHAR(128),
 enabled BIT,
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_org_site ON wearable_organization(site_id);
CREATE TABLE wearable_area (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 code VARCHAR(128),
 name VARCHAR(128),
 parent_id VARCHAR(128),
 enabled BIT,
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_area_site ON wearable_area(site_id);
CREATE TABLE wearable_person (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 code VARCHAR(128),
 name VARCHAR(128),
 organization_id VARCHAR(128),
 area_id VARCHAR(128),
 account_id VARCHAR(128),
 enabled BIT,
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_person_site ON wearable_person(site_id);
CREATE INDEX idx_wearable_person_name ON wearable_person(name);
CREATE TABLE wearable_duty_shift (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 name VARCHAR(128),
 enabled BIT,
 version BIGINT,
 starts_at VARCHAR(64),
 ends_at VARCHAR(64),
 shift_source VARCHAR(64),
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_shift_site ON wearable_duty_shift(site_id);
CREATE TABLE wearable_account (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 login_name VARCHAR(128),
 name VARCHAR(128),
 site_id VARCHAR(128),
 person_id VARCHAR(128),
 enabled BIT,
 builtin BIT,
 version BIGINT,
 credential_version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_account_login ON wearable_account(login_name);
CREATE TABLE wearable_role (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 name VARCHAR(128),
 builtin BIT,
 enabled BIT,
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE TABLE wearable_device (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 code VARCHAR(128),
 name VARCHAR(128),
 device_type VARCHAR(32),
 lifecycle VARCHAR(32),
 relation_state VARCHAR(32),
 communication VARCHAR(32),
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_device_site ON wearable_device(site_id);
CREATE INDEX idx_wearable_device_code ON wearable_device(code);
CREATE TABLE wearable_assignment (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 active BIT,
 started_at VARCHAR(64),
 version BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_assignment_person ON wearable_assignment(person_id);
CREATE INDEX idx_wearable_assignment_device ON wearable_assignment(device_id);
CREATE TABLE wearable_assignment_history (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 person_id VARCHAR(128),
 device_id VARCHAR(128),
 action VARCHAR(32),
 occurred_at VARCHAR(64),
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_history_person ON wearable_assignment_history(person_id);
CREATE INDEX idx_wearable_history_device ON wearable_assignment_history(device_id);
CREATE TABLE wearable_audit (
 id VARCHAR(128) NOT NULL PRIMARY KEY,
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 actor_id VARCHAR(128),
 object_id VARCHAR(128),
 action VARCHAR(128),
 result VARCHAR(32),
 occurred_at VARCHAR(64),
 sort_order INT NOT NULL,
 body CLOB NOT NULL
);
CREATE INDEX idx_wearable_audit_site ON wearable_audit(site_id);
CREATE TABLE wearable_idempotency (
 idem_key VARCHAR(512) NOT NULL PRIMARY KEY,
 body CLOB NOT NULL
);
CREATE TABLE wearable_document (
 doc_key VARCHAR(64) NOT NULL PRIMARY KEY,
 body CLOB NOT NULL
);
