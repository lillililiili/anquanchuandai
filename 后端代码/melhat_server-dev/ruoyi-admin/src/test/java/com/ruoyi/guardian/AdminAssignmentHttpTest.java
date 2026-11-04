package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** HTTP serialization regression only; does not claim database/cluster integration coverage. */
class AdminAssignmentHttpTest {
    AtomicReference<JSONObject> saved;
    AdminLedgerStore ledger;
    AdminAssignmentService assignments;
    WearableBusinessPolicy policy;
    MockMvc http;
    ObjectMapper jackson = new ObjectMapper();
    String actorId = "demo-site";

    @BeforeEach void setup() throws Exception {
        JSONObject seed = JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(), StandardCharsets.UTF_8));
        migrate(seed);
        seed.put("devices", JSONArray.of(object("id","http-belt","siteId","site-1","name","HTTP belt","code","HTTP-BELT","type","BELT",
                "source","DIRECT_BELT","deviceNumber","HTTP-BELT-LOGIN","lifecycle","STOCK","relation","UNASSIGNED","version",1)));
        seed.put("assignments", new JSONArray());
        saved = new AtomicReference<>(seed);
        ledger = mock(AdminLedgerStore.class);
        when(ledger.mutate(any())).thenAnswer(call -> ((java.util.function.Supplier<?>) call.getArgument(0)).get());
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        GuardianStore guardian = mock(GuardianStore.class);
        AdminQueryService queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
        assignments = spy(new AdminAssignmentService(ledger, guardian, queries));
        policy = mock(WearableBusinessPolicy.class);
        when(policy.config()).thenReturn(object("simulatedWatchVisible",false));
        ReflectionTestUtils.setField(assignments,"businessPolicy",policy);
        doAnswer(call -> {
            JSONObject input = call.getArgument(2);
            Object items = input.get("items");
            assertTrue(items instanceof ArrayList, "Jackson must supply ArrayList items");
            assertTrue(((List<?>)items).get(0) instanceof LinkedHashMap, "Jackson must supply LinkedHashMap rows");
            return call.callRealMethod();
        }).when(assignments).execute(anyString(),anyString(),any(JSONObject.class));
        AdminLedgerController controller = new AdminLedgerController(ledger,queries,mock(AdminDeviceService.class),assignments,
                mock(AdminMaintenanceService.class),mock(AdminMasterService.class),mock(AdminAccessService.class));
        http = MockMvcBuilders.standaloneSetup(controller).setMessageConverters(new MappingJackson2HttpMessageConverter(jackson)).build();
    }
    Map<String,Object> map(Object... values) { Map<String,Object> result=new LinkedHashMap<>(); for(int i=0;i<values.length;i+=2)result.put((String)values[i],values[i+1]);return result; }
    Map<String,Object> issue() {
        JSONObject person=rows(saved.get(),"people").getJSONObject(0);
        return map("siteId","site-1","personId",person.getString("id"),"personVersion",person.getIntValue("version"),
                "items",Arrays.asList(map("deviceId","http-belt","deviceVersion",1)),"operationId","http-issue","acknowledged",true);
    }
    JSONObject send(String type,Map<String,Object> input,int expected) throws Exception {
        String response=http.perform(post("/api/admin/v1/execute").requestAttr("wearable.actor",find(saved.get(),"accounts",actorId))
                .contentType(MediaType.APPLICATION_JSON).content(jackson.writeValueAsBytes(map("type",type,"input",input))))
                .andExpect(status().is(expected)).andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return JSONObject.parseObject(response);
    }
    @Test void jacksonIssueReturnAndReplayKeepSingleMutation() throws Exception {
        Map<String,Object> input=issue();
        JSONObject issued=send("assignments.issue",input,200);
        String committed=saved.get().toJSONString();
        assertEquals(issued,send("assignments.issue",input,200));
        assertEquals(committed,saved.get().toJSONString());
        JSONObject person=rows(saved.get(),"people").getJSONObject(0), link=rows(saved.get(),"assignments").getJSONObject(0);
        Map<String,Object> giveBack=map("siteId","site-1","personId",person.getString("id"),"personVersion",person.getIntValue("version"),
                "items",Arrays.asList(map("deviceId","http-belt","deviceVersion",2,"assignmentId",link.getString("id"),"assignmentVersion",1,"condition","GOOD")),
                "operationId","http-return","acknowledged",true);
        JSONObject returned=send("assignments.return",giveBack,200);
        committed=saved.get().toJSONString();
        assertEquals(returned,send("assignments.return",giveBack,200));
        assertEquals(committed,saved.get().toJSONString());
        assertFalse(rows(saved.get(),"assignments").getJSONObject(0).getBooleanValue("active"));
        verify(ledger,times(2)).write(any());
    }
    @Test void replayWithVisibleSimulationStillChecksDeviceScope() throws Exception {
        when(policy.config()).thenReturn(object("simulatedWatchVisible",true));
        Map<String,Object> input=issue();
        JSONObject issued=send("assignments.issue",input,200);
        assertEquals(issued,send("assignments.issue",input,200));
        find(saved.get(),"devices","http-belt").put("siteId","site-2");
        assertEquals("PERMISSION_DENIED",send("assignments.issue",input,403).getString("errorCode"));
        verify(ledger,times(1)).write(any());
    }
    @Test void staleVersionsRemainConflictsWithoutWrites() throws Exception {
        Map<String,Object> input=issue();input.put("personVersion",0);
        assertEquals("VERSION_CONFLICT",send("assignments.issue",input,409).getString("errorCode"));
        input=issue();input.put("items",Arrays.asList(map("deviceId","http-belt","deviceVersion",0)));
        assertEquals("VERSION_CONFLICT",send("assignments.issue",input,409).getString("errorCode"));
        verify(ledger,never()).write(any());
    }
    @Test void replayRejectsChangedContentAndRevokedActor() throws Exception {
        Map<String,Object> input=issue();send("assignments.issue",input,200);
        input.put("acknowledged",false);
        assertEquals("IDEMPOTENCY_CONFLICT",send("assignments.issue",input,409).getString("errorCode"));
        input.put("acknowledged",true);
        rows(find(saved.get(),"accounts",actorId),"roleIds").clear();
        assertEquals("PERMISSION_DENIED",send("assignments.issue",input,403).getString("errorCode"));
        verify(ledger,times(1)).write(any());
    }
    @Test void hiddenWatchPolicyRemainsEnforcedForJacksonItems() throws Exception {
        find(saved.get(),"devices","http-belt").put("source","DEMO_WATCH");
        assertEquals("SIMULATION_HIDDEN",send("assignments.issue",issue(),409).getString("errorCode"));
        verify(ledger,never()).write(any());
    }
}
