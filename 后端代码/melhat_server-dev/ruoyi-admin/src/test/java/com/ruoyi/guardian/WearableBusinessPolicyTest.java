package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.guardian.WearableModel.*;

class WearableBusinessPolicyTest {
    @Test void hiddenWatchIsRemovedFromMobileContextAndAssignmentHistoryWithoutMutatingLedger(){
        WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());policy.configure(object("simulatedWatchVisible",false,"expectedVersion",1),admin());
        JSONObject source=object("accounts",JSONArray.of(object("id","demo-system","enabled",true)),"devices",JSONArray.of(object("id","watch-ledger","portalDeviceId","RL-W001","source","DEMO_WATCH")),"people",JSONArray.of(object("id","demo-person","source","DEMO_WATCH")),"assignments",JSONArray.of(object("deviceId","watch-ledger")),"history",JSONArray.of(object("deviceId","watch-ledger")));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(source));
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));org.springframework.test.util.ReflectionTestUtils.setField(access,"businessPolicy",policy);
        JSONObject view=access.context(object("id","demo-system")).data;
        assertTrue(rows(view,"devices").isEmpty());assertTrue(rows(view,"people").isEmpty());assertTrue(rows(view,"assignments").isEmpty());assertTrue(rows(view,"history").isEmpty());assertEquals(1,rows(source,"devices").size());
        assertFalse(safe(object("businessOperations",object("private",true))).containsKey("businessOperations"));
    }
    JdbcTemplate jdbc(){return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));}
    GuardianAccess.Context admin(){JSONObject data=object("sites",JSONArray.of(object("id","site-1","enabled",true)),"accounts",JSONArray.of(object("id","demo-system","enabled",true)),"roles",new JSONArray());AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(data);return new GuardianAccess(ledger,mock(AdminQueryService.class)).context(object("id","demo-system"));}
    @Test void supportedMediaUsesRuntimeReadinessWhilePhysicalEvidenceSurvivesOffline(){WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());JSONObject hat=object("id","866652021714127","source","DIRECT_HELMET","online",true,"mediaAvailable",true);JSONObject features=policy.features(hat);
        assertTrue(features.getJSONObject("video").getBooleanValue("available"));assertTrue(features.getJSONObject("photo").getBooleanValue("available"));assertFalse(features.getJSONObject("photo").getBooleanValue("verified"));assertFalse(features.getJSONObject("vitals").getBooleanValue("supported"));
        hat.put("online",false);features=policy.features(hat);assertTrue(features.getJSONObject("video").getBooleanValue("supported"));assertTrue(features.getJSONObject("video").getBooleanValue("verified"));assertFalse(features.getJSONObject("video").getBooleanValue("available"));}
    @Test void beltOnlyUsesConfirmedHookMappingAndNeverOffersVideo(){WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());JSONObject belt=object("id","866652023095053","source","DIRECT_BELT","online",true,"telemetryFreshness","CURRENT","hookMappingConfirmed",true);
        JSONObject states=policy.features(belt);assertTrue(states.getJSONObject("hooks").getBooleanValue("available"));assertFalse(states.getJSONObject("wear").getBooleanValue("verified"));assertFalse(states.getJSONObject("video").getBooleanValue("supported"));assertFalse(states.getJSONObject("proximity").getBooleanValue("supported"));
        belt.put("telemetryFreshness","STALE");assertFalse(policy.features(belt).getJSONObject("hooks").getBooleanValue("available"));}
    @Test void visibilityIsPersistedAndNeverDeletesUnderlyingDataOrUnassignedEvents(){JdbcTemplate db=jdbc();WearableBusinessPolicy policy=new WearableBusinessPolicy(db);JSONObject source=object("devices",JSONArray.of(object("id","RL-W001","source","DEMO_WATCH"),object("id","hat","source","DIRECT_HELMET")),"events",JSONArray.of(object("id","real","source","device")),"vitals",JSONArray.of(object("deviceId","RL-W001")));
        policy.configure(object("simulatedWatchVisible",false,"expectedVersion",1),admin());JSONObject view=policy.decorate(copy(source),false);assertEquals(1,rows(view,"devices").size());assertEquals(1,rows(view,"events").size());assertTrue(rows(view,"vitals").isEmpty());assertEquals(2,rows(source,"devices").size());assertFalse(new WearableBusinessPolicy(db).config().getBooleanValue("simulatedWatchVisible"));}
    @Test void operationalMediaDoesNotWaiveSensorVerificationOrUnsupportedFeatures(){WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());JSONObject hat=object("id","unverified-helmet","source","DIRECT_HELMET","online",true,"mediaAvailable",true);assertDoesNotThrow(()->policy.require(hat,"photo",false,admin()));assertEquals("FEATURE_PENDING_ACCEPTANCE",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"wear",false,admin())).errorCode);assertDoesNotThrow(()->policy.require(hat,"wear",true,admin()));assertEquals("FEATURE_UNSUPPORTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"vitals",true,admin())).errorCode);}
    @Test void allImplementedHelmetMediaOperationsUseTheirActualServiceAndDeviceReadiness(){
        JdbcTemplate db=jdbc();WearableBusinessPolicy policy=new WearableBusinessPolicy(db);
        JSONObject hat=object("id","new-helmet","source","DIRECT_HELMET","online",true,"mediaAvailable",true,"voiceAvailable",true,"broadcastAvailable",true);
        for(String feature:new String[]{"video","photo","recording","voice","videoCall","broadcast"}){
            JSONObject state=policy.features(hat).getJSONObject(feature);
            assertTrue(state.getBooleanValue("available"),feature);assertFalse(state.getBooleanValue("verified"),feature);assertEquals("",state.getString("reason"),feature);
            assertDoesNotThrow(()->policy.require(hat,feature,false,admin()));
        }
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM wearable_feature_acceptance WHERE device_id='new-helmet'",Integer.class));
        hat.put("voiceAvailable",false);
        for(String feature:new String[]{"voice","videoCall"})assertEquals("FEATURE_NOT_CONNECTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,feature,false,admin())).errorCode);
        assertTrue(policy.features(hat).getJSONObject("photo").getBooleanValue("available"));
        hat.put("broadcastAvailable",false);assertEquals("文字转语音服务暂不可用",policy.features(hat).getJSONObject("broadcast").getString("reason"));
        assertEquals("FEATURE_NOT_CONNECTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"broadcast",false,admin())).errorCode);
        hat.put("mediaAvailable",false);
        for(String feature:new String[]{"video","photo","recording"})assertEquals("FEATURE_NOT_CONNECTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,feature,false,admin())).errorCode);
        hat.put("online",false);
        for(String feature:new String[]{"video","photo","recording","voice","videoCall","broadcast"})assertEquals("DEVICE_OFFLINE",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,feature,false,admin())).errorCode);
    }
    @Test void voiceUsesLiveServiceReadinessWithoutManufacturingAcceptanceEvidence(){
        JdbcTemplate db=jdbc();WearableBusinessPolicy policy=new WearableBusinessPolicy(db);
        JSONObject hat=object("id","866652021714127","source","DIRECT_HELMET","online",true,"mediaAvailable",true,"voiceAvailable",true);
        JSONObject voice=policy.features(hat).getJSONObject("voice");
        assertTrue(voice.getBooleanValue("supported"));assertTrue(voice.getBooleanValue("available"));assertEquals("",voice.getString("reason"));
        assertFalse(voice.getBooleanValue("verified"));assertEquals("PENDING",voice.getString("verificationStatus"));
        assertDoesNotThrow(()->policy.require(hat,"voice",false,admin()));
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM wearable_feature_acceptance WHERE device_id=? AND feature_key='voice'",Integer.class,"866652021714127"));
        hat.put("online",false);voice=policy.features(hat).getJSONObject("voice");assertFalse(voice.getBooleanValue("available"));assertEquals("设备离线",voice.getString("reason"));
        assertEquals("DEVICE_OFFLINE",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"voice",false,admin())).errorCode);
        hat.put("online",true);hat.put("voiceAvailable",false);voice=policy.features(hat).getJSONObject("voice");assertFalse(voice.getBooleanValue("available"));assertEquals("安全帽语音未连接",voice.getString("reason"));
        assertEquals("FEATURE_NOT_CONNECTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"voice",false,admin())).errorCode);
        hat.put("mediaAvailable",false);hat.put("mediaStatus","unconfigured");assertEquals("语音服务未配置",policy.features(hat).getJSONObject("voice").getString("reason"));
        hat.put("mediaStatus","unavailable");assertEquals("语音服务暂不可用",policy.features(hat).getJSONObject("voice").getString("reason"));
    }
    @Test void onlineBeltAndWatchNeverBecomeVoiceTargets(){
        WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());
        for(String source:new String[]{"DIRECT_BELT","DEMO_WATCH","PLATFORM"}){
            JSONObject device=object("id","other-device","source",source,"online",true,"voiceAvailable",true,"mediaAvailable",true);
            JSONObject voice=policy.features(device).getJSONObject("voice");assertFalse(voice.getBooleanValue("supported"));assertFalse(voice.getBooleanValue("available"));
            assertEquals("FEATURE_UNSUPPORTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(device,"voice",true,admin())).errorCode);
        }
    }
}
