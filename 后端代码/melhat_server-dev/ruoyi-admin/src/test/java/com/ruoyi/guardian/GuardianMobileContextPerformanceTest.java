package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.util.UUID;
import java.util.concurrent.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Exercises the read path and its existing command monitor, without timing-based performance limits. */
class GuardianMobileContextPerformanceTest {
    JSONObject master,state,member;
    AdminLedgerStore ledger;
    GuardianStore store;
    GuardianAccess access;
    GuardianMobileController mobile;
    JdbcTemplate jdbc;

    @BeforeEach void setup() {
        member=object("id","member","name","Mobile member","enabled",true,"personId","p1","siteId","site-1","roleIds",JSONArray.of("mobile-user"));
        master=object("sites",JSONArray.of(object("id","site-1","portalStation","S1","enabled",true),object("id","site-2","portalStation","S2","enabled",true)),
                "accounts",JSONArray.of(member),
                "roles",JSONArray.of(object("id","mobile-user","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-1","site-2"),"operations",JSONArray.of("self:read","works:read"))))),
                "people",JSONArray.of(object("id","p1","portalId","P1","name","Person 1","siteId","site-1","enabled",true,"version",3),object("id","p2","portalId","P2","siteId","site-2","enabled",true,"version",9)),
                "devices",JSONArray.of(device("d1","D1","site-1"),device("d2","D2","site-2")),
                "assignments",JSONArray.of(assignment("a1","p1","d1","site-1"),assignment("a2","p2","d2","site-2")),
                "history",JSONArray.of(object("id","h1","siteId","site-1","personId","p1","deviceId","d1","action","issue"),object("id","h2","siteId","site-2","personId","p2","deviceId","d2","action","issue")));
        state=object("people",JSONArray.of(object("id","P1","ledgerId","p1","station","S1"),object("id","P2","ledgerId","p2","station","S2")),
                "devices",JSONArray.of(observed("D1","d1","S1"),observed("D2","d2","S2")),
                "bindings",JSONArray.of(binding("a1","P1","D1","site-1","S1"),binding("a2","P2","D2","site-2","S2")));
        ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(call->copy(master));
        store=mock(GuardianStore.class);when(store.snapshot()).thenAnswer(call->copy(state));
        access=spy(new GuardianAccess(ledger,mock(AdminQueryService.class)));
        jdbc=spy(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","")));
        WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc);
        ReflectionTestUtils.setField(access,"businessPolicy",policy);
        GuardianEvents events=new GuardianEvents(store,access,mock(GuardianFiles.class));
        ReflectionTestUtils.setField(events,"equipment",new PersonEquipmentContext(ledger,access,store,policy));
        mobile=new GuardianMobileController(null,null,access,events,null,ledger);
        clearInvocations(jdbc,ledger,access,store);
    }
    private JSONObject device(String id,String portal,String site){return object("id",id,"portalDeviceId",portal,"siteId",site,"source","DIRECT_BELT","type","BELT","lifecycle","IN_USE","version",5);}
    private JSONObject observed(String id,String ledgerId,String station){return object("id",id,"ledgerId",ledgerId,"station",station,"source","DIRECT_BELT","online",true);}
    private JSONObject assignment(String id,String person,String device,String site){return object("id",id,"personId",person,"deviceId",device,"siteId",site,"active",true,"version",2);}
    private JSONObject binding(String id,String person,String device,String site,String station){return object("id","b-"+id,"assignmentId",id,"personId",person,"deviceId",device,"siteId",site,"station",station);}
    private MockHttpServletRequest request(){MockHttpServletRequest r=new MockHttpServletRequest();r.setAttribute("wearable.actor",member);return r;}
    private long evidenceQueries(){return mockingDetails(jdbc).getInvocations().stream().filter(call->call.getMethod().getName().equals("query")&&call.getArguments().length>1&&call.getArgument(0) instanceof String&&call.getArgument(1) instanceof org.springframework.jdbc.core.RowMapper&&((String)call.getArgument(0)).contains("FROM wearable_feature_acceptance")).count();}

    @Test void actualHttpReusesOneAuthorizedContextAndOneEvidenceBatch() throws Exception {
        for(int n=0;n<128;n++)rows(master,"devices").add(device("extra-"+n,"EXTRA-"+n,"site-2"));
        String body=MockMvcBuilders.standaloneSetup(mobile).build().perform(get("/api/guardian/v1/mobile/context").param("siteId","site-1").requestAttr("wearable.actor",member))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        JSONObject result=JSONObject.parseObject(body);
        assertEquals(1,rows(result,"people").size());assertEquals("P1",rows(result,"people").getJSONObject(0).getString("id"));
        assertEquals(3,rows(result,"people").getJSONObject(0).getIntValue("version"));
        assertEquals(1,rows(result,"devices").size());assertEquals(5,rows(result,"devices").getJSONObject(0).getIntValue("version"));
        assertEquals("a1",rows(result,"assignments").getJSONObject(0).getString("id"));
        assertEquals("h1",rows(result,"assignmentHistory").getJSONObject(0).getString("id"));
        assertEquals("a1",result.getJSONObject("personEquipmentContext").getJSONObject("P1").getJSONArray("devices").getJSONObject(0).getString("assignmentId"));
        verify(access,times(1)).context(any());verify(ledger,times(1)).read();verify(store,times(1)).snapshot();
        assertEquals(1,evidenceQueries(),"Evidence query count must not scale with the number of devices or decorations");
    }

    @Test void eachRequestReloadsAccountRoleAndAssignmentAuthority() {
        assertEquals(1,rows(mobile.context("site-1",request()),"devices").size());
        synchronized(ledger){find(master,"accounts","member").put("enabled",false);}
        assertEquals(401,assertThrows(AdminQueryService.QueryFailed.class,()->mobile.context("site-1",request())).code);
        synchronized(ledger){find(master,"accounts","member").put("enabled",true);find(master,"roles","mobile-user").put("enabled",false);}
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->mobile.context("site-1",request())).code);
        synchronized(ledger){
            find(master,"roles","mobile-user").put("enabled",true);find(master,"assignments","a1").put("active",false);
            find(master,"devices","d1").put("lifecycle","STOCK");find(master,"devices","d1").put("version",6);
            rows(state,"bindings").getJSONObject(0).put("end","2026-11-04T10:00:00Z");
            rows(master,"history").add(object("id","returned","siteId","site-1","personId","p1","deviceId","d1","action","return"));
        }
        JSONObject returned=mobile.context("site-1",request());
        assertTrue(rows(returned,"devices").isEmpty());assertFalse(rows(returned,"assignments").getJSONObject(0).getBooleanValue("active"));
        assertEquals(2,rows(returned,"assignmentHistory").size());
        assertTrue(returned.getJSONObject("personEquipmentContext").getJSONObject("P1").getJSONArray("devices").isEmpty());
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->mobile.context("site-2",request())).code);
    }

    @Test void optionalPolicyAbsenceRetainsEquipmentFeatureFallback() {
        ReflectionTestUtils.setField(access,"businessPolicy",null);
        JSONObject result=mobile.context("site-1",request());
        JSONObject target=result.getJSONObject("personEquipmentContext").getJSONObject("P1").getJSONArray("devices").getJSONObject(0);
        assertEquals("a1",target.getString("assignmentId"));assertTrue(target.getJSONObject("featureStates").getJSONObject("hooks").getBooleanValue("supported"));
        assertEquals(1,evidenceQueries());verify(access,times(1)).context(any());
    }

    @Test void concurrentAdminRevocationCannotSplitOneMobileRead() throws Exception {
        CountDownLatch insideSnapshot=new CountDownLatch(1),releaseSnapshot=new CountDownLatch(1),writerStarted=new CountDownLatch(1),writerEntered=new CountDownLatch(1);
        when(store.snapshot()).thenAnswer(call->{
            assertTrue(Thread.holdsLock(ledger),"Mobile read must retain the assignment and authorization monitor");
            insideSnapshot.countDown();assertTrue(releaseSnapshot.await(5,TimeUnit.SECONDS));return copy(state);
        });
        AdminAccessService changes=mock(AdminAccessService.class);when(changes.handles("roles.status")).thenReturn(true);
        when(changes.execute(anyString(),eq("roles.status"),any())).thenAnswer(call->{
            assertTrue(Thread.holdsLock(ledger));writerEntered.countDown();find(master,"roles","mobile-user").put("enabled",false);return object("ok",true);
        });
        AdminLedgerController admin=new AdminLedgerController(ledger,mock(AdminQueryService.class),mock(AdminDeviceService.class),mock(AdminAssignmentService.class),mock(AdminMaintenanceService.class),mock(AdminMasterService.class),changes);
        ExecutorService pool=Executors.newFixedThreadPool(2);
        try {
            Future<JSONObject> reading=pool.submit(()->mobile.context("site-1",request()));
            assertTrue(insideSnapshot.await(5,TimeUnit.SECONDS));
            Future<JSONObject> writing=pool.submit(()->{writerStarted.countDown();return admin.execute(object("type","roles.status","input",object()),request());});
            assertTrue(writerStarted.await(5,TimeUnit.SECONDS));assertFalse(writerEntered.await(100,TimeUnit.MILLISECONDS));
            releaseSnapshot.countDown();JSONObject before=reading.get(5,TimeUnit.SECONDS);writing.get(5,TimeUnit.SECONDS);
            assertEquals(1,rows(before,"devices").size());assertEquals(1,rows(before,"assignments").size());
            assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->mobile.context("site-1",request())).code);
        } finally {releaseSnapshot.countDown();pool.shutdownNow();}
    }
}
