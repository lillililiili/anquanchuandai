-- DM8 explicit schema. No source data.
CREATE TABLE sys_dept (
 dept_id           bigint      IDENTITY(1,1) NOT NULL,
 parent_id         bigint      default 0,
 ancestors         varchar(50)     default '',
 dept_name         varchar(30)     default '',
 dept_code varchar(64),
 order_num         int          default 0,
 leader            varchar(20)     default null,
 phone             varchar(11)     default null,
 email             varchar(50)     default null,
 status            char(1)         default '0',
 del_flag          char(1)         default '0',
 create_by         varchar(64)     default '',
 create_time 	    TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 primary key (dept_id)
);
CREATE TABLE sys_user (
 user_id           bigint      IDENTITY(1,1) NOT NULL,
 dept_id           bigint      default null,
 user_name         varchar(30)     not null,
 nick_name         varchar(30)     not null,
 user_type         varchar(2)      default '00',
 email             varchar(50)     default '',
 phonenumber       varchar(11)     default '',
 sex               char(1)         default '0',
 avatar            varchar(100)    default '',
 password          varchar(100)    default '',
 status            char(1)         default '0',
 del_flag          char(1)         default '0',
 login_ip          varchar(128)    default '',
 login_date        TIMESTAMP,
 create_by         varchar(64)     default '',
 create_time       TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 remark            varchar(500)    default null,
 result            varchar(20)     default null,
 approver          varchar(64)     default null,
 approval_time     TIMESTAMP,
 birthday          varchar(20)     default null,
 identification_card varchar(32)   default null,
 wechat            varchar(64)     default null,
 native_place      varchar(255)    default null,
 address           varchar(500)    default null,
 card_is           varchar(255)    default null,
 card_the          varchar(255)    default null,
 shackup_card      varchar(255)    default null,
 electronic_signature CLOB,
 sip_id            varchar(64)     default null,
 assist_group      varchar(500)    default null,
 primary key (user_id)
);
CREATE TABLE sys_post (
 post_id       bigint      IDENTITY(1,1) NOT NULL,
 post_code     varchar(64)     not null,
 post_name     varchar(50)     not null,
 post_sort     int          not null,
 status        char(1)         not null,
 create_by     varchar(64)     default '',
 create_time   TIMESTAMP,
 update_by     varchar(64)     default '',
 update_time   TIMESTAMP,
 remark        varchar(500)    default null,
 primary key (post_id)
);
CREATE TABLE sys_role (
 role_id              bigint      IDENTITY(1,1) NOT NULL,
 role_name            varchar(30)     not null,
 role_key             varchar(100)    not null,
 role_sort            int          not null,
 data_scope           char(1)         default '1',
 menu_check_strictly  SMALLINT      default 1,
 dept_check_strictly  SMALLINT      default 1,
 status               char(1)         not null,
 del_flag             char(1)         default '0',
 create_by            varchar(64)     default '',
 create_time          TIMESTAMP,
 update_by            varchar(64)     default '',
 update_time          TIMESTAMP,
 remark               varchar(500)    default null,
 primary key (role_id)
);
CREATE TABLE sys_menu (
 menu_id           bigint      IDENTITY(1,1) NOT NULL,
 menu_name         varchar(50)     not null,
 parent_id         bigint      default 0,
 order_num         int          default 0,
 path              varchar(200)    default '',
 component         varchar(255)    default null,
 query             varchar(255)    default null,
 is_frame          int          default 1,
 is_cache          int          default 0,
 menu_type         char(1)         default '',
 visible           char(1)         default 0,
 status            char(1)         default 0,
 perms             varchar(100)    default null,
 icon              varchar(100)    default '#',
 create_by         varchar(64)     default '',
 create_time       TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 remark            varchar(500)    default '',
 primary key (menu_id)
);
CREATE TABLE sys_user_role (
 user_id   bigint not null,
 role_id   bigint not null,
 primary key(user_id, role_id)
);
CREATE TABLE sys_role_menu (
 role_id   bigint not null,
 menu_id   bigint not null,
 primary key(role_id, menu_id)
);
CREATE TABLE sys_role_dept (
 role_id   bigint not null,
 dept_id   bigint not null,
 primary key(role_id, dept_id)
);
CREATE TABLE sys_user_post (
 user_id   bigint not null,
 post_id   bigint not null,
 primary key (user_id, post_id)
);
CREATE TABLE sys_oper_log (
 oper_id           bigint      IDENTITY(1,1) NOT NULL,
 title             varchar(50)     default '',
 business_type     int          default 0,
 method            varchar(100)    default '',
 request_method    varchar(10)     default '',
 operator_type     int          default 0,
 oper_name         varchar(50)     default '',
 dept_name         varchar(50)     default '',
 oper_url          varchar(255)    default '',
 oper_ip           varchar(128)    default '',
 oper_location     varchar(255)    default '',
 oper_param        varchar(2000)   default '',
 json_result       varchar(2000)   default '',
 status            int          default 0,
 error_msg         varchar(2000)   default '',
 oper_time         TIMESTAMP,
 cost_time         bigint      default 0,
 primary key (oper_id)
);
CREATE INDEX idx_sys_oper_log_bt ON sys_oper_log(business_type);
CREATE INDEX idx_sys_oper_log_s ON sys_oper_log(status);
CREATE INDEX idx_sys_oper_log_ot ON sys_oper_log(oper_time);
CREATE TABLE sys_dict_type (
 dict_id          bigint      IDENTITY(1,1) NOT NULL,
 dict_name        varchar(100)    default '',
 dict_type        varchar(100)    default '',
 status           char(1)         default '0',
 create_by        varchar(64)     default '',
 create_time      TIMESTAMP,
 update_by        varchar(64)     default '',
 update_time      TIMESTAMP,
 remark           varchar(500)    default null,
 primary key (dict_id),
 unique (dict_type)
);
CREATE TABLE sys_dict_data (
 dict_code        bigint      IDENTITY(1,1) NOT NULL,
 dict_sort        int          default 0,
 dict_label       varchar(100)    default '',
 dict_value       varchar(100)    default '',
 dict_type        varchar(100)    default '',
 css_class        varchar(100)    default null,
 list_class       varchar(100)    default null,
 is_default       char(1)         default 'N',
 status           char(1)         default '0',
 create_by        varchar(64)     default '',
 create_time      TIMESTAMP,
 update_by        varchar(64)     default '',
 update_time      TIMESTAMP,
 remark           varchar(500)    default null,
 primary key (dict_code)
);
CREATE TABLE sys_config (
 config_id         int          IDENTITY(1,1) NOT NULL,
 config_name       varchar(100)    default '',
 config_key        varchar(100)    default '',
 config_value      varchar(500)    default '',
 config_type       char(1)         default 'N',
 create_by         varchar(64)     default '',
 create_time       TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 remark            varchar(500)    default null,
 primary key (config_id)
);
CREATE TABLE sys_logininfor (
 info_id        bigint     IDENTITY(1,1) NOT NULL,
 user_name      varchar(50)    default '',
 ipaddr         varchar(128)   default '',
 login_location varchar(255)   default '',
 browser        varchar(50)    default '',
 os             varchar(50)    default '',
 status         char(1)        default '0',
 msg            varchar(255)   default '',
 login_time     TIMESTAMP,
 primary key (info_id)
);
CREATE INDEX idx_sys_logininfor_s ON sys_logininfor(status);
CREATE INDEX idx_sys_logininfor_lt ON sys_logininfor(login_time);
CREATE TABLE sys_job (
 job_id              bigint    IDENTITY(1,1) NOT NULL,
 job_name            varchar(64)   default '',
 job_group           varchar(64)   default 'DEFAULT',
 invoke_target       varchar(500)  not null,
 cron_expression     varchar(255)  default '',
 misfire_policy      varchar(20)   default '3',
 concurrent          char(1)       default '1',
 status              char(1)       default '0',
 create_by           varchar(64)   default '',
 create_time         TIMESTAMP,
 update_by           varchar(64)   default '',
 update_time         TIMESTAMP,
 remark              varchar(500)  default '',
 primary key (job_id, job_name, job_group)
);
CREATE TABLE sys_job_log (
 job_log_id          bigint     IDENTITY(1,1) NOT NULL,
 job_name            varchar(64)    not null,
 job_group           varchar(64)    not null,
 invoke_target       varchar(500)   not null,
 job_message         varchar(500),
 status              char(1)        default '0',
 exception_info      varchar(2000)  default '',
 create_time         TIMESTAMP,
 primary key (job_log_id)
);
CREATE TABLE sys_notice (
 notice_id         int          IDENTITY(1,1) NOT NULL,
 notice_title      varchar(50)     not null,
 notice_type       char(1)         not null,
 notice_content    longblob        default null,
 status            char(1)         default '0',
 create_by         varchar(64)     default '',
 create_time       TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 remark            varchar(255)    default null,
 primary key (notice_id)
);
CREATE TABLE gen_table (
 table_id          bigint      IDENTITY(1,1) NOT NULL,
 table_name        varchar(200)    default '',
 table_comment     varchar(500)    default '',
 sub_table_name    varchar(64)     default null,
 sub_table_fk_name varchar(64)     default null,
 class_name        varchar(100)    default '',
 tpl_category      varchar(200)    default 'crud',
 package_name      varchar(100),
 module_name       varchar(30),
 business_name     varchar(30),
 function_name     varchar(50),
 function_author   varchar(50),
 gen_type          char(1)         default '0',
 gen_path          varchar(200)    default '/',
 options           varchar(1000),
 create_by         varchar(64)     default '',
 create_time 	    TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 remark            varchar(500)    default null,
 primary key (table_id)
);
CREATE TABLE gen_table_column (
 column_id         bigint      IDENTITY(1,1) NOT NULL,
 table_id          varchar(64),
 column_name       varchar(200),
 column_comment    varchar(500),
 column_type       varchar(100),
 java_type         varchar(500),
 java_field        varchar(200),
 is_pk             char(1),
 is_increment      char(1),
 is_required       char(1),
 is_insert         char(1),
 is_edit           char(1),
 is_list           char(1),
 is_query          char(1),
 query_type        varchar(200)    default 'EQ',
 html_type         varchar(200),
 dict_type         varchar(200)    default '',
 sort              int,
 create_by         varchar(64)     default '',
 create_time 	    TIMESTAMP,
 update_by         varchar(64)     default '',
 update_time       TIMESTAMP,
 primary key (column_id)
);
CREATE TABLE group_info (
 id bigint IDENTITY(1,1) NOT NULL,
 group_name varchar(100) NOT NULL,
 group_desc varchar(500) DEFAULT NULL,
 safety_count int DEFAULT 0,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_group_name ON group_info(group_name);
CREATE TABLE safety_hat_info (
 id bigint IDENTITY(1,1) NOT NULL,
 hat_number varchar(64) NOT NULL,
 bind_user_id bigint DEFAULT NULL,
 bind_user_name varchar(64) DEFAULT NULL,
 bind_group_id bigint DEFAULT NULL,
 bind_group varchar(100) DEFAULT NULL,
 bind_time TIMESTAMP DEFAULT NULL,
 status varchar(20) DEFAULT 'offline',
 cpu_usage decimal(10,2) DEFAULT 0,
 storage_usage decimal(10,2) DEFAULT 0,
 electricity_usage decimal(10,2) DEFAULT 0,
 alarm_count int DEFAULT 0,
 video_url varchar(500) DEFAULT NULL,
 rtc_play_config CLOB,
 uid varchar(64) DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id),
 CONSTRAINT uk_hat_number UNIQUE (hat_number)
);
CREATE INDEX idx_hat_user ON safety_hat_info(bind_user_id);
CREATE INDEX idx_hat_group ON safety_hat_info(bind_group_id);
CREATE INDEX idx_hat_status ON safety_hat_info(status);
CREATE TABLE safety_hat_location_record (
 id bigint IDENTITY(1,1) NOT NULL,
 hat_id bigint NOT NULL,
 hat_number varchar(64) NOT NULL,
 user_id bigint DEFAULT NULL,
 user_name varchar(64) DEFAULT NULL,
 lng varchar(32) DEFAULT NULL,
 lat varchar(32) DEFAULT NULL,
 speed varchar(32) DEFAULT NULL,
 timestamp varchar(32) DEFAULT NULL,
 altitude varchar(32) DEFAULT NULL,
 del_flag int DEFAULT 0,
 create_time TIMESTAMP DEFAULT NULL,
 create_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 PRIMARY KEY (id)
);
CREATE INDEX idx_location_hat_time ON safety_hat_location_record(hat_id, timestamp);
CREATE INDEX idx_location_user ON safety_hat_location_record(user_id);
CREATE TABLE electronic_fence (
 id bigint IDENTITY(1,1) NOT NULL,
 fence_name varchar(100) NOT NULL,
 fence_type varchar(32) DEFAULT NULL,
 fence_shape varchar(16) DEFAULT '0',
 alert_count int DEFAULT 0,
 status int DEFAULT 1,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_fence_name ON electronic_fence(fence_name);
CREATE INDEX idx_fence_type_status ON electronic_fence(fence_type, status);
CREATE TABLE electronic_fence_latitude (
 id bigint IDENTITY(1,1) NOT NULL,
 fence_id bigint NOT NULL,
 longitude decimal(10,6) DEFAULT NULL,
 latitude decimal(10,6) DEFAULT NULL,
 create_time TIMESTAMP DEFAULT NULL,
 update_time TIMESTAMP DEFAULT NULL,
 del_flag int DEFAULT 0,
 create_by varchar(64) DEFAULT '',
 update_by varchar(64) DEFAULT '',
 PRIMARY KEY (id)
);
CREATE INDEX idx_fence_latitude_fence ON electronic_fence_latitude(fence_id);
CREATE TABLE electronic_fence_alarm (
 id bigint IDENTITY(1,1) NOT NULL,
 user_id bigint DEFAULT NULL,
 user_name varchar(64) DEFAULT NULL,
 hat_number varchar(64) DEFAULT NULL,
 hat_id bigint DEFAULT NULL,
 fence_id bigint DEFAULT NULL,
 alarm_type varchar(32) DEFAULT NULL,
 alarm_start_time TIMESTAMP DEFAULT NULL,
 alarm_end_time TIMESTAMP DEFAULT NULL,
 description varchar(1000) DEFAULT NULL,
 is_handled int DEFAULT 0,
 handle_time TIMESTAMP DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_fence_alarm_hat_time ON electronic_fence_alarm(hat_id, alarm_start_time);
CREATE INDEX idx_fence_alarm_fence_time ON electronic_fence_alarm(fence_id, alarm_start_time);
CREATE INDEX idx_fence_alarm_user ON electronic_fence_alarm(user_id);
CREATE INDEX idx_fence_alarm_type_handled ON electronic_fence_alarm(alarm_type, is_handled);
CREATE TABLE real_time_alarm (
 id bigint IDENTITY(1,1) NOT NULL,
 user_id bigint DEFAULT NULL,
 user_name varchar(64) DEFAULT NULL,
 hat_number varchar(64) DEFAULT NULL,
 hat_id bigint DEFAULT NULL,
 alarm_type varchar(32) DEFAULT NULL,
 alarm_level varchar(16) DEFAULT NULL,
 alarm_start_time TIMESTAMP DEFAULT NULL,
 alarm_end_time TIMESTAMP DEFAULT NULL,
 description varchar(1000) DEFAULT NULL,
 is_handled int DEFAULT 0,
 handle_time TIMESTAMP DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_realtime_alarm_hat_time ON real_time_alarm(hat_id, alarm_start_time);
CREATE INDEX idx_realtime_alarm_user ON real_time_alarm(user_id);
CREATE INDEX idx_realtime_alarm_handled ON real_time_alarm(is_handled);
CREATE TABLE sos_alarm_record (
 id bigint IDENTITY(1,1) NOT NULL,
 user_id bigint DEFAULT NULL,
 user_name varchar(64) DEFAULT NULL,
 hat_id bigint DEFAULT NULL,
 hat_number varchar(64) DEFAULT NULL,
 lng varchar(32) DEFAULT NULL,
 lat varchar(32) DEFAULT NULL,
 call_time TIMESTAMP DEFAULT NULL,
 description varchar(1000) DEFAULT NULL,
 process_status SMALLINT DEFAULT 0,
 handler varchar(64) DEFAULT NULL,
 handle_time TIMESTAMP DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_sos_hat_time ON sos_alarm_record(hat_id, call_time);
CREATE INDEX idx_sos_user ON sos_alarm_record(user_id);
CREATE INDEX idx_sos_process ON sos_alarm_record(process_status);
CREATE TABLE file_record (
 id bigint IDENTITY(1,1) NOT NULL,
 file_name varchar(255) NOT NULL,
 file_type varchar(32) DEFAULT NULL,
 file_url varchar(500) DEFAULT NULL,
 hat_id bigint DEFAULT NULL,
 hat_number varchar(64) DEFAULT NULL,
 user_name varchar(64) DEFAULT NULL,
 file_size decimal(10,2) DEFAULT 0,
 upload_time TIMESTAMP DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_file_hat_upload ON file_record(hat_id, upload_time);
CREATE INDEX idx_file_type_upload ON file_record(file_type, upload_time);
CREATE INDEX idx_file_name ON file_record(file_name);
CREATE TABLE intercom_record (
 id bigint IDENTITY(1,1) NOT NULL,
 intercom_type varchar(16) DEFAULT NULL,
 hat_number varchar(500) DEFAULT NULL,
 participant varchar(500) DEFAULT NULL,
 recipient_count int DEFAULT 0,
 start_time TIMESTAMP DEFAULT NULL,
 end_time TIMESTAMP DEFAULT NULL,
 duration varchar(32) DEFAULT NULL,
 record_path varchar(500) DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_intercom_type_time ON intercom_record(intercom_type, start_time);
CREATE INDEX idx_intercom_start_time ON intercom_record(start_time);
CREATE TABLE tts_text_synthesis_broadcast (
 id bigint IDENTITY(1,1) NOT NULL,
 broadcast_type varchar(16) DEFAULT NULL,
 hat_number varchar(500) DEFAULT NULL,
 recipient varchar(500) DEFAULT NULL,
 recipient_count int DEFAULT 0,
 send_time TIMESTAMP DEFAULT NULL,
 content CLOB,
 operator varchar(64) DEFAULT NULL,
 del_flag char(1) DEFAULT '0',
 create_by varchar(64) DEFAULT '',
 create_time TIMESTAMP DEFAULT NULL,
 update_by varchar(64) DEFAULT '',
 update_time TIMESTAMP DEFAULT NULL,
 PRIMARY KEY (id)
);
CREATE INDEX idx_tts_type_time ON tts_text_synthesis_broadcast(broadcast_type, send_time);
CREATE INDEX idx_tts_send_time ON tts_text_synthesis_broadcast(send_time);
CREATE TABLE demo_compat_record (
 id bigint IDENTITY(1,1) NOT NULL,
 module_key varchar(40) NOT NULL,
 business_key varchar(80) NOT NULL,
 payload json NOT NULL,
 create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (id),
 CONSTRAINT uk_demo_module_business UNIQUE (module_key, business_key)
);
CREATE INDEX idx_demo_module ON demo_compat_record(module_key);
CREATE TABLE QRTZ_JOB_DETAILS (
 sched_name           varchar(120)    not null,
 job_name             varchar(200)    not null,
 job_group            varchar(200)    not null,
 description          varchar(250)    null,
 job_class_name       varchar(250)    not null,
 is_durable           varchar(1)      not null,
 is_nonconcurrent     varchar(1)      not null,
 is_update_data       varchar(1)      not null,
 requests_recovery    varchar(1)      not null,
 job_data             blob            null,
 primary key (sched_name, job_name, job_group)
);
CREATE TABLE QRTZ_TRIGGERS (
 sched_name           varchar(120)    not null,
 trigger_name         varchar(200)    not null,
 trigger_group        varchar(200)    not null,
 job_name             varchar(200)    not null,
 job_group            varchar(200)    not null,
 description          varchar(250)    null,
 next_fire_time       bigint      null,
 prev_fire_time       bigint      null,
 priority             integer         null,
 trigger_state        varchar(16)     not null,
 trigger_type         varchar(8)      not null,
 start_time           bigint      not null,
 end_time             bigint      null,
 calendar_name        varchar(200)    null,
 misfire_instr        smallint     null,
 job_data             blob            null,
 primary key (sched_name, trigger_name, trigger_group),
 foreign key (sched_name, job_name, job_group) references QRTZ_JOB_DETAILS(sched_name, job_name, job_group)
);
CREATE TABLE QRTZ_SIMPLE_TRIGGERS (
 sched_name           varchar(120)    not null,
 trigger_name         varchar(200)    not null,
 trigger_group        varchar(200)    not null,
 repeat_count         bigint       not null,
 repeat_interval      bigint      not null,
 times_triggered      bigint      not null,
 primary key (sched_name, trigger_name, trigger_group),
 foreign key (sched_name, trigger_name, trigger_group) references QRTZ_TRIGGERS(sched_name, trigger_name, trigger_group)
);
CREATE TABLE QRTZ_CRON_TRIGGERS (
 sched_name           varchar(120)    not null,
 trigger_name         varchar(200)    not null,
 trigger_group        varchar(200)    not null,
 cron_expression      varchar(200)    not null,
 time_zone_id         varchar(80),
 primary key (sched_name, trigger_name, trigger_group),
 foreign key (sched_name, trigger_name, trigger_group) references QRTZ_TRIGGERS(sched_name, trigger_name, trigger_group)
);
CREATE TABLE QRTZ_BLOB_TRIGGERS (
 sched_name           varchar(120)    not null,
 trigger_name         varchar(200)    not null,
 trigger_group        varchar(200)    not null,
 blob_data            blob            null,
 primary key (sched_name, trigger_name, trigger_group),
 foreign key (sched_name, trigger_name, trigger_group) references QRTZ_TRIGGERS(sched_name, trigger_name, trigger_group)
);
CREATE TABLE QRTZ_CALENDARS (
 sched_name           varchar(120)    not null,
 calendar_name        varchar(200)    not null,
 calendar             blob            not null,
 primary key (sched_name, calendar_name)
);
CREATE TABLE QRTZ_PAUSED_TRIGGER_GRPS (
 sched_name           varchar(120)    not null,
 trigger_group        varchar(200)    not null,
 primary key (sched_name, trigger_group)
);
CREATE TABLE QRTZ_FIRED_TRIGGERS (
 sched_name           varchar(120)    not null,
 entry_id             varchar(95)     not null,
 trigger_name         varchar(200)    not null,
 trigger_group        varchar(200)    not null,
 instance_name        varchar(200)    not null,
 fired_time           bigint      not null,
 sched_time           bigint      not null,
 priority             integer         not null,
 state                varchar(16)     not null,
 job_name             varchar(200)    null,
 job_group            varchar(200)    null,
 is_nonconcurrent     varchar(1)      null,
 requests_recovery    varchar(1)      null,
 primary key (sched_name, entry_id)
);
CREATE TABLE QRTZ_SCHEDULER_STATE (
 sched_name           varchar(120)    not null,
 instance_name        varchar(200)    not null,
 last_checkin_time    bigint      not null,
 checkin_interval     bigint      not null,
 primary key (sched_name, instance_name)
);
CREATE TABLE QRTZ_LOCKS (
 sched_name           varchar(120)    not null,
 lock_name            varchar(40)     not null,
 primary key (sched_name, lock_name)
);
CREATE TABLE QRTZ_SIMPROP_TRIGGERS (
 sched_name           varchar(120)    not null,
 trigger_name         varchar(200)    not null,
 trigger_group        varchar(200)    not null,
 str_prop_1           varchar(512)    null,
 str_prop_2           varchar(512)    null,
 str_prop_3           varchar(512)    null,
 int_prop_1           int             null,
 int_prop_2           int             null,
 long_prop_1          bigint          null,
 long_prop_2          bigint          null,
 dec_prop_1           numeric(13,4)   null,
 dec_prop_2           numeric(13,4)   null,
 bool_prop_1          varchar(1)      null,
 bool_prop_2          varchar(1)      null,
 primary key (sched_name, trigger_name, trigger_group),
 foreign key (sched_name, trigger_name, trigger_group) references QRTZ_TRIGGERS(sched_name, trigger_name, trigger_group)
);
