package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.*;
import okhttp3.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.util.function.Function;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Isolated HTTP authorization checks: no database, vendor traffic or physical device commands. */
class SplitHelmetSessionAuthorizationTest {
    private static JSONObject object(Object... values){return SplitTelemetry.obj(values);}
    SplitHelmetService service; PersonEquipmentContext equipment; GuardianAccess access; JSONObject ledger;
    final String sessionId="SPLIT-test", actorId="dispatcher";
    @BeforeEach @SuppressWarnings("unchecked") void setup() {
        ledger=object("accounts",JSONArray.of(object("id",actorId,"enabled",true,"roleIds",JSONArray.of("reader"))),
            "roles",JSONArray.of(object("id","reader","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("current-site"),"operations",JSONArray.of("assets:read","communications:voice"))))),
            "sites",JSONArray.of(object("id","current-site","enabled",true),object("id","historical-site","enabled",true)),"devices",new JSONArray(),"people",new JSONArray());
        AdminLedgerStore store=mock(AdminLedgerStore.class);when(store.read()).thenAnswer(i->JSONObject.parseObject(ledger.toJSONString()));
        access=new GuardianAccess(store,mock(AdminQueryService.class));service=mock(SplitHelmetService.class);equipment=mock(PersonEquipmentContext.class);
        when(equipment.execute(any(),any())).thenAnswer(i->((Function<GuardianAccess.Context,Object>)i.getArgument(1)).apply(access.context(i.getArgument(0))));
    }
    MockMvc http(SplitHelmetService target){return MockMvcBuilders.standaloneSetup(new SplitHelmetSessionController(target,equipment,access)).setControllerAdvice(new GuardianError()).build();}
    JSONObject recipient(String sn){return object("deviceId",sn,"personId","person-"+sn,"assignmentId","assignment-"+sn,"assignmentVersion",1,"siteId","current-site");}
    JSONObject session(){return object("id",sessionId,"actorId",actorId,"status","offered","expiresMillis",System.currentTimeMillis()+180000,"mode","call","video",false,"recipients",JSONArray.of(recipient("SN1")),"deviceIds",JSONArray.of("SN1"),"remoteSessions",JSONArray.of(object("helmetSn","SN1")));}

    @Test void wrongOwnerCannotNegotiateOrHeartbeatEvenWhenDevicePermissionWouldPass()throws Exception {
        when(service.owned(actorId,sessionId)).thenThrow(new AdminQueryService.QueryFailed(404,"CALL_NOT_FOUND","会话不属于当前账号"));
        MockMvc mvc=http(service);
        mvc.perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/devices/SN1/play").requestAttr("wearable.actor",object("id",actorId)).contentType("application/sdp").content("v=0\r\n"))
            .andExpect(status().isNotFound());
        mvc.perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/heartbeat").requestAttr("wearable.actor",object("id",actorId)))
            .andExpect(status().isNotFound());
        verify(equipment,never()).require(any(),anyString(),any(),anyString(),anyString());verify(service,never()).signal(anyString(),anyString(),anyString(),anyString(),anyString());verify(service,never()).heartbeat(anyString(),anyString());
    }
    @Test @SuppressWarnings("unchecked") void foreignDeviceCannotReuseAnOwnedSessionProxy()throws Exception {
        SplitHelmetProperties properties=new SplitHelmetProperties();properties.setEnabled(true);properties.setAllowedDevices("SN1,SN2");
        SplitHelmetStore store=mock(SplitHelmetStore.class);SplitHelmetClient vendor=mock(SplitHelmetClient.class);ObjectProvider<SplitHelmetBridge> bridges=mock(ObjectProvider.class);SplitHelmetBridge bridge=mock(SplitHelmetBridge.class);
        when(bridges.getIfAvailable()).thenReturn(bridge);when(bridge.isRegistered(anyString())).thenReturn(true);when(store.session(sessionId)).thenAnswer(i->session());when(store.owns(sessionId,"SN2")).thenReturn(false);
        SplitHelmetService real=new SplitHelmetService(properties,vendor,store,bridges);
        http(real).perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/devices/SN2/talk").requestAttr("wearable.actor",object("id",actorId)).contentType("application/sdp").content("v=0\r\n"))
            .andExpect(status().isConflict()).andExpect(jsonPath("$.errorCode").value("CALL_EXPIRED"));
        verifyNoInteractions(vendor);
    }
    @Test void changedAssignmentPreventsHeartbeatAndDoesNotRenewTheVendorLease()throws Exception {
        when(service.owned(actorId,sessionId)).thenReturn(session());
        when(equipment.require(any(),eq("SN1"),any(),eq("voice"),eq("communications:voice"))).thenThrow(new AdminQueryService.QueryFailed(409,"ASSIGNMENT_CHANGED","领用已变化"));
        http(service).perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/heartbeat").requestAttr("wearable.actor",object("id",actorId)))
            .andExpect(status().isConflict()).andExpect(jsonPath("$.errorCode").value("ASSIGNMENT_CHANGED"));
        verify(service,never()).heartbeat(anyString(),anyString());
    }
    @Test void assignmentRevokedDuringSdpNegotiationDiscardsAnswerAndClosesOriginalSession()throws Exception {
        when(service.owned(actorId,sessionId)).thenAnswer(i->session());when(service.signal(actorId,sessionId,"SN1","play","v=0\r\n")).thenReturn("v=0\r\nanswer");
        when(equipment.require(any(),eq("SN1"),any(),eq("voice"),eq("communications:voice"))).thenReturn(recipient("SN1")).thenThrow(new AdminQueryService.QueryFailed(409,"ASSIGNMENT_CHANGED","协商期间领用变化"));
        http(service).perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/devices/SN1/play").requestAttr("wearable.actor",object("id",actorId)).contentType("application/sdp").content("v=0\r\n"))
            .andExpect(status().isConflict()).andExpect(jsonPath("$.errorCode").value("ASSIGNMENT_CHANGED"));verify(service).end(sessionId);
    }
    @Test void oneUnauthorizedGroupRecipientRejectsSdpBeforeAnyMediaSubmission()throws Exception {
        JSONObject row=session();row.getJSONArray("recipients").add(recipient("SN2"));when(service.owned(actorId,sessionId)).thenReturn(row);
        when(equipment.require(any(),eq("SN2"),any(),eq("voice"),eq("communications:voice"))).thenThrow(new AdminQueryService.QueryFailed(403,"PERMISSION_DENIED","无权限"));
        http(service).perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/devices/SN1/play").requestAttr("wearable.actor",object("id",actorId)).contentType("application/sdp").content("v=0\r\n"))
            .andExpect(status().isForbidden());
        verify(service,never()).signal(anyString(),anyString(),anyString(),anyString(),anyString());
    }
    @Test void watchingDoesNotGrantMicrophoneAndActiveMonitorTalkRechecksOnRenewal() throws Exception {
        JSONObject row=session(); row.put("mode","preview"); row.put("video",true);
        when(service.owned(actorId,sessionId)).thenReturn(row);
        when(equipment.require(any(),eq("SN1"),any(),eq("voice"),anyString()))
                .thenThrow(new AdminQueryService.QueryFailed(403,"PERMISSION_DENIED","无对讲权限"));
        MockMvc mvc=http(service); String path="/api/guardian/v1/split/sessions/"+sessionId;
        mvc.perform(post(path+"/devices/SN1/play").requestAttr("wearable.actor",object("id",actorId)).contentType("application/sdp").content("v=0")).andExpect(status().isOk());
        mvc.perform(post(path+"/devices/SN1/talk").requestAttr("wearable.actor",object("id",actorId)).contentType("application/sdp").content("v=0")).andExpect(status().isForbidden());
        verify(service,never()).enableMonitorTalk(anyString(),anyString(),anyString());
        verify(service,never()).signal(anyString(),anyString(),anyString(),eq("talk"),anyString());
        row.put("monitorTalk",true);
        mvc.perform(post(path+"/heartbeat").requestAttr("wearable.actor",object("id",actorId))).andExpect(status().isForbidden());
        verify(service,never()).heartbeat(anyString(),anyString());
    }
    @Test void cleanupRemainsAvailableToOwnerAfterAnAssignmentChange()throws Exception {
        when(service.owned(actorId,sessionId)).thenReturn(session());when(service.callState(sessionId)).thenReturn(object("status","ended"));
        http(service).perform(post("/api/guardian/v1/split/sessions/"+sessionId+"/end").requestAttr("wearable.actor",object("id",actorId)))
            .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ended"));
        verify(service).end(sessionId);verifyNoInteractions(equipment);
    }
    @Test void currentDeviceScopeDoesNotGrantAFileFromAnUnauthorizedHistoricalSite()throws Exception {
        String id=new String(new char[64]).replace('\0','a');when(service.fileContext("SN1",id)).thenReturn(object("siteId","historical-site","areaId","historical-area"));
        http(service).perform(get("/api/guardian/v1/split/devices/SN1/files/"+id).requestAttr("wearable.actor",object("id",actorId)))
            .andExpect(status().isForbidden()).andExpect(jsonPath("$.errorCode").value("PERMISSION_DENIED"));
        verify(service,never()).fileSnapshot(anyString(),anyString());verify(service,never()).client();
    }
    @Test void historicalReaderCanReadFileWithoutCurrentAssignmentOrCurrentSitePermission()throws Exception {
        ledger.getJSONArray("roles").getJSONObject(0).getJSONArray("grants").getJSONObject(0).put("siteIds",JSONArray.of("historical-site"));
        String id=new String(new char[64]).replace('\0','b'), url="https://files.example.test/SN1/clip.mp4";when(service.fileContext("SN1",id)).thenReturn(object("siteId","historical-site","areaId","historical-area"));when(service.fileSnapshot("SN1",id)).thenReturn(object("siteId","historical-site","areaId","historical-area","privateSourceUrl",url));
        SplitHelmetClient vendor=mock(SplitHelmetClient.class);when(service.client()).thenReturn(vendor);
        when(vendor.file(url,"SN1",null)).thenReturn(new Response.Builder().request(new Request.Builder().url(url).build()).protocol(Protocol.HTTP_1_1).code(200).message("OK").header("Content-Type","video/mp4").body(ResponseBody.create(MediaType.get("video/mp4"),new byte[]{1,2,3})).build());
        http(service).perform(get("/api/guardian/v1/split/devices/SN1/files/"+id).requestAttr("wearable.actor",object("id",actorId)))
            .andExpect(status().isOk()).andExpect(content().bytes(new byte[]{1,2,3})).andExpect(header().string("Cache-Control","no-store, private"));
        verifyNoInteractions(equipment);
    }
    @Test void refreshedFileSnapshotCannotChangeIntoAnUnauthorizedHistoricalScope()throws Exception {
        String id=new String(new char[64]).replace('\0','c');
        when(service.fileContext("SN1",id)).thenReturn(object("siteId","current-site"));
        when(service.fileSnapshot("SN1",id)).thenReturn(object("siteId","historical-site","privateSourceUrl","https://files.example.test/SN1/changed.mp4"));
        http(service).perform(get("/api/guardian/v1/split/devices/SN1/files/"+id).requestAttr("wearable.actor",object("id",actorId)))
            .andExpect(status().isForbidden()).andExpect(jsonPath("$.errorCode").value("PERMISSION_DENIED"));
        verify(service,never()).client();
    }
}
