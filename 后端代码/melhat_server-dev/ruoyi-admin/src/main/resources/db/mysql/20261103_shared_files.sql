CREATE TABLE IF NOT EXISTS guardian_file_publication (
 file_id VARCHAR(80) PRIMARY KEY,
 file_name VARCHAR(160),
 content_type VARCHAR(40),
 sha256 CHAR(64),
 byte_length BIGINT
);
