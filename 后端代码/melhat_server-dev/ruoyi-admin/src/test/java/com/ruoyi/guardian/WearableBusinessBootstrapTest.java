package com.ruoyi.guardian;
import com.alibaba.fastjson2.*;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.common.database.DatabaseDialect;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
class WearableBusinessBootstrapTest {
    static final String KEY=Base64.getEncoder().encodeToString(new byte[32]);
    JdbcTemplate database(){JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));new SchemaLifecycle(jdbc).migrate(SchemaLifecycle.all(DatabaseDialect.H2));SchemaLifecycle.configure(jdbc.getDataSource(),"H2","validate");return jdbc;}
    JSONObject ledger(){return object("sites",new JSONArray(),"accounts",new JSONArray(),"revision",1,"nextId",1);}
    JSONObject guardian(){JSONObject state=object("version",1,"seq",0,"clock",0);for(String key:Arrays.asList("stations","people","devices","bindings","locations","vitals","works","events","media","groups","fences","fenceRecords","calls","broadcasts","audit"))state.put(key,new JSONArray());return state;}
    void initialize(JdbcTemplate jdbc,JSONObject ledger,JSONArray acceptance){WearableBusinessBootstrap.initialize(jdbc,KEY,ledger,guardian(),new JSONObject(),WearableBusinessPolicy.defaults(),acceptance);}
    @Test void initializesBothNamespacesAndMetadataExactlyOnce(){JdbcTemplate jdbc=database();initialize(jdbc,ledger(),new JSONArray());assertEquals(1,jdbc.queryForObject("SELECT revision FROM wearable_meta WHERE id=1",Integer.class));assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_meta WHERE revision=1",Integer.class));assertEquals("ACTIVE",jdbc.queryForObject("SELECT mode FROM wearable_runtime_control WHERE control_key='global'",String.class));assertThrows(IllegalStateException.class,()->initialize(jdbc,ledger(),new JSONArray()));}
    @Test void noCredentialDefaultsAndAnyLateFailureRollsBackAllInputs(){JdbcTemplate jdbc=database();JSONObject seed=ledger();seed.put("accounts",JSONArray.of(object("id","operator","enabled",true)));assertThrows(IllegalArgumentException.class,()->initialize(jdbc,seed,new JSONArray()));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_meta",Integer.class));JSONArray bad=JSONArray.of(object("deviceId","h","featureKey","video"));assertThrows(IllegalArgumentException.class,()->initialize(jdbc,ledger(),bad));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_meta",Integer.class));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_meta",Integer.class));assertNull(jdbc.queryForObject("SELECT owner FROM wearable_schema_lock WHERE id=1",String.class));}
    @Test void refusesUnknownOperationAndUnmarkedRows(){JdbcTemplate jdbc=database();jdbc.update("INSERT INTO wearable_cluster_operation(operation_id,node_id,generation,operation_kind,state,lease_until,created_at) VALUES('unknown','old','old','BUSINESS','ACTIVE',0,0)");assertThrows(IllegalStateException.class,()->initialize(jdbc,ledger(),new JSONArray()));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_meta",Integer.class));}
    @Test void rejectsBlankAndMalformedKeysEvenForEmptyMedia(){JdbcTemplate jdbc=database();for(String key:Arrays.asList(" ","",Base64.getEncoder().encodeToString(new byte[16]),"bad@"))assertThrows(IllegalArgumentException.class,()->WearableBusinessBootstrap.initialize(jdbc,key,ledger(),guardian(),new JSONObject(),WearableBusinessPolicy.defaults(),new JSONArray()));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_meta",Integer.class));}
    @Test void rejectsUnmarkedExternalAndHatRows(){
        for(String insert:Arrays.asList("INSERT INTO external_integration VALUES('old','s','DEVICE',1,'{}')","INSERT INTO external_data_record VALUES('old','integration','s','DEVICE','IN','x','now','OK','{}')","INSERT INTO safety_hat_info(hat_number) VALUES('old')")){
            JdbcTemplate jdbc=database();jdbc.update(insert);assertThrows(IllegalStateException.class,()->initialize(jdbc,ledger(),new JSONArray()));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_meta",Integer.class));
        }
    }
    @Test void mediaImportHasStrongerPendingCommandGateThanNodeDrain(){JdbcTemplate jdbc=database();initialize(jdbc,ledger(),new JSONArray());jdbc.update("UPDATE wearable_runtime_control SET mode='PAUSED' WHERE control_key='global'");
        for(String pending:Arrays.asList("QUEUED","PREPARING","SENT")) {
            jdbc.update("INSERT INTO wearable_transport_command(command_id,scope_key,fingerprint,device_type,device_id,node_id,generation,connection_token,wire_json,context_json,created_at,updated_at,deadline,delivery_status) VALUES('pending','scope','fp','helmet','h','node','gen','connection','{}','{}',0,0,9999999999999,?)",pending);
            assertThrows(IllegalStateException.class,()->org.springframework.test.util.ReflectionTestUtils.invokeMethod(WearableBusinessImport.class,"lockMaintenance",jdbc,true));
            assertEquals(Boolean.TRUE,org.springframework.test.util.ReflectionTestUtils.invokeMethod(WearableBusinessImport.class,"lockMaintenance",jdbc,false));jdbc.update("DELETE FROM wearable_transport_command");
        }
    }
}
