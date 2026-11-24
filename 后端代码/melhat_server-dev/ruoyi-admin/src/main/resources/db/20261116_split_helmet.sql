CREATE TABLE IF NOT EXISTS split_helmet_inbox (
 ingress_id VARCHAR(100) PRIMARY KEY,device_id VARCHAR(64) NOT NULL,kind VARCHAR(24) NOT NULL,
 received_at BIGINT NOT NULL,fingerprint VARCHAR(64) NOT NULL,body LONGTEXT NOT NULL,projected INT NOT NULL DEFAULT 0,
 INDEX split_inbox_pending(projected,received_at)
);
CREATE TABLE IF NOT EXISTS split_helmet_state (device_id VARCHAR(64) PRIMARY KEY,body LONGTEXT NOT NULL);
CREATE TABLE IF NOT EXISTS split_helmet_session (
 id VARCHAR(64) PRIMARY KEY,actor_id VARCHAR(100) NOT NULL,request_key VARCHAR(64) NOT NULL,
 fingerprint VARCHAR(64) NOT NULL,status VARCHAR(24) NOT NULL,expires_at BIGINT NOT NULL,body LONGTEXT NOT NULL,
 UNIQUE KEY split_session_request(actor_id,request_key),INDEX split_session_expiry(status,expires_at)
);
CREATE TABLE IF NOT EXISTS split_helmet_lease(device_id VARCHAR(64) PRIMARY KEY,session_id VARCHAR(64) NOT NULL);
CREATE TABLE IF NOT EXISTS split_helmet_command (
 id VARCHAR(64) PRIMARY KEY,actor_id VARCHAR(100) NOT NULL,device_id VARCHAR(64) NOT NULL,request_key VARCHAR(64) NOT NULL,
 fingerprint VARCHAR(64) NOT NULL,created_at BIGINT NOT NULL,body LONGTEXT NOT NULL,
 UNIQUE KEY split_command_request(actor_id,request_key),INDEX split_command_device(device_id,created_at)
);
CREATE TABLE IF NOT EXISTS split_helmet_event (
 id BIGINT AUTO_INCREMENT PRIMARY KEY,ingress_id VARCHAR(100) NOT NULL UNIQUE,body LONGTEXT NOT NULL,
 handled INT NOT NULL DEFAULT 0,handled_at BIGINT NULL,handler VARCHAR(100) NULL
);
CREATE TABLE IF NOT EXISTS split_helmet_file (
 id VARCHAR(64) PRIMARY KEY,device_id VARCHAR(64) NOT NULL,file_key VARCHAR(512) NOT NULL,
 observed_at BIGINT NOT NULL,body LONGTEXT NOT NULL,source_url TEXT NULL,refreshed_at BIGINT NOT NULL,
 INDEX split_file_device_time(device_id,observed_at)
);
