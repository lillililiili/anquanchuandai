package com.ruoyi.guardian;

import com.alibaba.fastjson2.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class SplitHelmetRegistrationTest {
    JSONObject state,snapshot;AdminLedgerStore ledger;GuardianStore guardian;GuardianHatArchive archive;
    AdminDeviceService devices;AdminQueryService queries;
    @BeforeEach void setup()throws Exception {
        state=seed("admin-seed.json");snapshot=seed("guardian-seed.json");ledger=mock(AdminLedgerStore.class);archive=mock(GuardianHatArchive.class);guardian=mock(GuardianStore.class);
        when(ledger.read()).thenAnswer(i->copy(state));doAnswer(i->{JSONObject next=i.getArgument(0);state.clear();state.putAll(next);return null;}).when(ledger).write(any());
        when(guardian.snapshot()).thenAnswer(i->copy(snapshot));queries=new AdminQueryService(ledger,guardian,mock(ObjectProvider.class));
        devices=new AdminDeviceService(ledger,archive);ReflectionTestUtils.setField(devices,"queries",queries);
    }
    JSONObject seed(String name)throws Exception{return JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource(name).getInputStream(),StandardCharsets.UTF_8));}
    JSONObject request(){return object("siteId","site-1","operationId","split-register","data",object("type","HELMET","source","SPLIT_HELMET","deviceNumber","SPLIT.001","code","ASSET-001","sn","SERIAL-001","name","分体帽","manufacturer","厂家"));}
    JSONObject create(){return devices.execute("demo-system","devices.create",request()).getJSONObject("data");}
    @Test void isolatedIdentityIsManualAndImmutableAndIdempotent(){
        JSONObject row=create();assertEquals("SPLIT_HELMET",row.getString("source"));assertEquals("ZLM_WEBRTC",row.getString("communicationProtocol"));assertEquals("SPLIT.001",row.getString("portalDeviceId"));assertNull(row.get("battery"));assertNull(row.get("online"));
        assertEquals(row.toJSONString(),devices.execute("demo-system","devices.create",request()).getJSONObject("data").toJSONString());
        for(String key:new String[]{"code","sn","deviceNumber","source"})assertThrows(AdminQueryService.QueryFailed.class,()->devices.execute("demo-system","devices.update",object("siteId","site-1","id",row.get("id"),"expectedVersion",1,"operationId","change-"+key,"data",object(key,"replacement"))));
        verify(archive,times(1)).requireUnusedIdentity("SPLIT.001");verify(archive,never()).ensureUnassigned(anyString());verify(archive,never()).ensureDirectUnassigned(anyString());verify(ledger,times(1)).write(any());
    }
    @Test void duplicateManufacturerNumberAndWrongDeviceTypeAreRejected(){
        create();JSONObject duplicate=request();duplicate.put("operationId","duplicate");duplicate.getJSONObject("data").put("code","other-code");duplicate.getJSONObject("data").put("sn","other-serial");
        assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->devices.execute("demo-system","devices.create",duplicate)).code);
        JSONObject wrong=request();wrong.put("operationId","wrong-type");wrong.getJSONObject("data").put("type","BELT");assertThrows(AdminQueryService.QueryFailed.class,()->devices.execute("demo-system","devices.create",wrong));
    }
    @Test void issueAndReturnPreserveManufacturerIdentityAndHistoricalScope(){
        JSONObject row=create(),person=rows(state,"people").getJSONObject(0);state.put("assignments",new JSONArray());
        AdminAssignmentService assignments=new AdminAssignmentService(ledger,guardian,queries);
        assignments.execute("demo-system","assignments.issue",object("siteId","site-1","personId",person.get("id"),"personVersion",person.getIntValue("version"),"items",JSONArray.of(object("deviceId",row.get("id"),"deviceVersion",1)),"operationId","issue","acknowledged",true));
        GuardianMasterProjection.apply(snapshot,state);assertNotNull(find(snapshot,"devices","SPLIT.001"));assertEquals("SPLIT_HELMET",find(snapshot,"devices","SPLIT.001").getString("source"));
        assertEquals("SPLIT.001",find(state,"devices",row.getString("id")).getString("portalDeviceId"));JSONObject assignment=rows(state,"assignments").getJSONObject(0);
        assertEquals(find(state,"people",person.getString("id")).getString("portalId"),GuardianSplitHelmetBridge.historicalContext(state,"SPLIT.001",assignment.getString("startedAt")).getString("personId"));
        assignments.execute("demo-system","assignments.return",object("siteId","site-1","personId",person.get("id"),"personVersion",find(state,"people",person.getString("id")).getIntValue("version"),"items",JSONArray.of(object("deviceId",row.get("id"),"deviceVersion",2,"assignmentId",assignment.get("id"),"assignmentVersion",1,"condition","GOOD")),"operationId","return","acknowledged",true));
        assertEquals("SPLIT.001",find(state,"devices",row.getString("id")).getString("portalDeviceId"));assertFalse(rows(state,"assignments").getJSONObject(0).getBooleanValue("active"));
    }
    @Test void projectionKeepsFieldsIndependentAndCannotInferWornFromRemoval(){
        JSONObject row=object("source","SPLIT_HELMET","active",true);
        SplitHelmetProjection.applyStatus(row,object("online",null,"freshness","UNKNOWN","battery",84,"batteryReportedAt","2026-11-10T00:00:00Z","batteryFreshness","STALE","pressure","999.1","pressureReportedAt","2026-11-16T00:00:00Z","pressureFreshness","CURRENT","storageTotal","128G","storageTotalReportedAt","2026-11-16T00:00:00Z","storageTotalFreshness","CURRENT","tfEnable","1","tfEnableFreshness","UNKNOWN","worn",true),true);
        assertNull(row.get("online"));assertEquals(84,row.getIntValue("battery"));assertEquals("STALE",row.getString("batteryFreshness"));assertEquals("CURRENT",row.getString("pressureFreshness"));assertEquals("128G",row.getString("storageTotal"));assertEquals("UNKNOWN",row.getString("tfEnableFreshness"));assertNull(row.get("worn"));
        SplitHelmetProjection.applyStatus(row,null,false);assertNull(row.get("online"));assertEquals("128G",row.getString("storageTotal"));assertFalse(row.getBooleanValue("mediaAvailable"));assertEquals("unconfigured",row.getString("mediaStatus"));
    }
}
