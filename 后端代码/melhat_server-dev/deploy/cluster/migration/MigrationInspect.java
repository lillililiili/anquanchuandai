import java.nio.file.*;
import java.sql.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;

/** Readback and controlled faults restricted to the explicit disposable migration fixture schema. */
public class MigrationInspect {
    public static void main(String[] args)throws Exception{
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        var config=MigrationTool.JSON.readTree(Files.readString(Path.of(args[1])));
        String schema=config.path("schema").asText();MigrationTool.require(schema.toLowerCase(Locale.ROOT).startsWith("wearable_migration_"),"DISPOSABLE_SCHEMA_REQUIRED");
        JdbcTemplate j=IntegrationFixture.jdbc(config,false);
        switch(args[0]){
            case "audit-schema" -> {
                com.ruoyi.common.database.DatabaseRuntimeContract.verify(j);
                for(var row:j.queryForList("SELECT version_id,state FROM wearable_schema_history ORDER BY version_id"))System.out.println(row);
                System.out.println("incomplete_steps="+j.queryForObject("SELECT COUNT(*) FROM wearable_schema_step WHERE state<>'COMPLETE'",Integer.class));
            }
            case "assert-crash" -> {
                boolean identity=j.execute((org.springframework.jdbc.core.ConnectionCallback<Boolean>)c->{try(ResultSet fields=c.getMetaData().getColumns(null,schema,"WEARABLE_DEVICE_REPORT","SEQUENCE")){MigrationTool.require(fields.next(),"COLUMN_MISSING");return "YES".equalsIgnoreCase(fields.getString("IS_AUTOINCREMENT"));}});
                MigrationTool.require(!identity&&j.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Integer.class)==1,"CRASH_BARRIER_NOT_DURABLE");
                MigrationTool.require(j.queryForObject("SELECT COUNT(*) FROM wearable_schema_lock WHERE owner IS NOT NULL",Integer.class)==1,"IMPORT_OWNER_NOT_DURABLE");
            }
            case "take-lock", "restore-lock" -> {
                String owner=MigrationTool.JSON.readTree(Files.readString(Path.of(args[2]))).path("owner").asText();String other="bd53cb0e-a16a-4001-9778-af3d06380a37";
                String from=args[0].equals("take-lock")?owner:other,to=args[0].equals("take-lock")?other:owner;
                MigrationTool.require(j.update("UPDATE wearable_schema_lock SET owner=? WHERE id=1 AND owner=?",to,from)==1,"LOCK_INJECTION_PRECONDITION_FAILED");
            }
            case "mutate-count", "restore-count" -> {
                String name=args[0].equals("mutate-count")?"same-count-tamper":"中文公告";
                MigrationTool.require(j.update("UPDATE sys_notice SET notice_title=? WHERE notice_id=11",name)==1,"COUNT_FAULT_PRECONDITION_FAILED");
            }
            case "seed-json" -> {
                j.update("INSERT INTO demo_compat_record(module_key,business_key,payload) VALUES ('migration','json-unicode',?)","{\"name\":\"中文🪖\",\"n\":9000000000001,\"decimal\":12.3400}");
            }
            case "seed-recovery" -> {
                MigrationTool.require(j.queryForObject("SELECT COUNT(*) FROM wearable_cluster_recovery",Integer.class)==0,"EMPTY_RECOVERY_FIXTURE_REQUIRED");
                j.update("INSERT INTO wearable_cluster_recovery(recovery_id,node_id,generation,actor_id,reason,summary_json,created_at) VALUES (?,?,?,?,?,?,?)",
                    "a9137259-e6b9-48b9-94dd-c6484bc352a2","retired-fixture-node","ed56cb17-63b4-4488-a63e-b5bf3a2efbaa","fixture-operator","迁移验收🪖",
                    "{\"message\":\"恢复审计🪖\",\"counts\":{\"UNKNOWN\":2},\"revision\":9000000000001}",1700000000123L);
            }
            case "assert-recovery" -> {
                String summary=j.queryForObject("SELECT summary_json FROM wearable_cluster_recovery WHERE recovery_id=?",(rs,n)->rs.getString(1),"a9137259-e6b9-48b9-94dd-c6484bc352a2");
                var value=MigrationTool.JSON.readTree(summary);
                MigrationTool.require(value.path("message").asText().equals("恢复审计🪖")&&value.path("counts").path("UNKNOWN").asInt()==2&&value.path("revision").asLong()==9000000000001L,"RECOVERY_AUDIT_CONTENT_CHANGED");
            }
            case "consume-target-identity" -> {
                MigrationTool.require(j.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Integer.class)==0,"EMPTY_TARGET_REQUIRED");
                j.execute("SET IDENTITY_INSERT wearable_device_report ON");
                try{j.update("INSERT INTO wearable_device_report(sequence,receipt_id,protocol,device_id,received_at,body) VALUES(9000000000000,'target-deleted','fixture','900000000000001',1,'{}')");}
                finally{j.execute("SET IDENTITY_INSERT wearable_device_report OFF");}
                j.update("DELETE FROM wearable_device_report WHERE receipt_id='target-deleted'");
            }
            case "assert-higher-target-identity" -> {
                j.update("INSERT INTO wearable_device_report(receipt_id,protocol,device_id,received_at,body) VALUES('after-recovery','fixture','900000000000001',1,'{}')");
                long key=j.queryForObject("SELECT sequence FROM wearable_device_report WHERE receipt_id='after-recovery'",Long.class);
                MigrationTool.require(key>9000000000000L,"TARGET_HIGHER_WATERMARK_LOWERED");
                j.update("DELETE FROM wearable_device_report WHERE receipt_id='after-recovery'");
            }
            default -> throw new IllegalArgumentException();
        }
        System.out.println("PASS: disposable readback/fault "+args[0]+".");
    }
}
