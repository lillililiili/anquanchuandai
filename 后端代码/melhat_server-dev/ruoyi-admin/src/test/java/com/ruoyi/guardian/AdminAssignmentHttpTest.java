package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.http.MediaType;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Real Jackson HTTP bodies contain map items, unlike directly constructed Fastjson fixtures. */
class AdminAssignmentHttpTest {
    MockMvc http;
    AtomicReference<JSONObject> state;
    AdminLedgerStore ledger;
    AdminAssignmentService assignments;
    JSONObject actor;
    ObjectMapper json = new ObjectMapper();

    @BeforeEach void setup() {
        state = new AtomicReference<>(object("revision", 1, "nextId", 100,
                "sites", JSONArray.of(object("id", "site-1", "enabled", true), object("id", "site-2", "enabled", true)),
                "accounts", JSONArray.of(object("id", "operator", "name", "Operator", "siteId", "site-1", "enabled", true, "roleIds", JSONArray.of("operator-role"))),
                "roles", JSONArray.of(object("id", "operator-role", "enabled", true, "grants", JSONArray.of(object("siteIds", JSONArray.of("site-1"), "operations", JSONArray.of("assets:read", "assets:write", "people:read"))))),
                "people", JSONArray.of(object("id", "person-A", "siteId", "site-1", "name", "Person A", "code", "P-A", "enabled", true, "version", 1,
                        "equipmentEvidence", object("HELMET", "COMPLETE", "BELT", "COMPLETE", "WATCH", "COMPLETE"))),
                "devices", JSONArray.of(device("belt-A", "site-1", "BELT", "DIRECT_BELT"), device("belt-B", "site-2", "BELT", "DIRECT_BELT"), device("watch-A", "site-1", "WATCH", "DEMO_WATCH")),
                "assignments", new JSONArray(), "history", new JSONArray(), "audit", new JSONArray(), "idempotency", new JSONObject()));
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(state.get()));
        doAnswer(call -> { state.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        GuardianStore guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenReturn(object("devices", new JSONArray()));
        AdminQueryService queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
        assignments = spy(new AdminAssignmentService(ledger, guardian, queries));
        actor = find(state.get(), "accounts", "operator");
        AdminLedgerController controller = new AdminLedgerController(ledger, queries, mock(AdminDeviceService.class), assignments,
                mock(AdminMaintenanceService.class), mock(AdminMasterService.class), mock(AdminAccessService.class));
        http = MockMvcBuilders.standaloneSetup(controller).build();
    }

    JSONObject device(String id, String site, String type, String source) {
        return object("id", id, "siteId", site, "type", type, "source", source, "name", id, "code", id,
                "deviceNumber", "SN-" + id, "lifecycle", "STOCK", "relation", "UNASSIGNED", "version", 1);
    }
    Map<String, Object> map(Object... entries) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < entries.length; i += 2) result.put((String) entries[i], entries[i + 1]);
        return result;
    }
    Map<String, Object> command(String operation, Object items) {
        return map("siteId", "site-1", "operationId", operation, "personId", "person-A", "personVersion",
                find(state.get(), "people", "person-A").getIntValue("version"), "acknowledged", true, "items", items);
    }
    JSONObject send(String type, Map<String, Object> command, int code) throws Exception {
        String response = http.perform(post("/api/admin/v1/execute").requestAttr("wearable.actor", actor)
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsBytes(map("type", type, "input", command))))
                .andExpect(status().is(code)).andReturn().getResponse().getContentAsString();
        return JSONObject.parseObject(response);
    }

    @Test void normalHttpIssueAndReturnReplayOnceAndRetainHistory() throws Exception {
        AtomicBoolean mapSeen = new AtomicBoolean();
        doAnswer(call -> {
            Object raw = ((JSONObject) call.getArgument(2)).getJSONArray("items").get(0);
            mapSeen.set(raw instanceof Map && !(raw instanceof JSONObject));
            return call.callRealMethod();
        }).when(assignments).execute(eq("operator"), anyString(), any());
        Map<String, Object> issue = command("http-issue", Collections.singletonList(map("deviceId", "belt-A", "deviceVersion", 1)));
        JSONObject issued = send("assignments.issue", issue, 200);
        assertTrue(mapSeen.get(), "The controller must exercise Jackson's map item shape");
        int revision = state.get().getIntValue("revision");
        assertEquals(issued, send("assignments.issue", issue, 200));
        assertEquals(revision, state.get().getIntValue("revision"));
        JSONObject link = rows(state.get(), "assignments").getJSONObject(0);
        Map<String, Object> returning = command("http-return", Collections.singletonList(map("deviceId", "belt-A",
                "deviceVersion", find(state.get(), "devices", "belt-A").getIntValue("version"), "assignmentId", link.getString("id"),
                "assignmentVersion", link.getIntValue("version"), "condition", "GOOD")));
        JSONObject returned = send("assignments.return", returning, 200);
        assertEquals(returned, send("assignments.return", returning, 200));
        assertEquals(2, rows(state.get(), "history").size());
        assertFalse(rows(state.get(), "assignments").getJSONObject(0).getBooleanValue("active"));
    }

    @Test void hiddenWatchPolicyAcceptsNormalHttpItemsButRejectsHiddenWatch() throws Exception {
        WearableBusinessPolicy policy = mock(WearableBusinessPolicy.class);
        when(policy.config()).thenReturn(object("simulatedWatchVisible", false));
        ReflectionTestUtils.setField(assignments, "businessPolicy", policy);
        send("assignments.issue", command("hidden-watch", Collections.singletonList(map("deviceId", "watch-A", "deviceVersion", 1))), 409);
        send("assignments.issue", command("ordinary-belt", Collections.singletonList(map("deviceId", "belt-A", "deviceVersion", 1))), 200);
    }

    @Test void malformedHttpItemsFailClosedWithoutWriting() throws Exception {
        for (Object item : Arrays.asList(null, 7, "{\"deviceId\":\"belt-A\",\"deviceVersion\":1}", Collections.emptyList())) {
            JSONObject error = send("assignments.issue", command("bad-item", Collections.singletonList(item)), 400);
            assertEquals("INVALID_ITEMS", error.getString("errorCode"));
        }
        verify(ledger, never()).write(any());
    }

    @Test void foreignDeviceAndRevokedReplayStillFailCurrentScopeChecks() throws Exception {
        send("assignments.issue", command("foreign-device", Collections.singletonList(map("deviceId", "belt-B", "deviceVersion", 1))), 404);
        Map<String, Object> issue = command("revoked-replay", Collections.singletonList(map("deviceId", "belt-A", "deviceVersion", 1)));
        send("assignments.issue", issue, 200);
        int revision = state.get().getIntValue("revision");
        find(state.get(), "roles", "operator-role").put("enabled", false);
        send("assignments.issue", issue, 403);
        assertEquals(revision, state.get().getIntValue("revision"));
    }
}
