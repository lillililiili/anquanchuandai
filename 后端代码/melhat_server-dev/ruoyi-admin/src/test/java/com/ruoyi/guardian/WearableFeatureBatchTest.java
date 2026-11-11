package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WearableFeatureBatchTest {
    JdbcTemplate jdbc;
    WearableBusinessPolicy policy;
    @BeforeEach void setup(){
        jdbc=spy(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","")));
        policy=new WearableBusinessPolicy(jdbc);clearInvocations(jdbc);
    }
    private long queries(){return mockingDetails(jdbc).getInvocations().stream().filter(call->call.getMethod().getName().equals("query")&&call.getArguments().length>1&&call.getArgument(0) instanceof String&&call.getArgument(1) instanceof org.springframework.jdbc.core.RowMapper&&((String)call.getArgument(0)).contains("FROM wearable_feature_acceptance")).count();}

    @Test void batchPreservesIdPrecedenceDuplicatesEmptyIdsAndMissingEvidence(){
        jdbc.update("INSERT INTO wearable_feature_acceptance(device_id,feature_key,evidence) VALUES('','battery','test')");
        JSONArray devices=JSONArray.of(
                object("id","ledger-a","portalDeviceId","866652021714127","deviceNumber","ignored","source","DIRECT_HELMET","online",true,"mediaAvailable",true),
                object("id","ledger-b","deviceNumber","866652023095053","source","DIRECT_BELT","online",true,"hookMappingConfirmed",true,"telemetryFreshness","CURRENT"),
                object("id","ledger-c","portalDeviceId","866652021714127","source","DIRECT_HELMET","online",false),
                object("id","no-evidence","source","DIRECT_HELMET","online",true,"voiceAvailable",true),
                object("source","DIRECT_BELT","online",true));
        clearInvocations(jdbc);Map<String,Set<String>> batch=policy.featureAcceptance(devices);
        assertEquals(1,queries());assertEquals(new HashSet<>(Arrays.asList("866652021714127","866652023095053","no-evidence","")),batch.keySet());
        assertTrue(batch.get("no-evidence").isEmpty());assertTrue(batch.get("").contains("battery"));
        List<JSONObject> actual=new ArrayList<>();for(Object raw:devices)actual.add(policy.features((JSONObject)raw,batch));
        assertEquals(1,queries(),"Every requested ID, including an empty or unaccepted ID, is represented in the batch");
        for(int n=0;n<devices.size();n++)assertEquals(policy.features(devices.getJSONObject(n)),actual.get(n));
        assertFalse(actual.get(2).getJSONObject("video").getBooleanValue("available"));
    }

    @Test void batchesOnlyRequestedDevicesAndBoundsSqlParameters(){
        JSONArray devices=new JSONArray();for(int n=0;n<501;n++)devices.add(object("id","requested-"+n));
        Map<String,Set<String>> batch=policy.featureAcceptance(devices);
        assertEquals(501,batch.size());assertEquals(2,queries());assertFalse(batch.containsKey("866652021714127"));
        clearInvocations(jdbc);assertTrue(policy.featureAcceptance(new JSONArray()).isEmpty());assertEquals(0,queries());
    }

    @Test void evidenceIsRequestLocalAndReadinessIsNeverCached(){
        JSONObject device=object("id","new-helmet","source","DIRECT_HELMET","online",true,"mediaAvailable",true);
        Map<String,Set<String>> first=policy.featureAcceptance(JSONArray.of(device));
        assertFalse(policy.features(device,first).getJSONObject("wear").getBooleanValue("verified"));
        jdbc.update("INSERT INTO wearable_feature_acceptance(device_id,feature_key,evidence) VALUES('new-helmet','wear','confirmed')");
        assertFalse(policy.features(device,first).getJSONObject("wear").getBooleanValue("verified"));
        Map<String,Set<String>> next=policy.featureAcceptance(JSONArray.of(device));
        assertTrue(policy.features(device,next).getJSONObject("wear").getBooleanValue("verified"));
        device.put("online",false);assertFalse(policy.features(device,next).getJSONObject("wear").getBooleanValue("available"));
        clearInvocations(jdbc);
        JSONObject unlisted=object("id","866652021714127","source","DIRECT_HELMET");
        JSONObject fallback=policy.features(unlisted,next);assertEquals(1,queries());assertEquals(policy.features(unlisted),fallback);
    }

    @Test void databaseCaseInsensitiveMatchesMapBackToEveryOriginalRequestedId(){
        jdbc.execute("ALTER TABLE wearable_feature_acceptance ALTER COLUMN device_id VARCHAR_IGNORECASE(100)");
        jdbc.update("INSERT INTO wearable_feature_acceptance(device_id,feature_key,evidence) VALUES('Case-Helmet','wear','confirmed')");
        JSONObject lower=object("id","case-helmet","source","DIRECT_HELMET","online",true);
        JSONObject upper=object("id","CASE-HELMET","source","DIRECT_HELMET","online",true);
        clearInvocations(jdbc);Map<String,Set<String>> batch=policy.featureAcceptance(JSONArray.of(lower,upper));
        assertEquals(1,queries());assertEquals(new HashSet<>(Arrays.asList("case-helmet","CASE-HELMET")),batch.keySet());
        for(JSONObject device:Arrays.asList(lower,upper)){
            assertTrue(batch.get(device.getString("id")).contains("wear"));
            assertEquals(policy.features(device),policy.features(device,batch));
        }
    }
}
