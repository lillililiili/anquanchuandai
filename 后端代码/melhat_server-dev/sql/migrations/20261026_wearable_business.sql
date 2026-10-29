-- SQL business authority. Idempotent schema; no sample rows and no destructive DDL.
CREATE TABLE IF NOT EXISTS wearable_business_meta (
 namespace VARCHAR(32) NOT NULL PRIMARY KEY, revision BIGINT NOT NULL,
 imported_from VARCHAR(1024), import_sha256 VARCHAR(64), imported_at BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS wearable_business_document (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL,
 value_type VARCHAR(16) NOT NULL, body LONGTEXT,
 PRIMARY KEY(namespace,collection_key)
);
CREATE TABLE IF NOT EXISTS wearable_device_report (
 sequence BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, receipt_id VARCHAR(128) NOT NULL,
 protocol VARCHAR(64) NOT NULL, device_id VARCHAR(128) NOT NULL,
 received_at BIGINT NOT NULL, processed_at BIGINT, body LONGTEXT NOT NULL,
 UNIQUE KEY wearable_report_receipt(receipt_id),
 INDEX wearable_report_pending(processed_at,sequence), INDEX wearable_report_device(device_id,received_at)
);
CREATE TABLE IF NOT EXISTS wearable_projection (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_0_device(device_id,observed_at), INDEX wb_0_person(person_id,observed_at),
 INDEX wb_0_site(site_id,area_id), INDEX wb_0_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_device_state (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_1_device(device_id,observed_at), INDEX wb_1_person(person_id,observed_at),
 INDEX wb_1_site(site_id,area_id), INDEX wb_1_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_location (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_2_device(device_id,observed_at), INDEX wb_2_person(person_id,observed_at),
 INDEX wb_2_site(site_id,area_id), INDEX wb_2_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_event (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_3_device(device_id,observed_at), INDEX wb_3_person(person_id,observed_at),
 INDEX wb_3_site(site_id,area_id), INDEX wb_3_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_event_operation (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_4_device(device_id,observed_at), INDEX wb_4_person(person_id,observed_at),
 INDEX wb_4_site(site_id,area_id), INDEX wb_4_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_assistance (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_5_device(device_id,observed_at), INDEX wb_5_person(person_id,observed_at),
 INDEX wb_5_site(site_id,area_id), INDEX wb_5_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_work (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_6_device(device_id,observed_at), INDEX wb_6_person(person_id,observed_at),
 INDEX wb_6_site(site_id,area_id), INDEX wb_6_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_fence (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_7_device(device_id,observed_at), INDEX wb_7_person(person_id,observed_at),
 INDEX wb_7_site(site_id,area_id), INDEX wb_7_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_fence_record (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_8_device(device_id,observed_at), INDEX wb_8_person(person_id,observed_at),
 INDEX wb_8_site(site_id,area_id), INDEX wb_8_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_group (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_9_device(device_id,observed_at), INDEX wb_9_person(person_id,observed_at),
 INDEX wb_9_site(site_id,area_id), INDEX wb_9_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_vital (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_10_device(device_id,observed_at), INDEX wb_10_person(person_id,observed_at),
 INDEX wb_10_site(site_id,area_id), INDEX wb_10_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_business_audit (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_11_device(device_id,observed_at), INDEX wb_11_person(person_id,observed_at),
 INDEX wb_11_site(site_id,area_id), INDEX wb_11_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_communication (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_12_device(device_id,observed_at), INDEX wb_12_person(person_id,observed_at),
 INDEX wb_12_site(site_id,area_id), INDEX wb_12_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_media_asset (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_13_device(device_id,observed_at), INDEX wb_13_person(person_id,observed_at),
 INDEX wb_13_site(site_id,area_id), INDEX wb_13_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_media_account (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_14_device(device_id,observed_at), INDEX wb_14_person(person_id,observed_at),
 INDEX wb_14_site(site_id,area_id), INDEX wb_14_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_device_command (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_15_device(device_id,observed_at), INDEX wb_15_person(person_id,observed_at),
 INDEX wb_15_site(site_id,area_id), INDEX wb_15_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_media_stream (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_16_device(device_id,observed_at), INDEX wb_16_person(person_id,observed_at),
 INDEX wb_16_site(site_id,area_id), INDEX wb_16_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_business_extra (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_17_device(device_id,observed_at), INDEX wb_17_person(person_id,observed_at),
 INDEX wb_17_site(site_id,area_id), INDEX wb_17_event(event_id)
);
CREATE TABLE IF NOT EXISTS wearable_event_action (
 namespace VARCHAR(32) NOT NULL, collection_key VARCHAR(64) NOT NULL, record_key VARCHAR(512) NOT NULL,
 record_id VARCHAR(128), device_id VARCHAR(128), person_id VARCHAR(128), site_id VARCHAR(128),
 area_id VARCHAR(128), event_id VARCHAR(128), source VARCHAR(64), observed_at BIGINT,
 sort_order INT NOT NULL, body LONGTEXT NOT NULL,
 PRIMARY KEY(namespace,collection_key,record_key),
 INDEX wb_18_device(device_id,observed_at), INDEX wb_18_person(person_id,observed_at),
 INDEX wb_18_site(site_id,area_id), INDEX wb_18_event(event_id)
);

-- Shared client policy, evidence, integrations and durable maintenance control.
CREATE TABLE IF NOT EXISTS wearable_business_config (id INT PRIMARY KEY, version INT NOT NULL, body LONGTEXT NOT NULL);
CREATE TABLE IF NOT EXISTS wearable_feature_acceptance (device_id VARCHAR(100) NOT NULL, feature_key VARCHAR(40) NOT NULL, evidence VARCHAR(500) NOT NULL, PRIMARY KEY(device_id,feature_key));
CREATE TABLE IF NOT EXISTS external_integration (id VARCHAR(100) PRIMARY KEY,site_id VARCHAR(100) NOT NULL,kind VARCHAR(40) NOT NULL,version INT NOT NULL,body LONGTEXT NOT NULL);
CREATE TABLE IF NOT EXISTS external_data_record (id VARCHAR(100) PRIMARY KEY,integration_id VARCHAR(100) NOT NULL,site_id VARCHAR(100) NOT NULL,kind VARCHAR(40) NOT NULL,direction VARCHAR(12) NOT NULL,external_key VARCHAR(100) NOT NULL,received_at VARCHAR(40) NOT NULL,status VARCHAR(40) NOT NULL,body LONGTEXT NOT NULL,UNIQUE(integration_id,kind,direction,external_key));
CREATE TABLE IF NOT EXISTS wearable_runtime_control (control_key VARCHAR(32) PRIMARY KEY,mode VARCHAR(16) NOT NULL,updated_at BIGINT NOT NULL,updated_by VARCHAR(128));
