-- DM8 explicit schema. No source data.
CREATE TABLE wearable_business_meta (
 namespace VARCHAR(32) NOT NULL PRIMARY KEY,
 revision BIGINT NOT NULL,
 imported_from VARCHAR(1024),
 import_sha256 VARCHAR(64),
 imported_at BIGINT NOT NULL
);
CREATE TABLE wearable_business_document (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 value_type VARCHAR(16) NOT NULL,
 body CLOB,
 PRIMARY KEY(namespace,collection_key)
);
CREATE TABLE wearable_device_report (
 sequence BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
 receipt_id VARCHAR(128) NOT NULL,
 protocol VARCHAR(64) NOT NULL,
 device_id VARCHAR(128) NOT NULL,
 received_at BIGINT NOT NULL,
 processed_at BIGINT,
 body CLOB NOT NULL,
 CONSTRAINT wearable_report_receipt UNIQUE (receipt_id)
);
CREATE INDEX wearable_report_pending ON wearable_device_report(processed_at,sequence);
CREATE INDEX wearable_report_device ON wearable_device_report(device_id,received_at);
CREATE TABLE wearable_projection (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_0_device ON wearable_projection(device_id,observed_at);
CREATE INDEX wb_0_person ON wearable_projection(person_id,observed_at);
CREATE INDEX wb_0_site ON wearable_projection(site_id,area_id);
CREATE INDEX wb_0_event ON wearable_projection(event_id);
CREATE TABLE wearable_device_state (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_1_device ON wearable_device_state(device_id,observed_at);
CREATE INDEX wb_1_person ON wearable_device_state(person_id,observed_at);
CREATE INDEX wb_1_site ON wearable_device_state(site_id,area_id);
CREATE INDEX wb_1_event ON wearable_device_state(event_id);
CREATE TABLE wearable_location (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_2_device ON wearable_location(device_id,observed_at);
CREATE INDEX wb_2_person ON wearable_location(person_id,observed_at);
CREATE INDEX wb_2_site ON wearable_location(site_id,area_id);
CREATE INDEX wb_2_event ON wearable_location(event_id);
CREATE TABLE wearable_event (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_3_device ON wearable_event(device_id,observed_at);
CREATE INDEX wb_3_person ON wearable_event(person_id,observed_at);
CREATE INDEX wb_3_site ON wearable_event(site_id,area_id);
CREATE INDEX wb_3_event ON wearable_event(event_id);
CREATE TABLE wearable_event_operation (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_4_device ON wearable_event_operation(device_id,observed_at);
CREATE INDEX wb_4_person ON wearable_event_operation(person_id,observed_at);
CREATE INDEX wb_4_site ON wearable_event_operation(site_id,area_id);
CREATE INDEX wb_4_event ON wearable_event_operation(event_id);
CREATE TABLE wearable_assistance (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_5_device ON wearable_assistance(device_id,observed_at);
CREATE INDEX wb_5_person ON wearable_assistance(person_id,observed_at);
CREATE INDEX wb_5_site ON wearable_assistance(site_id,area_id);
CREATE INDEX wb_5_event ON wearable_assistance(event_id);
CREATE TABLE wearable_work (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_6_device ON wearable_work(device_id,observed_at);
CREATE INDEX wb_6_person ON wearable_work(person_id,observed_at);
CREATE INDEX wb_6_site ON wearable_work(site_id,area_id);
CREATE INDEX wb_6_event ON wearable_work(event_id);
CREATE TABLE wearable_fence (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_7_device ON wearable_fence(device_id,observed_at);
CREATE INDEX wb_7_person ON wearable_fence(person_id,observed_at);
CREATE INDEX wb_7_site ON wearable_fence(site_id,area_id);
CREATE INDEX wb_7_event ON wearable_fence(event_id);
CREATE TABLE wearable_fence_record (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_8_device ON wearable_fence_record(device_id,observed_at);
CREATE INDEX wb_8_person ON wearable_fence_record(person_id,observed_at);
CREATE INDEX wb_8_site ON wearable_fence_record(site_id,area_id);
CREATE INDEX wb_8_event ON wearable_fence_record(event_id);
CREATE TABLE wearable_group (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_9_device ON wearable_group(device_id,observed_at);
CREATE INDEX wb_9_person ON wearable_group(person_id,observed_at);
CREATE INDEX wb_9_site ON wearable_group(site_id,area_id);
CREATE INDEX wb_9_event ON wearable_group(event_id);
CREATE TABLE wearable_vital (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_10_device ON wearable_vital(device_id,observed_at);
CREATE INDEX wb_10_person ON wearable_vital(person_id,observed_at);
CREATE INDEX wb_10_site ON wearable_vital(site_id,area_id);
CREATE INDEX wb_10_event ON wearable_vital(event_id);
CREATE TABLE wearable_business_audit (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_11_device ON wearable_business_audit(device_id,observed_at);
CREATE INDEX wb_11_person ON wearable_business_audit(person_id,observed_at);
CREATE INDEX wb_11_site ON wearable_business_audit(site_id,area_id);
CREATE INDEX wb_11_event ON wearable_business_audit(event_id);
CREATE TABLE wearable_communication (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_12_device ON wearable_communication(device_id,observed_at);
CREATE INDEX wb_12_person ON wearable_communication(person_id,observed_at);
CREATE INDEX wb_12_site ON wearable_communication(site_id,area_id);
CREATE INDEX wb_12_event ON wearable_communication(event_id);
CREATE TABLE wearable_media_asset (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_13_device ON wearable_media_asset(device_id,observed_at);
CREATE INDEX wb_13_person ON wearable_media_asset(person_id,observed_at);
CREATE INDEX wb_13_site ON wearable_media_asset(site_id,area_id);
CREATE INDEX wb_13_event ON wearable_media_asset(event_id);
CREATE TABLE wearable_media_account (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_14_device ON wearable_media_account(device_id,observed_at);
CREATE INDEX wb_14_person ON wearable_media_account(person_id,observed_at);
CREATE INDEX wb_14_site ON wearable_media_account(site_id,area_id);
CREATE INDEX wb_14_event ON wearable_media_account(event_id);
CREATE TABLE wearable_device_command (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_15_device ON wearable_device_command(device_id,observed_at);
CREATE INDEX wb_15_person ON wearable_device_command(person_id,observed_at);
CREATE INDEX wb_15_site ON wearable_device_command(site_id,area_id);
CREATE INDEX wb_15_event ON wearable_device_command(event_id);
CREATE TABLE wearable_media_stream (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_16_device ON wearable_media_stream(device_id,observed_at);
CREATE INDEX wb_16_person ON wearable_media_stream(person_id,observed_at);
CREATE INDEX wb_16_site ON wearable_media_stream(site_id,area_id);
CREATE INDEX wb_16_event ON wearable_media_stream(event_id);
CREATE TABLE wearable_business_extra (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_17_device ON wearable_business_extra(device_id,observed_at);
CREATE INDEX wb_17_person ON wearable_business_extra(person_id,observed_at);
CREATE INDEX wb_17_site ON wearable_business_extra(site_id,area_id);
CREATE INDEX wb_17_event ON wearable_business_extra(event_id);
CREATE TABLE wearable_event_action (
 namespace VARCHAR(32) NOT NULL,
 collection_key VARCHAR(64) NOT NULL,
 record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128),
 device_id VARCHAR(128),
 person_id VARCHAR(128),
 site_id VARCHAR(128),
 area_id VARCHAR(128),
 event_id VARCHAR(128),
 source VARCHAR(64),
 observed_at BIGINT,
 sort_order INT NOT NULL,
 body CLOB NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key)
);
CREATE INDEX wb_18_device ON wearable_event_action(device_id,observed_at);
CREATE INDEX wb_18_person ON wearable_event_action(person_id,observed_at);
CREATE INDEX wb_18_site ON wearable_event_action(site_id,area_id);
CREATE INDEX wb_18_event ON wearable_event_action(event_id);
CREATE TABLE wearable_business_config (
 id INT PRIMARY KEY,
 version INT NOT NULL,
 body CLOB NOT NULL
);
CREATE TABLE wearable_feature_acceptance (
 device_id VARCHAR(100) NOT NULL,
 feature_key VARCHAR(40) NOT NULL,
 evidence VARCHAR(500) NOT NULL,
 PRIMARY KEY(device_id,feature_key)
);
CREATE TABLE external_integration (
 id VARCHAR(100) PRIMARY KEY,
 site_id VARCHAR(100) NOT NULL,
 kind VARCHAR(40) NOT NULL,
 version INT NOT NULL,
 body CLOB NOT NULL
);
CREATE TABLE external_data_record (
 id VARCHAR(100) PRIMARY KEY,
 integration_id VARCHAR(100) NOT NULL,
 site_id VARCHAR(100) NOT NULL,
 kind VARCHAR(40) NOT NULL,
 direction VARCHAR(12) NOT NULL,
 external_key VARCHAR(100) NOT NULL,
 received_at VARCHAR(40) NOT NULL,
 status VARCHAR(40) NOT NULL,
 body CLOB NOT NULL,
 UNIQUE(integration_id,kind,direction,external_key)
);
CREATE TABLE wearable_runtime_control (
 control_key VARCHAR(32) PRIMARY KEY,
 mode VARCHAR(16) NOT NULL,
 updated_at BIGINT NOT NULL,
 updated_by VARCHAR(128)
);
