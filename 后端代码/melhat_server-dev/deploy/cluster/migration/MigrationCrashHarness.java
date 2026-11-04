import java.nio.file.*;

/** A real test process is killed after DM has committed DROP IDENTITY and its progress record. */
public class MigrationCrashHarness {
    public static void main(String[] args)throws Exception{
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        Path marker=Path.of(args[1]);
        MigrationTool.checkpoint=(stage,table)->{
            if(stage.equals("identity-removed")&&table.equals("wearable_device_report")){
                Files.writeString(marker,"DROP_IDENTITY_COMMITTED\n",StandardOpenOption.CREATE_NEW);
                Thread.sleep(Long.MAX_VALUE);
            }
        };
        try(MigrationTool tool=new MigrationTool()){tool.importBundle(Path.of(args[0]),false);}
        throw new AssertionError("Expected the parent test to kill this process at the durable DDL barrier");
    }
}
