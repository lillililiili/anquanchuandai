package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class AdminWorksTest {
    @TempDir Path directory;
    JdbcTemplate jdbc;WearableBusinessPolicy policy;GuardianStore store;GuardianAccess access;AdminWorks works;GuardianEvents events;JSONObject master,admin,member;AdminLedgerStore ledger;
    @BeforeEach void setup() throws Exception {
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));policy=new WearableBusinessPolicy(jdbc);
        master=seed("admin-seed.json");migrate(master);admin=find(master,"accounts","demo-system");
        member=object("id","work-member","name","现场甲","enabled",true,"personId","person-1-0","roleIds",JSONArray.of("mobile-user"));rows(master,"accounts").add(member);
        ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));access=new GuardianAccess(ledger,mock(AdminQueryService.class));ReflectionTestUtils.setField(access,"businessPolicy",policy);
        store=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(store,"file",directory.resolve("state.json"));ReflectionTestUtils.setField(store,"businessPolicy",policy);
        org.springframework.beans.factory.ObjectProvider<GuardianStore> provider=mock(org.springframework.beans.factory.ObjectProvider.class);when(provider.getIfAvailable()).thenReturn(store);ReflectionTestUtils.setField(policy,"guardian",provider);
        JSONObject state=seed("guardian-seed.json");GuardianMasterProjection.apply(state,master);state.put("groups",new JSONArray());state.put("fences",new JSONArray());store.replace(state);
        works=new AdminWorks(store,access,policy,ledger);GuardianFiles files=new GuardianFiles();ReflectionTestUtils.setField(files,"root",directory.resolve("photos"));events=new GuardianEvents(store,access,files);
    }
    JSONObject seed(String name)throws Exception{return JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource(name).getInputStream(),StandardCharsets.UTF_8));}
    JSONObject input(){return object("requestId",UUID.randomUUID().toString(),"siteId","site-1","name","现场设备检查","area","设备平台","plannedStartAt",Instant.now().minusSeconds(3600).toString(),"plannedEndAt",Instant.now().plusSeconds(3600).toString(),"leader","P1","supervisor","P2","members",JSONArray.of("P1"),"remarks","本地登记");}
    JSONObject create(){return works.write(admin,null,"create",input());}
    JSONObject act(JSONObject work,String action){return works.write(admin,work.getString("id"),action,object("requestId",UUID.randomUUID().toString(),"expectedVersion",work.getIntValue("version")));}
    JSONObject toggle(boolean enabled){return policy.configure(object("workBusinessEnabled",enabled,"expectedVersion",policy.config().getIntValue("version")),access.context(admin));}
    @Test void httpRoutesPreservePermissionDisabledModeAndVersionStatusCodes() throws Exception {
        MockMvc http=MockMvcBuilders.standaloneSetup(new AdminWorksController(works),new GuardianBusinessConfigController(access,policy)).setControllerAdvice(new GuardianError()).build();
        http.perform(get("/api/admin/v1/works").requestAttr("wearable.actor",member)).andExpect(status().isForbidden()).andExpect(jsonPath("$.errorCode").value("PERMISSION_DENIED"));
        http.perform(get("/api/guardian/v1/business-config").requestAttr("wearable.actor",member)).andExpect(status().isOk()).andExpect(jsonPath("$.workBusinessEnabled").value(true)).andExpect(jsonPath("$.version").value(1));
        JSONObject work=create(),stale=object("requestId",UUID.randomUUID().toString(),"expectedVersion",0,"action","start");
        http.perform(post("/api/admin/v1/works/"+work.getString("id")+"/actions").requestAttr("wearable.actor",admin).contentType("application/json").content(stale.toJSONString())).andExpect(status().isConflict()).andExpect(jsonPath("$.errorCode").value("VERSION_CONFLICT"));
        toggle(false);
        http.perform(post("/api/admin/v1/works").requestAttr("wearable.actor",admin).contentType("application/json").content(input().toJSONString())).andExpect(status().isConflict()).andExpect(jsonPath("$.errorCode").value("WORK_BUSINESS_DISABLED"));
        http.perform(get("/api/admin/v1/works/"+work.getString("id")).requestAttr("wearable.actor",admin)).andExpect(status().isOk()).andExpect(jsonPath("$.id").value(work.getString("id")));
    }
    @Test void registrationLifecycleIsDurableVersionedAndIdempotent() {
        JSONObject request=input(),work=works.write(admin,null,"create",request);
        assertEquals(work,works.write(admin,null,"create",request));assertEquals("LOCAL",work.getString("source"));assertEquals("待开始",work.getString("status"));assertEquals(2,rows(work,"members").size());
        assertEquals(1,works.list(admin,"site-1",null,null,null,1,20).getIntValue("total"));
        JSONObject started=act(work,"start");assertEquals("进行中",started.getString("status"));assertEquals(1,works.list(admin,null,null,null,null,1,20).getIntValue("activeCount"));
        assertEquals("VERSION_CONFLICT",assertThrows(AdminQueryService.QueryFailed.class,()->act(work,"finish")).errorCode);
        JSONObject ended=act(started,"finish");assertEquals("已结束",ended.getString("status"));assertEquals("WORK_READ_ONLY",assertThrows(AdminQueryService.QueryFailed.class,()->act(ended,"cancel")).errorCode);
        GuardianStore restarted=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(restarted,"file",directory.resolve("state.json"));assertEquals("已结束",find(restarted.snapshot(),"works",work.getString("id")).getString("status"));
        assertTrue(rows(store.snapshot(),"audit").stream().anyMatch(raw->"works.finish".equals(((JSONObject)raw).getString("action"))));
    }
    @Test void httpJsonArraysCreateUpdateDeduplicateRolesAndRejectNonStringMembers() throws Exception {
        MockMvc http=MockMvcBuilders.standaloneSetup(new AdminWorksController(works)).setControllerAdvice(new GuardianError()).build();
        JSONObject request=input();request.put("members",JSONArray.of("P1","P1","P3"));
        String created=http.perform(post("/api/admin/v1/works").requestAttr("wearable.actor",admin).contentType("application/json").content(request.toJSONString()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.members.length()").value(3)).andExpect(jsonPath("$.source").value("LOCAL"))
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        JSONObject work=JSONObject.parseObject(created);assertEquals(JSONArray.of("P1","P3","P2"),work.getJSONArray("members"));
        http.perform(post("/api/admin/v1/works").requestAttr("wearable.actor",admin).contentType("application/json").content(request.toJSONString()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(work.getString("id")));
        JSONObject change=object("requestId",UUID.randomUUID().toString(),"expectedVersion",1,"members",JSONArray.of("P3","P3"));
        http.perform(patch("/api/admin/v1/works/"+work.getString("id")).requestAttr("wearable.actor",admin).contentType("application/json").content(change.toJSONString()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(2)).andExpect(jsonPath("$.members.length()").value(3));
        assertEquals(JSONArray.of("P3","P1","P2"),works.detail(admin,work.getString("id")).getJSONArray("members"));
        for(Object invalid:java.util.Arrays.asList(JSONArray.of(1),JSONArray.of(object("id","P1")),"P1")) {
            JSONObject bad=input();bad.put("members",invalid);
            http.perform(post("/api/admin/v1/works").requestAttr("wearable.actor",admin).contentType("application/json").content(bad.toJSONString()))
                    .andExpect(status().isBadRequest()).andExpect(jsonPath("$.errorCode").value("INVALID_MEMBERS"));
        }
        assertEquals(1,works.list(admin,null,null,null,null,1,20).getIntValue("total"));
    }
    @Test void permissionsTimeAndOverlappingParticipantsAreValidated() {
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->works.options(member,"site-1")).code);
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->works.write(member,null,"create",input())).code);
        JSONObject cross=input();cross.put("members",JSONArray.of("missing-person"));assertEquals("INVALID_MEMBERS",assertThrows(AdminQueryService.QueryFailed.class,()->works.write(admin,null,"create",cross)).errorCode);
        JSONObject first=act(create(),"start"),second=create();assertEquals("WORK_CONFLICT",assertThrows(AdminQueryService.QueryFailed.class,()->act(second,"start")).errorCode);
        act(first,"finish");assertEquals("进行中",act(second,"start").getString("status"));
        JSONObject future=input();future.put("plannedStartAt",Instant.now().plusSeconds(7200).toString());future.put("plannedEndAt",Instant.now().plusSeconds(10800).toString());JSONObject waiting=works.write(admin,null,"create",future);
        assertEquals("WORK_OUTSIDE_TIME",assertThrows(AdminQueryService.QueryFailed.class,()->act(waiting,"start")).errorCode);
    }
    @Test void disabledModeHidesWorkButPreservesEvidenceAndPhoneSosClosure() {
        JSONObject work=act(create(),"start");JSONObject event=events.createSos(member,object("requestId",UUID.randomUUID().toString(),"siteId","site-1"));String id=event.getString("id");
        assertEquals(work.getString("id"),event.getString("workId"));String historical=event.getJSONObject("snapshot").toJSONString();
        toggle(false);assertTrue(rows(events.snapshot(admin),"works").isEmpty());JSONObject hidden=events.detail(admin,id);assertFalse(hidden.containsKey("workId"));assertFalse(hidden.containsKey("externalStatus"));assertFalse(hidden.getJSONObject("snapshot").containsKey("supervisorName"));
        assertEquals("WORK_BUSINESS_DISABLED",assertThrows(AdminQueryService.QueryFailed.class,()->works.write(admin,null,"create",input())).errorCode);
        JSONObject off=events.createSos(member,object("requestId",UUID.randomUUID().toString(),"siteId","site-1"));assertFalse(off.containsKey("workId"));assertEquals("manual_sos",off.getString("source"));
        JSONObject done=events.command(admin,id,"verification",object("requestId",UUID.randomUUID().toString(),"expectedVersion",event.getIntValue("version"),"conclusion","需现场处理","situation","已完成现场核查"));assertEquals("已核验",done.getString("status"));
        assertEquals(historical,find(store.snapshot(),"events",id).getJSONObject("snapshot").toJSONString());
        toggle(true);assertEquals(work.getString("id"),events.detail(admin,id).getString("workId"));assertEquals("",events.detail(admin,off.getString("id")).getString("workId"));assertEquals("进行中",works.detail(admin,work.getString("id")).getString("status"));
    }
    @Test void configurationMigrationMergesFieldsAndRequiresCurrentVersion() {
        assertTrue(policy.config().getBooleanValue("workBusinessEnabled"));
        policy.configure(object("simulatedWatchVisible",false,"expectedVersion",1),access.context(admin));toggle(false);assertFalse(policy.config().getBooleanValue("simulatedWatchVisible"));
        assertEquals("VERSION_CONFLICT",assertThrows(AdminQueryService.QueryFailed.class,()->policy.configure(object("workBusinessEnabled",true,"expectedVersion",1),access.context(admin))).errorCode);
        assertEquals("VERSION_CONFLICT",assertThrows(AdminQueryService.QueryFailed.class,()->policy.configure(object("workBusinessEnabled",true),access.context(admin))).errorCode);
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->policy.configure(object("workBusinessEnabled",true,"expectedVersion",3),access.context(member))).code);
        JSONObject old=policy.config();old.remove("workBusinessEnabled");jdbc.update("UPDATE wearable_business_config SET body=? WHERE id=1",old.toJSONString());assertTrue(new WearableBusinessPolicy(jdbc).config().getBooleanValue("workBusinessEnabled"));
    }
    @Test void crossDayWorksAndSnapshotNamesDoNotChangePastEvents() {
        JSONObject request=input();request.put("plannedStartAt",Instant.now().minusSeconds(72000).toString());request.put("plannedEndAt",Instant.now().plusSeconds(72000).toString());
        JSONObject work=act(works.write(admin,null,"create",request),"start");JSONObject state=store.snapshot(),match=WorkBusiness.match(state,"P1","S1",Instant.now());assertNotNull(match);
        JSONObject event=object("snapshot",new JSONObject());WorkBusiness.capture(state,event,match);String original=event.getJSONObject("snapshot").getString("supervisorName");
        find(state,"people","P2").put("name","后续名称");WorkBusiness.capture(state,event,match);assertEquals(original,event.getJSONObject("snapshot").getString("supervisorName"));
        assertNull(WorkBusiness.match(state,"P1","S1",Instant.now().plusSeconds(80000)));find(state,"people","P1").put("active",false);assertNull(WorkBusiness.match(state,"P1","S1",Instant.now()));
        toggle(false);store.update(next->{find(next,"people","P1").put("active",false);next.put("bindings",new JSONArray());return true;});toggle(true);assertDoesNotThrow(()->store.update(next->{next.put("seq",next.getIntValue("seq")+1);return true;}));
    }
    @Test void cancelledWorkDoesNotOccupyParticipants() {
        JSONObject first=act(create(),"start");act(first,"cancel");JSONObject second=act(create(),"start");assertEquals("进行中",second.getString("status"));
        JSONObject state=store.snapshot();assertEquals(second.getString("id"),WorkBusiness.match(state,"P1","S1",Instant.now()).getString("id"));
        JSONObject ambiguous=copy(second);ambiguous.put("id","legacy-ambiguous");rows(state,"works").add(ambiguous);assertNull(WorkBusiness.match(state,"P1","S1",Instant.now()));
    }
    @Test void legacyWorkWithDisabledParticipantCanReopenWithoutBlockingOtherBusiness() {
        JSONObject work=act(create(),"start");
        store.update(state->{JSONObject legacy=find(state,"works",work.getString("id"));legacy.put("source","LEGACY");legacy.put("status","监护中");return true;});
        toggle(false);store.update(state->{find(state,"people","P1").put("active",false);state.put("bindings",new JSONArray());return true;});
        assertTrue(toggle(true).getBooleanValue("workBusinessEnabled"));
        assertNull(WorkBusiness.match(store.snapshot(),"P2","S1",Instant.now()));
        assertDoesNotThrow(()->store.update(state->{state.put("seq",state.getIntValue("seq")+1);return true;}));
        assertEquals("进行中",works.detail(admin,work.getString("id")).getString("status"));
        assertTrue(rows(store.snapshot(),"audit").stream().anyMatch(raw->"businessConfig.update".equals(((JSONObject)raw).getString("action"))));
    }
    @Test void disabledModeKeepsHelmetSourceLifecycleSyncAndAuditHistory() {
        JSONObject work=act(create(),"start");JSONObject event=events.createSos(member,object("requestId",UUID.randomUUID().toString(),"siteId","site-1"));
        store.update(state->{JSONObject raw=find(state,"events",event.getString("id"));raw.put("source","DEVICE");raw.put("protocol","direct-helmet");raw.put("sourceRecordId",999L);return true;});
        HelmetEventDelivery delivery=mock(HelmetEventDelivery.class);ReflectionTestUtils.setField(events,"helmetDelivery",delivery);
        toggle(false);
        JSONObject result=events.command(admin,event.getString("id"),"verification",object("requestId",UUID.randomUUID().toString(),"expectedVersion",event.getIntValue("version"),"conclusion","需现场处理","situation","设备原始告警完成核验"));
        assertEquals("direct-helmet",result.getString("protocol"));assertEquals("DEVICE",result.getString("source"));assertEquals(999L,result.getLongValue("sourceRecordId"));assertFalse(result.containsKey("workId"));
        verify(delivery).synchronize(result);
        AdminAccessService audit=new AdminAccessService(ledger);ReflectionTestUtils.setField(audit,"guardian",store);
        JSONObject logs=JSONObject.parseObject(JSONObject.toJSONString(audit.query("demo-system","audit",object("siteId","site-1","pageNum",1,"pageSize",100))));
        assertTrue(logs.toJSONString().contains("works.create"));assertTrue(logs.toJSONString().contains("businessConfig.update"));
        assertEquals(work.getString("id"),find(store.snapshot(),"events",event.getString("id")).getString("workId"));
    }
}
