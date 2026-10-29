CREATE TABLE IF NOT EXISTS helmet_location_fix (
 id VARCHAR(40) PRIMARY KEY, device_id VARCHAR(64) NOT NULL, person_id VARCHAR(64) NOT NULL,
 site_id VARCHAR(64), area_id VARCHAR(64), received_at BIGINT NOT NULL, observed_at BIGINT NOT NULL, body LONGTEXT NOT NULL,
 INDEX helmet_location_person (person_id, observed_at), INDEX helmet_location_device (device_id, observed_at)
);
CREATE TABLE IF NOT EXISTS helmet_event_group (
 group_key VARCHAR(64) PRIMARY KEY, open_event_id VARCHAR(64), initial_body LONGTEXT,
 INDEX helmet_event_group_open (open_event_id)
);
CREATE TABLE IF NOT EXISTS helmet_event_link (
 event_id VARCHAR(64) NOT NULL, group_key VARCHAR(64) NOT NULL, source_type VARCHAR(32) NOT NULL, source_record_id BIGINT NOT NULL,
 device_id VARCHAR(64) NOT NULL, received_at BIGINT NOT NULL, body LONGTEXT NOT NULL,
 projected INTEGER NOT NULL DEFAULT 0, closure_version INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY (source_type, source_record_id), INDEX helmet_event_case (event_id),
 INDEX helmet_event_pending (projected, received_at)
);
