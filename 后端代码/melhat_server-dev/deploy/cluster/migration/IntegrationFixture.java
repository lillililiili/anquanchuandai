import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import com.ruoyi.common.database.DatabaseDialect;
import com.ruoyi.database.SchemaLifecycle;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;

/** Opt-in disposable real-database fixture. Credentials are only read from the private configuration. */
public class IntegrationFixture {
    static String phase="initial";
    public static void main(String[] args)throws Exception{
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        try{
            ObjectNode config=(ObjectNode)MigrationTool.JSON.readTree(Files.readString(Path.of(args[1])));
            String schema=config.path("schema").asText();MigrationTool.require(schema.toLowerCase(Locale.ROOT).startsWith("wearable_migration_"),"DISPOSABLE_SCHEMA_REQUIRED");
            DatabaseDialect.identifier(schema);
            if(args[0].equals("provision")){provision(config);System.out.println("PASS: disposable schema provisioned.");return;}
            JdbcTemplate jdbc=jdbc(config,false);DatabaseDialect d=DatabaseDialect.valueOf(config.path("product").asText().toUpperCase(Locale.ROOT));
            if(args[0].equals("initialize")){
                phase="schema";new SchemaLifecycle(jdbc).migrate(SchemaLifecycle.all(d));new SchemaLifecycle(jdbc).validate(SchemaLifecycle.all(d));
            }else if(args[0].equals("seed")){
                MigrationTool.require(d==DatabaseDialect.MYSQL,"FIXTURE_SOURCE_MUST_BE_MYSQL");seed(jdbc,config);
            }else if(args[0].equals("assert-generated")){
                phase="generated-key";
                jdbc.update("INSERT INTO wearable_device_report(receipt_id,protocol,device_id,received_at,body) VALUES ('after-import','fixture','900000000000001',1,'{}')");
                Long key=jdbc.queryForObject("SELECT sequence FROM wearable_device_report WHERE receipt_id='after-import'",Long.class);
                MigrationTool.require(key>8000000000000L,"DELETED_ID_WATERMARK_LOST");
                jdbc.update("DELETE FROM wearable_device_report WHERE receipt_id='after-import'");
                jdbc.update("INSERT INTO sys_notice(notice_title,notice_type) VALUES ('after-import','1')");
                key=jdbc.queryForObject("SELECT notice_id FROM sys_notice WHERE notice_title='after-import'",Long.class);
                MigrationTool.require(key>1000000,"INT_IDENTITY_WATERMARK_LOST");jdbc.update("DELETE FROM sys_notice WHERE notice_title='after-import'");
                MigrationTool.require(jdbc.queryForObject("SELECT COUNT(*) FROM sys_dept WHERE dept_id=0",Integer.class)==1,"ZERO_ID_LOST");
            }else throw new IllegalArgumentException();
            System.out.println("PASS: disposable fixture "+args[0]+" completed.");
        }catch(Exception error){
            Throwable root=error;while(root.getCause()!=null)root=root.getCause();
            System.err.println("FAIL: fixture phase="+phase+" class="+root.getClass().getSimpleName()+(root instanceof SQLException?" vendor="+((SQLException)root).getErrorCode():""));System.exit(2);
        }
    }
    static JdbcTemplate jdbc(JsonNode config,boolean admin){
        JsonNode value=admin?config.path("admin"):config;SingleConnectionDataSource source=new SingleConnectionDataSource();source.setSuppressClose(true);
        source.setDriverClassName(config.path("product").asText().equals("dm8")?"dm.jdbc.driver.DmDriver":"com.mysql.cj.jdbc.Driver");
        source.setUrl(value.path("url").asText());source.setUsername(value.path("username").asText());source.setPassword(value.path("password").asText());return new JdbcTemplate(source);
    }
    static void provision(ObjectNode config){
        phase="provision";String user=config.path("username").asText(),schema=config.path("schema").asText(),password=config.path("password").asText();DatabaseDialect.identifier(user);
        MigrationTool.require(user.toLowerCase(Locale.ROOT).startsWith("wearable_migration_")&&password.matches("[A-Za-z0-9_-]{24,64}"),"DISPOSABLE_ACCOUNT_REQUIRED");
        JdbcTemplate admin=jdbc(config,true);
        if(config.path("product").asText().equals("mysql")){
            admin.execute("CREATE DATABASE `"+schema+"` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
            admin.execute("CREATE USER '"+user+"'@'%' IDENTIFIED BY '"+password+"'");
            admin.execute("GRANT ALL PRIVILEGES ON `"+schema+"`.* TO '"+user+"'@'%'");
        }else{
            MigrationTool.require(user.equals(schema),"DM_SCHEMA_USER_MISMATCH");
            admin.execute("CREATE USER "+user+" IDENTIFIED BY \""+password+"\" DEFAULT TABLESPACE MAIN DEFAULT INDEX TABLESPACE MAIN");
            admin.execute("GRANT RESOURCE TO "+user);
            admin.execute("GRANT SELECT ON V$DM_INI TO "+user);
        }
    }
    static void seed(JdbcTemplate j,ObjectNode config)throws Exception{
        phase="seed";
        // One connection is required for session sql_mode and the explicit zero identity.
        j.execute((org.springframework.jdbc.core.ConnectionCallback<Void>)connection->{
            try(Statement s=connection.createStatement()){
                s.execute("SET SESSION sql_mode=CONCAT(@@sql_mode,',NO_AUTO_VALUE_ON_ZERO')");
                s.executeUpdate("INSERT INTO sys_dept(dept_id,dept_name) VALUES (0,'零号部门')");
            }return null;
        });
        j.update("INSERT INTO wearable_runtime_control(control_key,mode,updated_at) VALUES ('global','PAUSED',1)");
        j.update("INSERT INTO wearable_meta(id,revision,next_id) VALUES (1,12,9000000000001)");
        j.update("INSERT INTO wearable_business_meta(namespace,revision,imported_at) VALUES ('guardian',7,1),('media',8,1)");
        j.update("INSERT INTO wearable_business_config(id,version,body) VALUES (1,4,?)","{\"enabled\":true}");
        for(String table:List.of("wearable_site","wearable_device","wearable_person","wearable_assignment","wearable_assignment_history")){
            j.update("INSERT INTO "+table+"(id,sort_order,body) VALUES (?,0,?)",table+"-1","{\"id\":\""+table+"-1\",\"name\":\"中文🪖\",\"large\":\""+"测试".repeat(40000)+"\"}");
        }
        j.update("UPDATE wearable_site SET enabled=1 WHERE id='wearable_site-1'");
        j.update("UPDATE wearable_assignment SET device_id='wearable_device-1',person_id='wearable_person-1',active=1");
        j.update("INSERT INTO wearable_document(doc_key,body) VALUES ('metadata','{\"nextId\":9000000000001}')");
        j.update("INSERT INTO wearable_idempotency(idem_key,body) VALUES ('operation-1','{\"ok\":true,\"revision\":12}')");
        j.update("INSERT INTO helmet_location_fix(id,device_id,person_id,received_at,observed_at,body) VALUES ('fix-1','900000000000001','wearable_person-1',1700000000123,1700000000001,?)","{\"longitude\":118.123456789,\"latitude\":37.123456789}");
        j.update("INSERT INTO wearable_device_report(sequence,receipt_id,protocol,device_id,received_at,processed_at,body) VALUES (42,'report-1','helmet','900000000000001',1700000000123,1700000000456,'{\"bat_l\":90}')");
        j.update("INSERT INTO wearable_device_report(sequence,receipt_id,protocol,device_id,received_at,body) VALUES (8000000000000,'deleted-report','helmet','900000000000001',1,'{}')");
        j.update("DELETE FROM wearable_device_report WHERE receipt_id='deleted-report'");
        j.update("INSERT INTO sys_notice(notice_id,notice_title,notice_type,notice_content,create_time) VALUES (11,'中文公告','1',?,'2026-11-03 01:02:03')","多字节🪖".getBytes(StandardCharsets.UTF_8));
        j.update("INSERT INTO sys_notice(notice_id,notice_title,notice_type) VALUES (1000000,'deleted-notice','1')");j.update("DELETE FROM sys_notice WHERE notice_id=1000000");
        j.update("UPDATE fuda_alarm_journal_state SET committed_sequence=7,retained_floor=1,backfill_completed_at=1700000000000 WHERE id=1");
        j.update("INSERT INTO fuda_alarm_journal(export_sequence,event_id,event_hash,device_key,scope_hash,internal_device_id,recorded_at,body) VALUES (7,'event-1',?,'helmet:900000000000001',?,'wearable_device-1',1700000000000,'{\"status\":\"OPEN\"}')","a".repeat(64),"b".repeat(64));
        j.update("INSERT INTO fuda_push_outbox(event_id,destination_key,destination_id,ledger_device_id,device_type,device_id,device_key,event_type,body,status,next_attempt_at,created_at) VALUES ('event-1',?,'fixture','wearable_device-1','helmet','900000000000001',?,'SOS','{\"fixture\":true}','PENDING',1700000000100,1700000000000)","c".repeat(64),"d".repeat(64));
        String id="upload-4efbb82e-8561-4730-a561-e1b33afc5912",filename=id+"-new.png";
        Path shared=Path.of(config.path("sharedRoot").asText());byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==");
        Files.write(shared.resolve("files").resolve(filename),png,StandardOpenOption.CREATE_NEW);
        Files.write(shared.resolve("files").resolve(id+"-old.jpg"),new byte[]{(byte)255,(byte)216,(byte)255,(byte)217},StandardOpenOption.CREATE_NEW);
        Files.createDirectories(shared.resolve("upload/photos"));Files.write(shared.resolve("upload/photos/fixture.png"),png,StandardOpenOption.CREATE_NEW);
        j.update("INSERT INTO guardian_file_publication(file_id,file_name,content_type,sha256,byte_length) VALUES (?,?,'image/png',?,?)",id,filename,MigrationTool.sha(png),png.length);
        j.update("INSERT INTO wearable_event(namespace,collection_key,record_key,sort_order,body) VALUES ('guardian','events','event-1',0,?)","{\"id\":\"event-1\",\"photoIds\":[\""+id+"\"],\"reason\":\"测试报警\"}");
        j.update("INSERT INTO file_record(file_name,file_url,file_size) VALUES ('fixture.png','/profile/photos/fixture.png',12.34)");
        String mediaKey=Files.readAllLines(Path.of(config.path("backendEnvFile").asText())).stream().filter(v->v.startsWith("MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=")).findFirst().orElseThrow().split("=",2)[1];
        byte[] nonce=new byte[12];new java.security.SecureRandom().nextBytes(nonce);Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(Base64.getDecoder().decode(mediaKey),"AES"),new GCMParameterSpec(128,nonce));cipher.updateAAD("media\naccounts\naccount-1".getBytes(StandardCharsets.UTF_8));
        byte[] encrypted=cipher.doFinal("{\"username\":\"媒体账户🪖\",\"password\":\"synthetic-only\"}".getBytes(StandardCharsets.UTF_8)),stored=new byte[12+encrypted.length];System.arraycopy(nonce,0,stored,0,12);System.arraycopy(encrypted,0,stored,12,encrypted.length);
        j.update("INSERT INTO wearable_business_document(namespace,collection_key,value_type,body) VALUES ('media','accounts','array',NULL)");
        j.update("INSERT INTO wearable_media_account(namespace,collection_key,record_key,sort_order,body) VALUES ('media','accounts','account-1',0,?)","enc:v1:"+Base64.getEncoder().encodeToString(stored));
        j.update("INSERT INTO wearable_transport_command(command_id,scope_key,fingerprint,device_type,device_id,node_id,generation,connection_token,wire_json,context_json,delivery_status,deadline,created_at,updated_at) VALUES ('command-unknown',?,?,'helmet','900000000000001','retired-node',?,?,'{\"command\":\"fixture\"}','{}','UNKNOWN',1,1,1)","e".repeat(64),"f".repeat(64),UUID.randomUUID().toString(),UUID.randomUUID().toString());
    }
}
