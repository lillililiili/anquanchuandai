CREATE TABLE IF NOT EXISTS wear_account_recovery (
 id varchar(36) NOT NULL PRIMARY KEY,
 identifier varchar(100) NOT NULL,
 real_name varchar(80) NOT NULL,
 contact varchar(100) NOT NULL,
 reason varchar(500) NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'pending',
 target_user_id bigint DEFAULT NULL,
 reviewed_by bigint DEFAULT NULL,
 review_reason varchar(500) DEFAULT NULL,
 created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
 reviewed_at datetime DEFAULT NULL,
 KEY idx_recovery_status (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='账号找回与重置审批，不存储密码';
