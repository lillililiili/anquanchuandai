package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Controlled cleanup/re-upgrade import. Run only after stopping business writers and draining the report journal. */
public final class WearableBusinessImport {
    private WearableBusinessImport() { }
    public static void main(String[] args) throws Exception {
        if(args.length!=1)throw new IllegalArgumentException("用法: WearableBusinessImport <包含manifest和清理数据的私有目录绝对路径>");
        Path directory=Paths.get(args[0]);if(!directory.isAbsolute())throw new IllegalArgumentException("导入目录必须为绝对路径");
        DriverManagerDataSource source=new DriverManagerDataSource();source.setDriverClassName("com.mysql.cj.jdbc.Driver");
        source.setUrl(required("WEARABLE_EXPORT_JDBC_URL"));source.setUsername(required("WEARABLE_EXPORT_USERNAME"));source.setPassword(required("WEARABLE_EXPORT_PASSWORD"));
        importCurrent(new JdbcTemplate(source),System.getenv("MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY"),directory);
        System.out.println("SQL business import completed with revision and report-watermark checks.");
    }

    static JSONObject importCurrent(JdbcTemplate jdbc,String mediaKey,Path directory) throws Exception {
        JSONObject manifest=read(directory.resolve("manifest.json")),guardian=read(directory.resolve("guardian-state.json"));
        if(!manifest.containsKey("guardianRevision")||!manifest.containsKey("reportWatermark"))throw new IllegalArgumentException("导入清单缺少预期版本或报文水位");
        long revision=manifest.getLongValue("guardianRevision"),watermark=manifest.getLongValue("reportWatermark");
        if(revision<1 || watermark<0)throw new IllegalArgumentException("导入版本或报文水位无效");
        GuardianValidator.check(guardian,false);
        boolean importMedia=manifest.getBooleanValue("importMedia");
        final JSONObject media=importMedia?read(directory.resolve("helmet-media-private.json")):null;
        if(importMedia && (!manifest.containsKey("mediaRevision")||manifest.getLongValue("mediaRevision")<1))throw new IllegalArgumentException("媒体导入缺少预期版本");
        if(Files.exists(directory.resolve("import-result.json")))throw new IllegalStateException("该目录已有导入结果，禁止重复导入");
        WearableBusinessStore store=WearableBusinessStore.existing(jdbc,mediaKey);
        TransactionTemplate transaction=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        transaction.setIsolationLevel(org.springframework.transaction.TransactionDefinition.ISOLATION_SERIALIZABLE);
        JSONObject result=transaction.execute(status->{
            boolean paused=lockMaintenance(jdbc);
            Long current=jdbc.queryForObject("SELECT COALESCE(MAX(sequence),0) FROM wearable_device_report",Long.class);
            Long pending=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NULL",Long.class);
            if(current==null||pending==null || (paused?current<watermark:current!=watermark||pending!=0))throw new IllegalStateException("设备报文水位不符合维护条件，禁止覆盖业务数据");
            long next=store.save("guardian",revision,guardian,null);
            JSONObject saved=new JSONObject();saved.put("guardianRevision",next);saved.put("reportWatermark",current);saved.put("exportReportWatermark",watermark);saved.put("pendingReports",pending);saved.put("maintenancePaused",paused);saved.put("importedAt",java.time.Instant.now().toString());
            if(importMedia)saved.put("mediaRevision",store.save("media",manifest.getLongValue("mediaRevision"),media,null));
            return saved;
        });
        Files.write(directory.resolve("import-result.json"),result.toJSONString().getBytes(StandardCharsets.UTF_8),StandardOpenOption.CREATE_NEW);
        return result;
    }
    private static boolean lockMaintenance(JdbcTemplate jdbc) {
        Boolean exists=jdbc.execute((org.springframework.jdbc.core.ConnectionCallback<Boolean>)connection->{
            try(java.sql.ResultSet tables=connection.getMetaData().getTables(connection.getCatalog(),null,"%",new String[]{"TABLE","BASE TABLE"})) {
                while(tables.next())if("wearable_runtime_control".equalsIgnoreCase(tables.getString("TABLE_NAME")))return true;
                return false;
            }
        });
        if(!Boolean.TRUE.equals(exists))return false; // Older/offline databases retain the strict drained-journal path.
        java.util.List<String> modes=jdbc.query("SELECT mode FROM wearable_runtime_control WHERE control_key='global' FOR UPDATE",(rs,n)->rs.getString(1));
        if(modes.size()!=1)throw new IllegalStateException("维护状态缺失，禁止导入");
        return "PAUSED".equals(modes.get(0));
    }
    private static JSONObject read(Path path) throws Exception { JSONObject value=JSONObject.parseObject(new String(Files.readAllBytes(path),StandardCharsets.UTF_8));if(value==null)throw new IllegalArgumentException("导入文件为空");return value; }
    private static String required(String name){String value=System.getenv(name);if(value==null||value.isEmpty())throw new IllegalArgumentException("缺少环境变量 "+name);return value;}
}
