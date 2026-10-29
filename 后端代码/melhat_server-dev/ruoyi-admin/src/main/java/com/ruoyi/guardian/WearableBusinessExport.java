package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.io.BufferedWriter;
import java.util.*;

/** Offline, read-only export of current SQL state for a controlled rollback. Never starts the application. */
public final class WearableBusinessExport {
    private WearableBusinessExport() { }
    public static void main(String[] args) throws Exception {
        if(args.length!=1)throw new IllegalArgumentException("用法: WearableBusinessExport <新的私有导出目录绝对路径>");
        Path directory=Paths.get(args[0]);
        if(!directory.isAbsolute() || Files.exists(directory))throw new IllegalArgumentException("导出目录必须是不存在的绝对路径");
        DriverManagerDataSource source=new DriverManagerDataSource();source.setDriverClassName("com.mysql.cj.jdbc.Driver");
        source.setUrl(required("WEARABLE_EXPORT_JDBC_URL"));source.setUsername(required("WEARABLE_EXPORT_USERNAME"));source.setPassword(required("WEARABLE_EXPORT_PASSWORD"));
        export(new JdbcTemplate(source),System.getenv("MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY"),directory);
        System.out.println("SQL business export completed. Private media credentials are present in the protected export directory.");
    }

    static void export(JdbcTemplate jdbc,String mediaKey,Path directory) throws Exception {
        if(Files.exists(directory))throw new IllegalArgumentException("导出目录已存在，禁止覆盖");
        Files.createDirectory(directory);
        try { Files.setPosixFilePermissions(directory,java.nio.file.attribute.PosixFilePermissions.fromString("rwx------")); }
        catch(UnsupportedOperationException ignored) { }
        WearableBusinessStore store=WearableBusinessStore.readOnly(jdbc,mediaKey);
        TransactionTemplate transaction=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        transaction.setIsolationLevel(org.springframework.transaction.TransactionDefinition.ISOLATION_REPEATABLE_READ);
        JSONObject manifest=transaction.execute(status->{
            JSONObject result=new JSONObject();result.put("formatVersion",1);result.put("exportedAt",java.time.Instant.now().toString());
            for(String namespace:Arrays.asList("guardian","media")) {
                Integer exists=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_meta WHERE namespace=?",Integer.class,namespace);
                if(exists==null || exists==0) { result.put(namespace+"Initialized",false);continue; }
                WearableBusinessStore.Snapshot snapshot=store.read(namespace);
                try{write(directory.resolve("guardian".equals(namespace)?"guardian-state.json":"helmet-media-private.json"),snapshot.state.toJSONString());}
                catch(Exception error){throw new IllegalStateException("业务导出文件保存失败",error);}
                result.put(namespace+"Initialized",true);result.put(namespace+"Revision",snapshot.revision);
            }
            Long watermark=jdbc.queryForObject("SELECT COALESCE(MAX(sequence),0) FROM wearable_device_report",Long.class);
            result.put("reportWatermark",watermark);
            result.put("pendingReports",jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE sequence<=? AND processed_at IS NULL",Long.class,watermark));
            try(BufferedWriter writer=Files.newBufferedWriter(directory.resolve("device-reports.jsonl"),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW)) {
                long cursor=0;
                while(true) {
                    List<JSONObject> batch=jdbc.query("SELECT sequence,receipt_id,protocol,device_id,received_at,processed_at,body FROM wearable_device_report WHERE sequence>? AND sequence<=? ORDER BY sequence LIMIT 1000",(rs,n)->{
                        JSONObject row=new JSONObject();row.put("sequence",rs.getLong(1));row.put("receiptId",rs.getString(2));row.put("protocol",rs.getString(3));row.put("deviceId",rs.getString(4));row.put("receivedMillis",rs.getLong(5));row.put("processedMillis",rs.getObject(6));row.put("payload",JSONObject.parseObject(rs.getString(7)));return row;
                    },cursor,watermark);
                    if(batch.isEmpty())break;
                    for(JSONObject row:batch){writer.write(row.toJSONString());writer.newLine();cursor=row.getLongValue("sequence");}
                }
            }catch(Exception error){throw new IllegalStateException("设备报文导出失败",error);}
            return result;
        });
        // Manifest is the completion marker; an interrupted directory without it is not a valid rollback image.
        write(directory.resolve("manifest.json"),manifest.toJSONString());
    }
    private static void write(Path path,String value) throws Exception {
        Files.write(path,value.getBytes(StandardCharsets.UTF_8),StandardOpenOption.CREATE_NEW);
        try{Files.setPosixFilePermissions(path,java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"));}catch(UnsupportedOperationException ignored){}
    }
    private static String required(String name){String value=System.getenv(name);if(value==null||value.isEmpty())throw new IllegalArgumentException("缺少环境变量 "+name);return value;}
}
