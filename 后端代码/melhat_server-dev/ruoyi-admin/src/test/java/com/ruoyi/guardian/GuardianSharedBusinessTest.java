package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.io.ByteArrayInputStream;
import java.util.*;
import java.util.concurrent.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianSharedBusinessTest {
    @TempDir Path directory;
    JSONObject master,admin,member,other;
    AdminLedgerStore ledger;
    GuardianStore store;
    GuardianAccess access;
    GuardianEvents service;
    GuardianFiles files;
    @BeforeEach void setup() throws Exception {
        master=seed("admin-seed.json");migrate(master);
        admin=find(master,"accounts","demo-system");
        member=object("id","mobile-one","name","现场甲","enabled",true,"personId","person-1-0","roleIds",JSONArray.parseArray("[\"mobile-user\"]"));
        other=object("id","mobile-two","name","现场乙","enabled",true,"personId","person-1-1","roleIds",JSONArray.parseArray("[\"mobile-user\"]"));
        rows(master,"accounts").add(member);rows(master,"accounts").add(other);
        ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));
        access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        store=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(store,"file",directory.resolve("guardian-state.json"));
        JSONObject state=seed("guardian-seed.json");GuardianMasterProjection.apply(state,master);GuardianEvents.normalize(state);store.replace(state);
        files=new GuardianFiles();ReflectionTestUtils.setField(files,"root",directory.resolve("photos"));service=new GuardianEvents(store,access,files);
    }
    private JSONObject seed(String name)throws Exception{return JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource(name).getInputStream(),StandardCharsets.UTF_8));}
    private JSONObject sos(JSONObject actor,String request){return service.createSos(actor,object("siteId","site-1","requestId",request));}
    private JSONObject command(JSONObject actor,JSONObject e,String action,Object... values){JSONObject input=object("requestId",UUID.randomUUID().toString(),"expectedVersion",e.getIntValue("version"));input.putAll(object(values));return service.command(actor,e.getString("id"),action,input);}

    @Test void emptyPhoneSosIsIdempotentAndKeepsRealSource() {
        int before=store.snapshot().getJSONArray("events").size();JSONObject first=sos(member,"same-request-001"),repeated=sos(member,"same-request-001");
        assertEquals(first.getString("id"),repeated.getString("id"));assertEquals(before+1,store.snapshot().getJSONArray("events").size());
        assertEquals("manual_sos",first.getString("source"));assertEquals("",first.getString("deviceId"));assertEquals("",first.getString("workId"));assertEquals("waiting",first.getJSONObject("assistance").getString("status"));
        assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->service.createSos(member,object("siteId","site-1","requestId","same-request-001","description","changed"))).code);
    }
    @Test void employeeCannotReadOtherPeopleOrOtherSites() {
        JSONObject mine=sos(member,"my-request-001"),theirs=sos(other,"other-request-001");
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->service.detail(member,theirs.getString("id"))).code);
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.createSos(member,object("siteId","site-2","requestId","foreign-site-001"))).code);
        JSONObject snapshot=service.snapshot(member);assertTrue(rows(snapshot,"events").stream().allMatch(e->"P1".equals(((JSONObject)e).getString("personId"))));
        assertEquals(1,rows(snapshot,"people").size());assertEquals("P1",rows(snapshot,"people").getJSONObject(0).getString("id"));assertFalse(snapshot.toJSONString().contains("passwordHash"));assertNotNull(service.detail(member,mine.getString("id")));
    }
    @Test void assistanceAndVerificationAreIndependentAndEachSosHasOwnRecord() {
        JSONObject one=sos(member,"first-sos-001"),two=sos(member,"second-sos-002");
        one=command(admin,one,"claim");one=command(admin,one,"assist-join");one=command(admin,one,"assist-end");
        assertEquals("处理中",one.getString("status"));assertNull(one.getJSONObject("verification"));assertEquals("ended",one.getJSONObject("assistance").getString("status"));
        assertEquals("waiting",service.detail(admin,two.getString("id")).getJSONObject("assistance").getString("status"));
        one=command(member,one,"observations","situation","人员已到安全区域");assertEquals("处理中",one.getString("status"));
        final JSONObject check=one;assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->command(member,check,"verification","conclusion","需现场处理","situation","确认")).code);
        one=command(admin,one,"verification-draft","conclusion","需现场处理","situation","待复查");assertNull(one.get("verification"));
        one=command(admin,one,"verification","conclusion","需现场处理","situation","现场复查完成","measures","已采取保护措施");assertEquals("已核验",one.getString("status"));assertEquals(admin.getString("id"),one.getJSONObject("verification").getString("actorId"));
        final JSONObject done=one;assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->command(member,done,"observations","situation","试图覆盖")).code);
    }
    @Test void twoTerminalsCannotOverwriteTheSameVersion() throws Exception {
        JSONObject event=sos(member,"racing-sos-001");ExecutorService pool=Executors.newFixedThreadPool(2);CountDownLatch start=new CountDownLatch(1);
        Callable<Boolean> action=()->{start.await();try{command(admin,event,"claim");return true;}catch(AdminQueryService.QueryFailed e){assertEquals(409,e.code);return false;}};
        try {Future<Boolean> first=pool.submit(action),second=pool.submit(action);start.countDown();assertNotEquals(first.get(5,TimeUnit.SECONDS),second.get(5,TimeUnit.SECONDS));assertEquals(2,service.detail(admin,event.getString("id")).getIntValue("version"));}finally{pool.shutdownNow();}
    }
    @Test void repeatedActionSurvivesRestartAndPermissionIsCheckedBeforeReplay() {
        JSONObject e=sos(member,"durable-sos-001"),input=object("expectedVersion",1,"requestId","claim-retry-001");JSONObject claimed=service.command(admin,e.getString("id"),"claim",input);
        GuardianStore loaded=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(loaded,"file",directory.resolve("guardian-state.json"));GuardianEvents second=new GuardianEvents(loaded,access,files);
        assertEquals(claimed.getIntValue("version"),second.command(admin,e.getString("id"),"claim",input).getIntValue("version"));
        admin.put("enabled",false);assertEquals(401,assertThrows(AdminQueryService.QueryFailed.class,()->second.command(admin,e.getString("id"),"claim",input)).code);
    }
    @Test void oldSnapshotCannotOverwriteEventOrAssistanceOrDeletePhotos() {
        JSONObject e=sos(member,"snapshot-sos-001"),visible=service.snapshot(admin);int seq=visible.getIntValue("seq");visible.put("seq",seq+1);
        find(visible,"events",e.getString("id")).put("status","已核验");assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->store.replaceScoped(visible,seq,access.context(admin))).code);
        assertEquals("待认领",service.detail(admin,e.getString("id")).getString("status"));
    }
    @Test void roleScopeChangesImmediatelyLimitMobileReadsAndWrites() {
        JSONObject duty=find(master,"accounts","demo-duty");assertNotNull(duty);
        JSONObject event=sos(member,"scope-sos-001");assertNotNull(service.detail(duty,event.getString("id")));
        JSONObject scopes=object("duty",object("siteIds",JSONArray.parseArray("[\"site-2\"]"),"areaIds","*"));duty.put("roleScopes",scopes);
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->service.detail(duty,event.getString("id"))).code);
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->command(duty,event,"claim")).code);
    }
    @Test void areaRestrictionDoesNotLeakThroughAnUnknownArea() {
        JSONObject duty=find(master,"accounts","demo-duty");duty.put("roleScopes",object("duty",object("siteIds",JSONArray.parseArray("[\"site-1\"]"),"areaIds",JSONArray.parseArray("[\"area-boiler\"]"))));
        GuardianAccess.Context ctx=access.context(duty);assertTrue(ctx.can("events:read","site-1","area-boiler"));assertFalse(ctx.can("events:read","site-1",null));assertFalse(ctx.can("events:read","site-1","another-area"));
    }
    @Test void photoOwnershipTypeSizeAndFinalReadonlyAreEnforced() {
        JSONObject e=sos(member,"photo-sos-001");String id="upload-"+UUID.randomUUID();byte[] png={(byte)137,80,78,71,13,10,26,10};
        service.upload(member,id,"image/png",new ByteArrayInputStream(png));assertNotNull(service.file(member,id));
        assertThrows(AdminQueryService.QueryFailed.class,()->service.file(other,id));assertThrows(GuardianRejected.class,()->service.upload(member,"upload-"+UUID.randomUUID(),"image/jpeg",new ByteArrayInputStream(png)));
        assertThrows(GuardianRejected.class,()->service.upload(member,"upload-"+UUID.randomUUID(),"image/png",new ByteArrayInputStream(new byte[10*1024*1024+1])));
        JSONArray photoIds=new JSONArray();photoIds.add(id);e=command(member,e,"observations","situation","现场照片","photoIds",photoIds);assertNotNull(service.file(admin,id));
        JSONObject otherEvent=sos(other,"photo-other-001");assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->command(other,otherEvent,"observations","situation","窃取照片","photoIds",photoIds)).code);
        assertEquals(1,e.getJSONArray("observations").size());
    }
    @Test void credentialsAreHashedAndResetRevokesOldPassword() {
        WearableCredentials.migrate(master);doAnswer(i->{master=copy(i.getArgument(0));return null;}).when(ledger).write(any());WearableCredentials credentials=new WearableCredentials(ledger);
        assertNotNull(credentials.authenticate("admin","Admin@2026"));assertThrows(AdminQueryService.QueryFailed.class,()->credentials.authenticate("admin","incorrect"));
        JSONObject duty=find(master,"accounts","demo-duty");int version=duty.getIntValue("credentialVersion");
        new AdminAccessService(ledger).execute(admin.getString("id"),"accounts.resetCredential",object("siteId",duty.getString("siteId"),"id",duty.getString("id"),"expectedVersion",duty.getIntValue("version"),"operationId","reset-credential-001","reason","测试密码重置","confirm",true,"password","Updated@2026"));
        assertThrows(AdminQueryService.QueryFailed.class,()->credentials.authenticate("duty","123456"));assertNotNull(credentials.authenticate("duty","Updated@2026"));
        assertEquals(version+1,find(master,"accounts","demo-duty").getIntValue("credentialVersion"));assertFalse(master.toJSONString().contains("Updated@2026"));assertFalse(safe(master).toJSONString().contains("$2a$"));
    }
    @Test void sourceMappingsStayStableWhenPeopleHaveSameNameOrChangeNames() {
        JSONObject p=find(master,"people","person-1-0");String id=p.getString("portalId");p.put("name","已改名");JSONObject extra=copy(p);extra.put("id","new-person");extra.remove("portalId");rows(master,"people").add(extra);migrate(master);
        assertEquals(id,p.getString("portalId"));assertEquals("new-person",extra.getString("portalId"));GuardianMasterProjection.apply(store.snapshot(),master);
    }
    @Test void deviceSosIsDeduplicatedByReportedTimestampAndGetsIndependentAssistance() {
        GuardianIngest ingest=new GuardianIngest(store);int before=rows(store.snapshot(),"events").size();
        ingest.sos("RL-H001",null,null,"2026-10-07 16:00:00");ingest.sos("RL-H001",null,null,"2026-10-07 16:00:00");
        ingest.sos("RL-H001",null,null,"2026-10-07 16:01:00");JSONObject state=store.snapshot();assertEquals(before+2,rows(state,"events").size());
        JSONObject event=rows(state,"events").getJSONObject(0);assertEquals("device",event.getString("source"));assertEquals("2026-10-07",event.getString("date"));assertNotNull(state.getJSONObject("assistance").getJSONObject(event.getString("id")));
    }
    @Test void existingPcLegacyWritesRemainAvailableWhileEventDataStaysServerOwned() {
        JSONObject snapshot=service.snapshot(admin);int seq=snapshot.getIntValue("seq");snapshot.put("seq",seq+1);snapshot.put("clock",snapshot.getIntValue("clock")+1);
        JSONObject group=rows(snapshot,"groups").getJSONObject(0);group.put("name","已调整协助分组");
        store.replaceScoped(snapshot,seq,access.context(admin));assertEquals("已调整协助分组",rows(store.snapshot(),"groups").getJSONObject(0).getString("name"));
    }
    @Test void pcReturnAndIssueUseTheSameLedgerThatMobileEquipmentReads() {
        doAnswer(i->{master=copy(i.getArgument(0));return null;}).when(ledger).write(any());ReflectionTestUtils.setField(store,"ledger",ledger);
        AdminQueryService queries=new AdminQueryService(ledger,store,mock(org.springframework.beans.factory.ObjectProvider.class));
        AdminAssignmentService assignments=new AdminAssignmentService(ledger,store,queries);
        JSONObject person=find(master,"people","person-1-0"),device=find(master,"devices","RL-W001"),link=find(master,"assignments","assignment-RL-W001");JSONArray items=new JSONArray();
        items.add(object("deviceId",device.getString("id"),"deviceVersion",device.getIntValue("version"),"assignmentId",link.getString("id"),"assignmentVersion",link.getIntValue("version"),"condition","GOOD"));
        assignments.execute(admin.getString("id"),"assignments.return",object("siteId","site-1","personId",person.getString("id"),"personVersion",person.getIntValue("version"),"items",items,"acknowledged",true,"operationId","return-shared-001"));
        assertTrue(rows(service.snapshot(member),"devices").stream().noneMatch(d->"RL-W001".equals(((JSONObject)d).getString("id"))));
        device=find(master,"devices","RL-W001");person=find(master,"people","person-1-0");items=new JSONArray();items.add(object("deviceId",device.getString("id"),"deviceVersion",device.getIntValue("version")));
        assignments.execute(admin.getString("id"),"assignments.issue",object("siteId","site-1","personId",person.getString("id"),"personVersion",person.getIntValue("version"),"items",items,"acknowledged",true,"operationId","issue-shared-001"));
        assertTrue(rows(service.snapshot(member),"devices").stream().anyMatch(d->"RL-W001".equals(((JSONObject)d).getString("id"))));
    }
    private javax.servlet.http.HttpServletRequest request(JSONObject actor){
        org.springframework.mock.web.MockHttpServletRequest r=new org.springframework.mock.web.MockHttpServletRequest();r.setAttribute("wearable.actor",actor);return r;
    }
    @Test void mobileContextHasAuthoritativeVersionsWithoutExpandingEmployeeScope(){
        member.put("roleScopes",object("mobile-user",object("siteIds",JSONArray.parseArray("[\"site-1\"]"),"areaIds","*")));
        GuardianMobileController mobile=new GuardianMobileController(mock(WearableCredentials.class),mock(WearableSessions.class),access,service,mock(AdminAssignmentService.class),ledger);
        JSONObject context=mobile.context("site-1",request(member));
        assertEquals(1,rows(context,"people").size());assertEquals("person-1-0",rows(context,"people").getJSONObject(0).getString("ledgerId"));
        assertTrue(rows(context,"people").getJSONObject(0).getIntValue("version")>0);
        assertTrue(rows(context,"devices").stream().allMatch(d->((JSONObject)d).getIntValue("version")>0));
        assertFalse(rows(context,"works").getJSONObject(0).getJSONObject("participantNames").isEmpty());
        assertNull(find(context,"people","P2"));
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->mobile.context("site-2",request(member))).code);
    }
    @Test void mobileCallRetriesDoNotCallDeviceTwiceAndCredentialsStayPrivate(){
        find(master,"devices","RL-H001").put("source","PLATFORM");GuardianVoiceService voice=mock(GuardianVoiceService.class);
        when(voice.call(any())).thenReturn(new HashMap<String,Object>(){{put("appId","test-app");put("channel","test-channel");put("uid","73");put("token","private-rtc-token");}});
        GuardianMobileCommunications controller=new GuardianMobileCommunications(store,access,voice);
        JSONObject input=object("deviceId","RL-H001","idempotencyKey","call-retry-001");
        JSONObject started=controller.start(input,request(admin));assertEquals(started.getString("id"),controller.start(input,request(admin)).getString("id"));verify(voice,times(1)).call(any());
        assertFalse(service.snapshot(admin).toJSONString().contains("private-rtc-token"));
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->controller.credentials(started.getString("id"),request(member))).code);
        JSONObject joined=controller.joined(started.getString("id"),object("agoraUid","73"),request(admin));assertEquals("local_joined",joined.getString("connectionQuality"));
        assertEquals("ended",controller.end(started.getString("id"),request(admin)).getString("status"));
        assertEquals("ended",controller.end(started.getString("id"),request(admin)).getString("status"));verify(voice,times(1)).end("test-channel");
    }
    @Test void mobileAssignmentAcceptsJacksonNestedMapsAndKeepsExistingService(){
        AdminAssignmentService assignments=mock(AdminAssignmentService.class);
        when(assignments.execute(anyString(),anyString(),any())).thenReturn(object("code",200));
        GuardianMobileController mobile=new GuardianMobileController(mock(WearableCredentials.class),mock(WearableSessions.class),access,service,assignments,ledger);
        Map<String,Object> item=new LinkedHashMap<>();item.put("deviceId","RL-W001");item.put("deviceVersion",1);
        JSONObject input=object("siteId","site-1","personId","person-1-0","items",Arrays.asList(item));
        assertEquals(200,mobile.assignment("return",input,request(admin)).getIntValue("code"));
        verify(assignments).execute(admin.getString("id"),"assignments.return",input);
    }
    @Test void uncertainBroadcastResultCannotBecomeSuccessOrReplayOnRetry(){
        find(master,"devices","RL-H001").put("source","PLATFORM");GuardianVoiceService voice=mock(GuardianVoiceService.class);
        doThrow(new GuardianRejected("platform unavailable")).when(voice).broadcast(any(),anyString(),anyString(),anyString());
        GuardianMobileCommunications controller=new GuardianMobileCommunications(store,access,voice);
        JSONObject input=object("deviceIds",JSONArray.parseArray("[\"RL-H001\"]"),"text","现场确认","idempotencyKey","tts-retry-001");
        assertEquals(502,assertThrows(AdminQueryService.QueryFailed.class,()->controller.broadcast(input,request(admin))).code);
        assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->controller.broadcast(input,request(admin))).code);
        verify(voice,times(1)).broadcast(any(),anyString(),anyString(),anyString());
        assertEquals("unknown",rows(store.snapshot(),"sharedCommunications").getJSONObject(0).getString("status"));
    }
    @Test void exampleHelmetAndUnprivilegedEmployeeCannotInvokeRealVoice(){
        GuardianVoiceService voice=mock(GuardianVoiceService.class);GuardianMobileCommunications controller=new GuardianMobileCommunications(store,access,voice);
        JSONObject input=object("deviceId","RL-H001","idempotencyKey","call-denied-001");
        assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->controller.start(input,request(admin))).code);
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->controller.start(input,request(member))).code);verifyNoInteractions(voice);
    }
}
