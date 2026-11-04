package com.ruoyi.guardian;
import com.alibaba.fastjson2.*;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.common.database.DatabaseDialect;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.file.*;
import java.util.*;
/** Explicit empty-database initialization. Never used by web startup; never merges or overwrites data. */
public final class WearableBusinessBootstrap {
    private WearableBusinessBootstrap(){}
    public static void main(String[] args)throws Exception {
        if(args.length!=1||!Paths.get(args[0]).isAbsolute())throw new IllegalArgumentException("Use one absolute private bootstrap directory");
        Path directory=Paths.get(args[0]);JSONObject ledger=JSON.parseObject(Files.readString(directory.resolve("admin-ledger.json"))),guardian=JSON.parseObject(Files.readString(directory.resolve("guardian-state.json"))),media=JSON.parseObject(Files.readString(directory.resolve("helmet-media-private.json"))),config=JSON.parseObject(Files.readString(directory.resolve("business-config.json")));
        JSONArray acceptance=JSON.parseArray(Files.readString(directory.resolve("feature-acceptance.json")));
        SingleConnectionDataSource source=new SingleConnectionDataSource(required("MELHAT_DB_URL"),required("MELHAT_DB_USERNAME"),required("MELHAT_DB_PASSWORD"),true);try{JdbcTemplate jdbc=new JdbcTemplate(source);
        SchemaLifecycle.configure(source,required("MELHAT_DB_PRODUCT"),"validate");
        initialize(jdbc,required("MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY"),ledger,guardian,media,config,acceptance);
        System.out.println("Empty-database business initialization committed; application startup remains validate-only.");
        }finally{source.destroy();}
    }
    static void initialize(JdbcTemplate jdbc,String mediaKey,JSONObject ledger,JSONObject guardian,JSONObject media,JSONObject config,JSONArray acceptance){
        if(mediaKey==null||mediaKey.isBlank()||Base64.getDecoder().decode(mediaKey.trim()).length!=32)throw new IllegalArgumentException("Explicit Base64 32-byte media key is required");
        // Bootstrap is account/organization setup, not an alternative to the device
        // writers that atomically register protocol ownership and related SQL rows.
        if(ledger==null||guardian==null||hasRows(ledger,"devices")||hasRows(ledger,"assignments")
                ||hasRows(guardian,"devices")||hasRows(guardian,"bindings")||media==null||!media.isEmpty()||acceptance==null||!acceptance.isEmpty())
            throw new IllegalArgumentException("初始化不导入设备、领用、媒体运行态或验收记录；请通过正式建档/领用接口或完整迁移导入");
        new SchemaLifecycle(jdbc).validate(SchemaLifecycle.all(DatabaseDialect.of(jdbc)));
        GuardianValidator.check(guardian,false);
        if(media==null||config==null||!(config.get("simulatedWatchVisible") instanceof Boolean)||acceptance==null)throw new IllegalArgumentException("Complete explicit business input is required");
        String owner=UUID.randomUUID().toString();
        if(jdbc.update("UPDATE wearable_schema_lock SET owner=? WHERE id=1 AND owner IS NULL",owner)!=1)throw new IllegalStateException("Another offline operation owns the schema");
        try {
            AdminLedgerStore master=new AdminLedgerStore(jdbc);WearableBusinessStore store=WearableBusinessStore.existing(jdbc,mediaKey);
            TransactionTemplate tx=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));tx.setTimeout(30);
            tx.execute(status->{
                jdbc.queryForObject("SELECT id FROM wearable_cluster_control WHERE id=1 FOR UPDATE",Integer.class);
                long now=DatabaseDialect.of(jdbc).dbTimeMillis(jdbc);
                if(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_node WHERE lease_until>?",Integer.class,now)>0)throw new IllegalStateException("Stop every application node before bootstrap");
                for(String table:Arrays.asList("wearable_business_meta","wearable_business_document","wearable_business_config","wearable_feature_acceptance","wearable_cluster_operation","wearable_media_effect","wearable_transport_command","wearable_device_owner","wearable_device_report","external_integration","external_data_record","safety_hat_info","fuda_push_outbox"))
                    if(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)>0)throw new IllegalStateException("Bootstrap requires empty business tables: "+table);
                for(String table:WearableBusinessStore.storageTables())if(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)>0)throw new IllegalStateException("Unmarked namespace data; bootstrap refused: "+table);
                master.initializeEmpty(ledger);
                for(String namespace:Arrays.asList("guardian","media")){
                    jdbc.update("INSERT INTO wearable_business_meta(namespace,revision,imported_at) VALUES(?,0,?)",namespace,now);
                    store.save(namespace,0,"guardian".equals(namespace)?guardian:media,null);
                }
                JSONObject settings=JSON.parseObject(config.toJSONString());settings.put("version",1);settings.put("dataVersion",WearableBusinessPolicy.DATA_VERSION);
                jdbc.update("INSERT INTO wearable_business_config(id,version,body) VALUES(1,1,?)",settings.toJSONString());
                for(Object raw:acceptance){JSONObject row=(JSONObject)raw;if(row.getString("evidence")==null||row.getString("evidence").isBlank())throw new IllegalArgumentException("Acceptance requires explicit evidence");jdbc.update("INSERT INTO wearable_feature_acceptance(device_id,feature_key,evidence) VALUES(?,?,?)",row.getString("deviceId"),row.getString("featureKey"),row.getString("evidence"));}
                DatabaseDialect.of(jdbc).insertIfAbsent(jdbc,"wearable_runtime_control",Arrays.asList("control_key","mode","updated_at"),Arrays.asList("control_key"),"global","ACTIVE",now);
                return null;
            });
        }finally{jdbc.update("UPDATE wearable_schema_lock SET owner=NULL WHERE id=1 AND owner=?",owner);}
    }
    private static boolean hasRows(JSONObject object,String key){Object value=object.get(key);return value!=null&&(!(value instanceof JSONArray)||!((JSONArray)value).isEmpty());}
    private static String required(String key){String value=System.getenv(key);if(value==null||value.isBlank())throw new IllegalArgumentException("Missing "+key);return value;}
}
