package com.ruoyi.guardian;

import com.alibaba.fastjson2.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PersonEquipmentContextTest {
    JSONObject master,state,actor,request;GuardianStore store;GuardianAccess access;PersonEquipmentContext service;WearableBusinessPolicy policy;JdbcTemplate jdbc;
    @BeforeEach void setup(){
        actor=object("id","demo-system","enabled",true);
        master=object("sites",JSONArray.of(object("id","site-1","portalStation","S1","enabled",true)),"accounts",JSONArray.of(actor),"roles",new JSONArray(),
                "people",JSONArray.of(object("id","p-ledger","portalId","P1","siteId","site-1","enabled",true)),
                "devices",JSONArray.of(object("id","d-hat","portalDeviceId","866652021714127","source","DIRECT_HELMET","type","HELMET","siteId","site-1","lifecycle","IN_USE"),object("id","d-belt","portalDeviceId","866652023095053","source","DIRECT_BELT","type","BELT","siteId","site-1","lifecycle","IN_USE")),
                "assignments",JSONArray.of(object("id","a-hat","personId","p-ledger","deviceId","d-hat","active",true,"version",3),object("id","a-belt","personId","p-ledger","deviceId","d-belt","active",true,"version",1)));
        state=object("people",JSONArray.of(object("id","P1","station","S1","siteId","site-1","active",true,"locationDeviceId","866652023095053","locationTimeBasis","RECEIVED_AT")),
                "devices",JSONArray.of(object("id","866652021714127","ledgerId","d-hat","station","S1","source","DIRECT_HELMET","online",true,"mediaAvailable",true,"voiceAvailable",true),object("id","866652023095053","ledgerId","d-belt","station","S1","source","DIRECT_BELT","online",true,"hookMappingConfirmed",true,"telemetryFreshness","CURRENT")));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));store=mock(GuardianStore.class);when(store.snapshot()).thenAnswer(i->copy(state));access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));policy=new WearableBusinessPolicy(jdbc);service=new PersonEquipmentContext(ledger,access,store,policy);
        request=object("personId","P1","assignmentId","a-hat","assignmentVersion",3);
    }
    @Test void snapshotOffersOnlyAssignedTargetsAndOfflineKeepsSupportedCapabilities(){
        state.getJSONArray("devices").getJSONObject(0).put("online",false);
        GuardianEvents events=new GuardianEvents(store,access,mock(GuardianFiles.class));ReflectionTestUtils.setField(events,"equipment",service);
        JSONObject snapshot=events.snapshot(actor),person=snapshot.getJSONObject("personEquipmentContext").getJSONObject("P1");
        assertEquals(2,person.getJSONArray("devices").size());JSONObject video=person.getJSONObject("features").getJSONObject("video");assertTrue(video.getBooleanValue("supported"));assertFalse(video.getBooleanValue("available"));assertEquals("设备离线",video.getString("reason"));assertEquals("a-hat",video.getString("assignmentId"));
        assertEquals("866652023095053",person.getJSONObject("features").getJSONObject("hooks").getString("deviceId"));assertEquals("待接入",person.getJSONArray("devices").getJSONObject(1).getJSONObject("featureStates").getJSONObject("voice").getString("reason"));
        assertEquals("RECEIVED_AT",person.getJSONObject("location").getString("locationTimeBasis"));
        master.getJSONArray("assignments").clear();service.decorate(access.context(actor),snapshot);assertTrue(snapshot.getJSONObject("personEquipmentContext").getJSONObject("P1").getJSONArray("devices").isEmpty());
    }
    @Test void realtimeRejectsUnassignedStaleVersionAndOfflineEvenForAcceptance(){
        assertEquals("a-hat",service.require(access.context(actor),"866652021714127",request,"video","communications:voice").getString("assignmentId"));
        request.put("assignmentVersion",2);assertEquals("ASSIGNMENT_CHANGED",assertThrows(AdminQueryService.QueryFailed.class,()->service.require(access.context(actor),"866652021714127",request,"video","communications:voice")).errorCode);
        request.put("assignmentVersion",3);request.put("acceptanceTest",true);master.getJSONArray("assignments").getJSONObject(0).put("active",false);assertEquals("ASSIGNMENT_REQUIRED",assertThrows(AdminQueryService.QueryFailed.class,()->service.require(access.context(actor),"866652021714127",request,"photo","communications:voice")).errorCode);
        master.getJSONArray("assignments").getJSONObject(0).put("active",true);state.getJSONArray("devices").getJSONObject(0).put("online",false);assertEquals("DEVICE_OFFLINE",assertThrows(AdminQueryService.QueryFailed.class,()->service.require(access.context(actor),"866652021714127",request,"photo","communications:voice")).errorCode);
    }
    @Test void liveVideoAcceptanceDoesNotAuthorizeVideoCallsAndPendingAdminStillNeedsIntegration(){
        JSONObject hat=state.getJSONArray("devices").getJSONObject(0),features=policy.features(hat);assertTrue(features.getJSONObject("video").getBooleanValue("verified"));assertFalse(features.getJSONObject("videoCall").getBooleanValue("verified"));
        assertEquals("FEATURE_PENDING_ACCEPTANCE",assertThrows(AdminQueryService.QueryFailed.class,()->service.require(access.context(actor),"866652021714127",request,"videoCall","communications:voice")).errorCode);
        request.put("acceptanceTest",true);hat.put("voiceAvailable",false);assertEquals("FEATURE_NOT_CONNECTED",assertThrows(AdminQueryService.QueryFailed.class,()->service.require(access.context(actor),"866652021714127",request,"voice","communications:voice")).errorCode);
    }
    @Test void pendingAcceptanceCannotBypassAssignmentContextOrSwitchTarget(){
        request.put("acceptanceTest",true);assertEquals("ASSIGNMENT_CHANGED",assertThrows(AdminQueryService.QueryFailed.class,()->service.require(access.context(actor),"866652023095053",request,"voice","communications:voice")).errorCode);
        JSONObject original=copy(request);request.put("personId","somebody-else");assertEquals("SESSION_CONTEXT_CHANGED",assertThrows(AdminQueryService.QueryFailed.class,()->PersonEquipmentContext.sameContext(original,request)).errorCode);
    }
    private javax.servlet.http.HttpServletRequest http(){org.springframework.mock.web.MockHttpServletRequest request=new org.springframework.mock.web.MockHttpServletRequest();request.setAttribute("wearable.actor",actor);return request;}
    private GuardianHelmetMediaController mediaController(com.ruoyi.melhat.direct.HelmetMediaService media){GuardianHelmetMediaController controller=new GuardianHelmetMediaController(access,media);ReflectionTestUtils.setField(controller,"equipment",service);return controller;}
    @Test void historyRemainsVisibleAfterReturnAndDisableWithoutLiveCredentials(){
        com.ruoyi.melhat.direct.HelmetMediaService media=mock(com.ruoyi.melhat.direct.HelmetMediaService.class);GuardianHelmetMediaController controller=mediaController(media);
        master.getJSONArray("devices").getJSONObject(0).put("lifecycle","DISABLED");master.getJSONArray("assignments").clear();state.getJSONArray("devices").getJSONObject(0).put("online",false);
        when(media.media("866652021714127")).thenReturn(object("items",JSONArray.of(object("id","historic-photo","siteId","site-1","personId","P1")),"commands",new JSONArray(),"live",object("url","must-not-leak")));
        JSONObject result=controller.media("866652021714127",http());assertEquals("historic-photo",result.getJSONArray("items").getJSONObject(0).getString("id"));assertFalse(result.containsKey("live"));
        assertEquals("ASSIGNMENT_REQUIRED",assertThrows(AdminQueryService.QueryFailed.class,()->controller.live("866652021714127","P1","a-hat",3,"viewer-test-001",true,http())).errorCode);verify(media,never()).live(anyString(),anyString(),any());
    }
    @Test void controllerCannotDispatchMissingOrStaleAssignmentButCleanupUsesCapturedPermission(){
        com.ruoyi.melhat.direct.HelmetMediaService media=mock(com.ruoyi.melhat.direct.HelmetMediaService.class);GuardianHelmetMediaController controller=mediaController(media);
        assertEquals("ASSIGNMENT_REQUIRED",assertThrows(AdminQueryService.QueryFailed.class,()->controller.command("866652021714127",object("action","start_video","acceptanceTest",true),http())).errorCode);
        JSONObject input=copy(request);input.put("action","start_video");input.put("assignmentVersion",2);assertEquals("ASSIGNMENT_CHANGED",assertThrows(AdminQueryService.QueryFailed.class,()->controller.command("866652021714127",input,http())).errorCode);verify(media,never()).command(anyString(),anyString(),any());
        master.getJSONArray("devices").getJSONObject(0).put("lifecycle","DISABLED");master.getJSONArray("assignments").clear();
        JSONObject stop=copy(request);stop.put("action","stop_video");stop.put("viewerSessionId","viewer-clean-001");JSONObject captured=copy(request);captured.put("siteId","site-1");when(media.requireCleanup("demo-system","866652021714127",stop)).thenReturn(captured);when(media.command(anyString(),anyString(),any())).thenReturn(object("status","completed"));
        assertEquals("completed",controller.command("866652021714127",stop,http()).getString("status"));
        captured.put("siteId","not-authorized");assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->controller.command("866652021714127",stop,http())).code);
    }
    @Test void mobileVideoCallNeedsIndependentAcceptanceAndOldWritesAreGone(){
        GuardianVoiceService voice=mock(GuardianVoiceService.class);GuardianMobileCommunications calls=new GuardianMobileCommunications(store,access,voice);ReflectionTestUtils.setField(calls,"equipment",service);
        jdbc.update("INSERT INTO wearable_feature_acceptance(device_id,feature_key,evidence) VALUES(?,?,?)","866652021714127","voice","test fixture only");
        JSONObject input=copy(request);input.put("deviceId","866652021714127");input.put("video",true);input.put("idempotencyKey","video-call-request-001");
        assertEquals("FEATURE_PENDING_ACCEPTANCE",assertThrows(AdminQueryService.QueryFailed.class,()->calls.start(input,http())).errorCode);verifyNoInteractions(voice);
        GuardianController legacy=new GuardianController(null,null,store,null,access,voice);assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->legacy.call(input,http())).code);assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->legacy.broadcast(input,http())).code);
        state.put("voiceSessions",object("old-call",object("ownerId","demo-system","hats",JSONArray.of(object("siteId","site-1")))));
        master.getJSONArray("assignments").clear();assertTrue(legacy.end(object("channel","old-call"),http()).getBooleanValue("ok"));verify(voice).end("old-call");
        state.getJSONObject("voiceSessions").getJSONObject("old-call").put("ownerId","another-owner");assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->legacy.end(object("channel","old-call"),http())).code);
    }
    @Test void sessionAuthorityTracksAssignmentVersionReturnActorAndCapturedSite(){
        JSONObject captured=copy(request);captured.put("deviceId","866652021714127");captured.put("siteId","site-1");
        service.withSessionAuthority(authority->assertTrue(authority.test("demo-system",captured)));
        master.getJSONArray("assignments").getJSONObject(0).put("version",4);service.withSessionAuthority(authority->assertFalse(authority.test("demo-system",captured)));
        master.getJSONArray("assignments").getJSONObject(0).put("version",3);master.getJSONArray("assignments").getJSONObject(0).put("active",false);service.withSessionAuthority(authority->assertFalse(authority.test("demo-system",captured)));
        master.getJSONArray("assignments").getJSONObject(0).put("active",true);master.getJSONArray("accounts").getJSONObject(0).put("enabled",false);service.withSessionAuthority(authority->assertFalse(authority.test("demo-system",captured)));
        master.getJSONArray("accounts").getJSONObject(0).put("enabled",true);captured.put("siteId","other-site");service.withSessionAuthority(authority->assertFalse(authority.test("demo-system",captured)));
        captured.put("siteId","site-1");master.getJSONArray("accounts").add(object("id","operator","enabled",true,"roleIds",JSONArray.of("operator-role")));
        master.getJSONArray("roles").add(object("id","operator-role","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-1"),"operations",JSONArray.of("communications:voice")))));
        service.withSessionAuthority(authority->assertTrue(authority.test("operator",captured)));master.getJSONArray("roles").getJSONObject(0).put("enabled",false);service.withSessionAuthority(authority->assertFalse(authority.test("operator",captured)));
    }
    @Test void revokedCallIsMarkedUnknownAndCredentialsRemovedEvenIfCloudCannotHangUp(){
        GuardianVoiceService voice=mock(GuardianVoiceService.class);GuardianMobileCommunications calls=new GuardianMobileCommunications(store,access,voice);ReflectionTestUtils.setField(calls,"equipment",service);
        JSONObject row=copy(request);row.putAll(object("id","COMM-active","requesterUserId","demo-system","operationType","call","deviceId","866652021714127","siteId","site-1","status","connected","protocol","SIP","channelName","SIP-active","credentials",object("test","private")));
        state.put("sharedCommunications",JSONArray.of(row));doAnswer(i->{GuardianStore.Edit edit=i.getArgument(0);edit.apply(state);return null;}).when(store).update(any());
        master.getJSONArray("assignments").clear();doThrow(new IllegalStateException("test unavailable")).when(voice).end("SIP-active");calls.reconcileInvalidSessions();
        JSONObject saved=state.getJSONArray("sharedCommunications").getJSONObject(0);assertEquals("unknown",saved.getString("status"));assertFalse(saved.containsKey("credentials"));assertEquals("P1",saved.getString("personId"));verify(voice).end("SIP-active");
    }
}
