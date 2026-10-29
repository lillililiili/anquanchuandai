package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.util.concurrent.atomic.AtomicReference;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PersonDeletionTest {
    AtomicReference<JSONObject> saved, projection;
    AdminMasterService masters;
    AdminQueryService queries;
    JSONObject actor;
    MockMvc http;
    boolean failPublish;
    int operation;
    @BeforeEach void setup() {
        actor = object("id", "demo-system", "name", "管理员", "enabled", true, "roleIds", new JSONArray());
        saved = new AtomicReference<>(object("revision", 1, "nextId", 100, "accounts", JSONArray.of(actor), "roles", new JSONArray(),
                "sites", JSONArray.of(object("id", "site-1", "name", "测试厂区", "enabled", true, "version", 1)),
                "people", JSONArray.of(object("id", "person", "portalId", "P-DELETE", "name", "待删除人员", "code", "P001", "siteId", "site-1", "enabled", true, "version", 1),
                        object("id", "other", "portalId", "P-KEEP", "name", "保留人员", "code", "P002", "siteId", "site-1", "enabled", true, "version", 1))));
        projection = new AtomicReference<>(object("people", JSONArray.of(object("id", "P-DELETE", "ledgerId", "person", "name", "待删除人员"), object("id", "P-KEEP", "ledgerId", "other", "name", "保留人员")),
                "events", JSONArray.of(object("id", "past-event", "personId", "P-DELETE")), "works", JSONArray.of(object("id", "ended-work", "status", "已结束", "members", JSONArray.of("P-DELETE"))),
                "bindings", JSONArray.of(object("id", "returned-binding", "personId", "P-DELETE", "end", "2020-01-01T00:00:00Z"))));
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        GuardianStore guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(call -> copy(projection.get()));when(guardian.isOperational(any(JSONObject.class))).thenReturn(true);
        doAnswer(call -> { JSONObject draft = copy(projection.get()); ((GuardianStore.Edit)call.getArgument(0)).apply(draft); if (failPublish) throw new IllegalArgumentException("投影校验失败"); projection.set(draft); return null; }).when(guardian).update(any());
        queries = new AdminQueryService(ledger, guardian, null);masters = new AdminMasterService(ledger, guardian, queries);
        http = MockMvcBuilders.standaloneSetup(new AdminLedgerController(ledger, queries, mock(AdminDeviceService.class), mock(AdminAssignmentService.class), mock(AdminMaintenanceService.class), masters, mock(AdminAccessService.class))).build();
    }
    JSONObject command() { return object("siteId", "site-1", "id", "person", "expectedVersion", 1, "operationId", "person-delete-" + ++operation); }
    JSONObject remove(JSONObject input) { return masters.execute(actor.getString("id"), "people.delete", input).getJSONObject("data"); }
    JSONObject impacts() { return JSONObject.parseObject(JSONObject.toJSONString(queries.query(actor.getString("id"), "impacts", object("siteId", "site-1", "entity", "people", "id", "person", "all", true)))); }
    JSONObject send(JSONObject input, int expected) throws Exception {
        String response = http.perform(post("/api/admin/v1/execute").requestAttr("wearable.actor", actor).contentType(MediaType.APPLICATION_JSON).content(object("type", "people.delete", "input", input).toJSONString()))
                .andExpect(status().is(expected)).andReturn().getResponse().getContentAsString();
        return JSONObject.parseObject(response);
    }
    @Test void httpDeletionPreservesHistoryRemovesOnlyTargetProjectionAndReplaysOnce() throws Exception {
        rows(saved.get(), "assignments").add(object("id", "returned", "personId", "person", "active", false));
        rows(saved.get(), "history").add(object("id", "old-history", "personId", "person", "personName", "待删除人员"));
        rows(saved.get(), "audit").add(object("id", "old-audit", "objectId", "person"));
        JSONObject before = copy(saved.get()), beforeProjection = copy(projection.get()), input = command();
        JSONObject result = send(input, 200);assertTrue(result.getJSONObject("data").getBooleanValue("deleted"));
        assertNull(find(saved.get(), "people", "person"));assertNotNull(find(saved.get(), "people", "other"));
        assertNull(find(projection.get(), "people", "P-DELETE"));assertNotNull(find(projection.get(), "people", "P-KEEP"));
        for (String key : new String[]{"works", "events", "bindings"}) assertEquals(beforeProjection.getJSONArray(key), projection.get().getJSONArray(key));
        assertEquals(before.getJSONArray("history"), saved.get().getJSONArray("history"));assertEquals(before.getJSONArray("assignments"), saved.get().getJSONArray("assignments"));
        assertEquals(2, rows(saved.get(), "audit").size());assertEquals("people.delete", rows(saved.get(), "audit").getJSONObject(1).getString("action"));
        assertEquals(result, send(input, 200));assertEquals(2, rows(saved.get(), "audit").size());
        input.put("expectedVersion", 2);assertEquals("IDEMPOTENCY_CONFLICT", send(input, 409).getString("errorCode"));
    }
    @Test void everyLiveReferenceBlocksDeletionIncludingDisabledBindingsAndLegacyDeviceLinks() {
        String[] keys = {"assignments", "dutyShifts", "groups", "groups", "accounts", "devices"};
        JSONObject[] refs = {
                object("id", "active-assignment", "active", true, "personId", "person"),
                object("id", "historic-shift", "enabled", false, "endsAt", "2000-01-01T00:00:00Z", "personIds", JSONArray.of("person")),
                object("id", "disabled-group", "enabled", false, "personIds", JSONArray.of("person")),
                object("id", "group-leader", "enabled", false, "personIds", new JSONArray(), "leaderId", "person"),
                object("id", "disabled-account", "enabled", false, "personId", "person"),
                object("id", "legacy-device", "lifecycle", "SCRAPPED", "personId", "person")};
        for (int i=0;i<keys.length;i++) {
            JSONArray records = rows(saved.get(), keys[i]);records.add(refs[i]);String baseline = saved.get().toJSONString();
            assertFalse(impacts().getJSONArray("rows").isEmpty(), keys[i]);
            assertEquals("REFERENCED", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(command())).errorCode, keys[i]);
            assertEquals(baseline, saved.get().toJSONString());records.remove(refs[i]);
        }
        rows(saved.get(), "accounts").add(object("id", "reverse-account", "enabled", false));find(saved.get(), "people", "person").put("accountId", "reverse-account");
        assertEquals(1, impacts().getJSONArray("rows").size());assertEquals("REFERENCED", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(command())).errorCode);
        find(saved.get(), "people", "person").put("accountId", "missing-account");assertTrue(remove(command()).getBooleanValue("deleted"));
    }
    @Test void openWorkBlocksDeletionAndIsReported() {
        rows(projection.get(), "works").add(object("id", "open-work", "name", "正在作业", "status", "作业中", "members", JSONArray.of("P-DELETE")));
        assertEquals(1, impacts().getJSONArray("rows").size());assertEquals("REFERENCED", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(command())).errorCode);
    }
    @Test void permissionsSiteVersionAndPermissionChangesOnReplayAreEnforced() {
        JSONObject stale = command();stale.put("expectedVersion", 0);assertEquals("VERSION_CONFLICT", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(stale)).errorCode);
        JSONObject foreign = command();foreign.put("siteId", "site-2");assertEquals("OBJECT_NOT_FOUND", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(foreign)).errorCode);
        actor = object("id", "writer", "enabled", true, "roleIds", JSONArray.of("writer-role"));rows(saved.get(), "accounts").add(actor);
        JSONObject grant = object("siteIds", JSONArray.of("site-1"), "operations", JSONArray.of("people:read"));
        rows(saved.get(), "roles").add(object("id", "writer-role", "enabled", true, "grants", JSONArray.of(grant)));
        assertEquals("PERMISSION_DENIED", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(command())).errorCode);
        grant.getJSONArray("operations").add("people:write");JSONObject input = command();remove(input);
        find(saved.get(), "roles", "writer-role").getJSONArray("grants").getJSONObject(0).getJSONArray("operations").remove("people:write");
        assertEquals("PERMISSION_DENIED", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(input)).errorCode);
    }
    @Test void failedProjectionPublishLeavesBothRecordsAndHistoryUntouched() {
        String before = saved.get().toJSONString(), beforeProjection = projection.get().toJSONString();failPublish = true;
        assertEquals("PORTAL_REJECTED", assertThrows(AdminQueryService.QueryFailed.class, () -> remove(command())).errorCode);
        assertEquals(before, saved.get().toJSONString());assertEquals(beforeProjection, projection.get().toJSONString());
    }
}
