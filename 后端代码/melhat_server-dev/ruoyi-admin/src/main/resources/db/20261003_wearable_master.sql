-- 后台主数据按行保存。可重复执行，不删除已有业务行。
-- 嵌套字段在 body 中，稳定列供查询。前台告警和定位不在这些表里。

CREATE TABLE IF NOT EXISTS wearable_meta (
  id TINYINT NOT NULL PRIMARY KEY,
  revision BIGINT NOT NULL,
  next_id BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS wearable_site (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  code VARCHAR(128),
  name VARCHAR(128),
  time_zone VARCHAR(64),
  enabled BOOLEAN,
  version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS wearable_organization (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  code VARCHAR(128),
  name VARCHAR(128),
  area_id VARCHAR(128),
  parent_id VARCHAR(128),
  enabled BOOLEAN,
  version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_org_site (site_id)
);

CREATE TABLE IF NOT EXISTS wearable_area (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  code VARCHAR(128),
  name VARCHAR(128),
  parent_id VARCHAR(128),
  enabled BOOLEAN,
  version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_area_site (site_id)
);

CREATE TABLE IF NOT EXISTS wearable_person (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  code VARCHAR(128),
  name VARCHAR(128),
  organization_id VARCHAR(128),
  area_id VARCHAR(128),
  account_id VARCHAR(128),
  enabled BOOLEAN,
  version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_person_site (site_id),
  INDEX idx_wearable_person_name (name)
);

CREATE TABLE IF NOT EXISTS wearable_duty_shift (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  name VARCHAR(128),
  enabled BOOLEAN,
  version BIGINT,
  starts_at VARCHAR(64),
  ends_at VARCHAR(64),
  shift_source VARCHAR(64),
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_shift_site (site_id)
);

CREATE TABLE IF NOT EXISTS wearable_account (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  login_name VARCHAR(128),
  name VARCHAR(128),
  site_id VARCHAR(128),
  person_id VARCHAR(128),
  enabled BOOLEAN,
  builtin BOOLEAN,
  version BIGINT,
  credential_version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_account_login (login_name)
);

CREATE TABLE IF NOT EXISTS wearable_role (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  name VARCHAR(128),
  builtin BOOLEAN,
  enabled BOOLEAN,
  version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS wearable_device (
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
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_device_site (site_id),
  INDEX idx_wearable_device_code (code)
);

CREATE TABLE IF NOT EXISTS wearable_assignment (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  device_id VARCHAR(128),
  person_id VARCHAR(128),
  active BOOLEAN,
  started_at VARCHAR(64),
  version BIGINT,
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_assignment_person (person_id),
  INDEX idx_wearable_assignment_device (device_id)
);

CREATE TABLE IF NOT EXISTS wearable_assignment_history (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  person_id VARCHAR(128),
  device_id VARCHAR(128),
  action VARCHAR(32),
  occurred_at VARCHAR(64),
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_history_person (person_id),
  INDEX idx_wearable_history_device (device_id)
);

CREATE TABLE IF NOT EXISTS wearable_audit (
  id VARCHAR(128) NOT NULL PRIMARY KEY,
  site_id VARCHAR(128),
  area_id VARCHAR(128),
  actor_id VARCHAR(128),
  object_id VARCHAR(128),
  action VARCHAR(128),
  result VARCHAR(32),
  occurred_at VARCHAR(64),
  sort_order INT NOT NULL,
  body LONGTEXT NOT NULL,
  INDEX idx_wearable_audit_site (site_id)
);

CREATE TABLE IF NOT EXISTS wearable_idempotency (
  idem_key VARCHAR(512) NOT NULL PRIMARY KEY,
  body LONGTEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS wearable_document (
  doc_key VARCHAR(64) NOT NULL PRIMARY KEY,
  body LONGTEXT NOT NULL
);
