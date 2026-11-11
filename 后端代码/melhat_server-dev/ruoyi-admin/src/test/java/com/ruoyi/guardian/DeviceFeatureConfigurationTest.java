package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DeviceFeatureConfigurationTest {
    JSONObject state, actor, device;
    AdminLedgerStore ledger;
    AdminDeviceService service;
    WearableBusinessPolicy policy;
    @BeforeEach void setup() {
        actor=object("id","demo-system","name","配置管理员","enabled",true);
        device=object("id","belt-ledger","portalDeviceId","belt-test","deviceNumber","belt-test","siteId","site-1","type","BELT","source","DIRECT_BELT","lifecycle","IN_USE","version",4);
        state=object("devices",JSONArray.of(device),"accounts",JSONArray.of(actor,object("id","readonly","enabled",true,"roleIds",new JSONArray())),
                "sites",JSONArray.of(object("id","site-1","enabled",true)),"roles",new JSONArray(),"revision",1);
        ledger=mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i->copy(state));
        doAnswer(i->{JSONObject next=i.getArgument(0);state.clear();state.putAll(next);return null;}).when(ledger).write(any());
        AdminQueryService queries=new AdminQueryService(ledger,mock(GuardianStore.class),mock(ObjectProvider.class));
        service=new AdminDeviceService(ledger,mock(GuardianHatArchive.class));ReflectionTestUtils.setField(service,"queries",queries);
        policy=new WearableBusinessPolicy(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","")));
    }
    JSONObject config(String key) {return object("feature",key,"support","SUPPORTED","verification","VERIFIED","evidence","虚构设备隔离测试：实测状态与报文对应","alarmCodes",new JSONArray());}
    JSONObject input(JSONObject data) {return object("siteId","site-1","id","belt-ledger","expectedVersion",4,"operationId","feature-test-1","data",data);}
    JSONObject save(JSONObject data) {return service.execute("demo-system","devices.features",input(data)).getJSONObject("data");}
    JSONObject statusConfig(String key) {return object("feature",key,"support","SUPPORTED","connection","CONNECTED","availability","AVAILABLE");}

    @Test void savesThreeStatusesWithoutEvidenceOrCodesAndAuditsTheChange() {
        JSONObject data=statusConfig("temperature"), saved=save(data);
        JSONObject configured=saved.getJSONObject("featureConfiguration").getJSONObject("temperature");
        assertEquals("CONNECTED",configured.getJSONObject("status").getString("connection"));
        assertEquals("AVAILABLE",configured.getJSONObject("status").getString("availability"));
        assertEquals("demo-system",configured.getString("updatedBy"));assertNotNull(configured.getString("updatedAt"));
        assertFalse(configured.containsKey("evidence"));assertFalse(configured.containsKey("alarmCodes"));
        assertEquals(saved,service.execute("demo-system","devices.features",input(data)).getJSONObject("data"));
        assertEquals(1,rows(state,"audit").size());assertEquals(5,saved.getIntValue("version"));
        assertEquals(configured,rows(state,"audit").getJSONObject(0).getJSONObject("after").getJSONObject("temperature"));
    }
    @Test void maintainedStatusesDoNotChangeSensorInterpretationOrCommandReadiness() {
        JSONObject observed=copy(device);observed.put("online",true);observed.put("telemetryFreshness","CURRENT");
        JSONObject before=policy.features(copy(observed));
        for(String key:new String[]{"wear","hooks","height","temperature","rtk"})observed=DeviceFeatureConfiguration.update(observed,statusConfig(key),actor);
        assertEquals(before,policy.features(observed));
        assertNull(DeviceFeatureConfiguration.alarmFeature(observed,"3"));
        assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(find(state,"devices","belt-ledger"),"height",false,null));
    }
    @Test void statusEditsPreserveExistingMappingsAndCanReturnToAutomatic() {
        JSONObject data=config("temperature");data.put("alarmCodes",JSONArray.of("3"));
        JSONObject saved=save(data), before=copy(entry(saved,"temperature"));
        JSONObject updated=DeviceFeatureConfiguration.update(saved,statusConfig("temperature"),actor);
        assertEquals(before.get("alarmCodes"),entry(updated,"temperature").get("alarmCodes"));
        assertEquals(before.get("verification"),entry(updated,"temperature").get("verification"));
        assertEquals(before.get("evidence"),entry(updated,"temperature").get("evidence"));
        JSONObject reset=object("feature","temperature","support","DEFAULT","connection","DEFAULT","availability","DEFAULT");
        JSONObject automatic=DeviceFeatureConfiguration.update(updated,reset,actor);
        assertEquals("DEFAULT",entry(automatic,"temperature").getJSONObject("status").getString("availability"));
        assertEquals("temperature",DeviceFeatureConfiguration.alarmFeature(automatic,"3"));
    }
    @Test void rejectsMalformedOrContradictoryMaintainedStatusesWithoutWriting() {
        for(String field:new String[]{"support","connection","availability"}) {
            JSONObject missing=statusConfig("temperature");missing.remove(field);assertThrows(AdminQueryService.QueryFailed.class,()->save(missing));
            JSONObject wrong=statusConfig("temperature");wrong.put(field,true);assertThrows(AdminQueryService.QueryFailed.class,()->save(wrong));
        }
        JSONObject extra=statusConfig("temperature");extra.put("available",true);assertThrows(AdminQueryService.QueryFailed.class,()->save(extra));
        JSONObject offline=statusConfig("temperature");offline.put("connection","NOT_CONNECTED");assertThrows(AdminQueryService.QueryFailed.class,()->save(offline));
        JSONObject unsupported=statusConfig("temperature");unsupported.put("support","UNSUPPORTED");assertThrows(AdminQueryService.QueryFailed.class,()->save(unsupported));
        verify(ledger,never()).write(any());
    }
    @Test void maintainedStatusesSurviveDatabaseRestartAndProjection() {
        JdbcTemplate db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        AdminLedgerStore durable=new AdminLedgerStore(db);durable.write(copy(state));
        AdminDeviceService writer=new AdminDeviceService(durable,mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(writer,"queries",new AdminQueryService(durable,mock(GuardianStore.class),mock(ObjectProvider.class)));
        writer.execute("demo-system","devices.features",input(statusConfig("lowHook")));
        JSONObject restarted=new AdminLedgerStore(db).read();
        JSONObject stored=find(restarted,"devices","belt-ledger").getJSONObject("featureConfiguration");
        assertEquals("AVAILABLE",stored.getJSONObject("lowHook").getJSONObject("status").getString("availability"));
        rows(restarted,"sites").getJSONObject(0).put("portalStation","station-1");
        JSONObject snapshot=object("devices",new JSONArray());GuardianMasterProjection.apply(snapshot,restarted);
        assertEquals(stored,rows(snapshot,"devices").getJSONObject(0).getJSONObject("featureConfiguration"));
    }

    @Test void savesPerDeviceWithAuditAndIdempotencyWithoutChangingTelemetry() {
        JSONObject data=config("temperature");data.put("alarmCodes",JSONArray.of("3"));
        JSONObject saved=save(data);
        assertEquals(5,saved.getIntValue("version"));assertFalse(saved.containsKey("online"));
        assertEquals("3",entry(saved,"temperature").getJSONArray("alarmCodes").getString(0));
        assertEquals("demo-system",entry(saved,"temperature").getString("updatedBy"));
        assertEquals(saved,service.execute("demo-system","devices.features",input(data)).getJSONObject("data"));
        assertEquals(1,rows(state,"audit").size());assertEquals("devices.features",rows(state,"audit").getJSONObject(0).getString("action"));
        assertNotNull(rows(state,"audit").getJSONObject(0).getJSONObject("after"));
        assertNull(entry(object("source","DIRECT_BELT"),"temperature"));
    }
    @Test void rejectsForgedReadinessAndMissingEvidenceBeforeWriting() {
        JSONObject data=config("height");data.put("available",true);
        assertThrows(AdminQueryService.QueryFailed.class,()->save(data));data.remove("available");data.put("evidence","");
        assertThrows(AdminQueryService.QueryFailed.class,()->save(data));verify(ledger,never()).write(any());
    }
    @Test void enforcesScopeVersionAndLifecycle() {
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute("readonly","devices.features",input(config("height")))).code);
        JSONObject stale=input(config("height"));stale.put("expectedVersion",3);
        assertEquals("VERSION_CONFLICT",assertThrows(AdminQueryService.QueryFailed.class,()->service.execute("demo-system","devices.features",stale)).errorCode);
        JSONObject cross=input(config("height"));cross.put("siteId","site-2");assertThrows(AdminQueryService.QueryFailed.class,()->service.execute("demo-system","devices.features",cross));
        rows(state,"devices").getJSONObject(0).put("lifecycle","SCRAPPED");assertThrows(AdminQueryService.QueryFailed.class,()->save(config("height")));
        verify(ledger,never()).write(any());
    }
    @Test void wearMappingNeverTurnsAnUnknownOrStaleReadingIntoSafe() {
        JSONObject data=config("wear");data.put("positiveValue","1");data.put("negativeValue","0");JSONObject observed=save(data);
        observed.put("online",true);observed.put("telemetryFreshness","CURRENT");observed.put("isWeared","1");
        assertTrue(policy.features(observed).getJSONObject("wear").getBooleanValue("available"));assertEquals(true,observed.get("worn"));
        observed.put("isWeared","9");assertFalse(policy.features(observed).getJSONObject("wear").getBooleanValue("available"));assertNull(observed.get("worn"));
        observed.put("isWeared","1");observed.put("online",false);policy.features(observed);assertNull(observed.get("worn"));
        observed.put("online",true);observed.put("telemetryFreshness","STALE");assertFalse(policy.features(observed).getJSONObject("wear").getBooleanValue("available"));
    }
    @Test void supportDoesNotCreateIntegrationOrLiveMeasurements() {
        JSONObject observed=save(config("height"));observed.put("online",true);observed.put("telemetryFreshness","CURRENT");
        assertFalse(policy.features(observed).getJSONObject("height").getBooleanValue("available"));
        observed.put("relativeAltitude",0);assertTrue(policy.features(observed).getJSONObject("height").getBooleanValue("available"));
        JSONObject rtk=DeviceFeatureConfiguration.update(device,config("rtk"),actor);rtk.put("online",true);
        JSONObject state=policy.features(rtk).getJSONObject("rtk");assertTrue(state.getBooleanValue("supported"));assertEquals("NOT_CONNECTED",state.getString("integrationStatus"));assertFalse(state.getBooleanValue("available"));
    }
    @Test void alarmMappingsAreExplicitUniqueAndUnknownCodesStayUnknown() {
        JSONObject data=config("proximity");assertThrows(AdminQueryService.QueryFailed.class,()->save(data));data.put("alarmCodes",JSONArray.of("11"));
        JSONObject saved=save(data);saved.put("online",true);
        assertEquals("proximity",DeviceFeatureConfiguration.alarmFeature(saved,"11"));assertNull(DeviceFeatureConfiguration.alarmFeature(saved,"6"));
        assertTrue(policy.features(saved).getJSONObject("proximity").getBooleanValue("available"));
        saved.put("online",false);assertFalse(policy.features(saved).getJSONObject("proximity").getBooleanValue("available"));
        assertEquals("NOT_CONNECTED",policy.features(saved).getJSONObject("proximity").getString("integrationStatus"));
        JSONObject duplicate=config("temperature");duplicate.put("alarmCodes",JSONArray.of("11"));assertThrows(AdminQueryService.QueryFailed.class,()->DeviceFeatureConfiguration.update(saved,duplicate,actor));
        entry(saved,"proximity").put("verification","PENDING");assertNull(DeviceFeatureConfiguration.alarmFeature(saved,"11"));
    }
    @Test void projectionCarriesConfigurationAndRevocationIntoOtherClients() {
        JSONObject configured=save(config("height"));rows(state,"sites").getJSONObject(0).put("portalStation","station-1");
        JSONObject snapshot=object("devices",new JSONArray());GuardianMasterProjection.apply(snapshot,copy(state));
        JSONObject projected=rows(snapshot,"devices").getJSONObject(0);assertEquals(configured.getJSONObject("featureConfiguration"),projected.getJSONObject("featureConfiguration"));
        JSONObject noSupport=config("height");noSupport.put("support","UNSUPPORTED");noSupport.put("verification","PENDING");
        projected=DeviceFeatureConfiguration.update(projected,noSupport,actor);projected.put("online",true);projected.put("telemetryFreshness","CURRENT");projected.put("relativeAltitude",3);
        assertFalse(policy.features(projected).getJSONObject("height").getBooleanValue("available"));
        assertEquals("UNSUPPORTED",policy.features(projected).getJSONObject("height").getString("supportStatus"));
    }
    @Test void configurationAndAuditSurviveDatabaseStoreRestart() {
        JdbcTemplate db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        AdminLedgerStore durable=new AdminLedgerStore(db);durable.write(copy(state));
        AdminDeviceService writer=new AdminDeviceService(durable,mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(writer,"queries",new AdminQueryService(durable,mock(GuardianStore.class),mock(ObjectProvider.class)));
        JSONObject data=config("temperature");data.put("alarmCodes",JSONArray.of("3"));
        writer.execute("demo-system","devices.features",input(data));
        JSONObject restarted=new AdminLedgerStore(db).read();
        assertEquals("3",entry(find(restarted,"devices","belt-ledger"),"temperature").getJSONArray("alarmCodes").getString(0));
        assertEquals(1,rows(restarted,"audit").size());assertEquals(5,find(restarted,"devices","belt-ledger").getIntValue("version"));
    }
    private JSONObject entry(JSONObject value,String key){return DeviceFeatureConfiguration.entry(value,key);}
}
