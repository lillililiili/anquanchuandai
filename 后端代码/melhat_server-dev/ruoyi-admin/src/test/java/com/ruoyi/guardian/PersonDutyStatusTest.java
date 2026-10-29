package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PersonDutyStatusTest {
    AtomicReference<JSONObject> saved, projection;
    AdminMasterService masters;
    AdminQueryService queries;
    GuardianStore guardian;
    JSONObject actor;
    MockMvc http;
    int operation;
    boolean failPublish;

    @BeforeEach void setup() {
        actor = object("id", "demo-system", "name", "值班管理员", "enabled", true, "roleIds", new JSONArray());
        saved = new AtomicReference<>(object("revision", 1, "nextId", 100,
                "accounts", JSONArray.of(actor), "roles", new JSONArray(),
                "sites", JSONArray.of(object("id", "site-1", "code", "S1", "name", "测试厂区", "enabled", true, "version", 1),
                        object("id", "site-2", "code", "S2", "name", "其他厂区", "enabled", true, "version", 1)),
                "people", JSONArray.of(person("person", true), person("disabled-person", false)),
                "devices", JSONArray.of(object("id", "watch", "code", "WATCH-1", "name", "手表", "portalDeviceId", "WATCH-1", "siteId", "site-1", "type", "WATCH", "source", "LOCAL", "lifecycle", "IN_USE", "relation", "ASSIGNED", "version", 1)),
                "assignments", JSONArray.of(object("id", "assignment-watch", "siteId", "site-1", "personId", "person", "deviceId", "watch", "active", true, "startedAt", "2026-10-01T00:00:00Z", "version", 1))));
        migrate(saved.get());
        projection = new AtomicReference<>(new JSONObject());
        GuardianMasterProjection.apply(projection.get(), saved.get());
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(call -> copy(projection.get()));
        doAnswer(call -> {
            JSONObject draft = copy(projection.get());
            ((GuardianStore.Edit) call.getArgument(0)).apply(draft);
            if (failPublish) throw new IllegalArgumentException("投影保存失败");
            projection.set(draft); return null;
        }).when(guardian).update(any());
        queries = new AdminQueryService(ledger, guardian, null);
        masters = new AdminMasterService(ledger, guardian, queries);
        http = MockMvcBuilders.standaloneSetup(new AdminLedgerController(ledger, queries, mock(AdminDeviceService.class),
                mock(AdminAssignmentService.class), mock(AdminMaintenanceService.class), masters, mock(AdminAccessService.class))).build();
    }

    JSONObject person(String id, boolean enabled) {
        return object("id", id, "portalId", "P-" + id, "code", id, "name", id, "siteId", "site-1", "enabled", enabled, "version", 1);
    }
    JSONObject command(String status) {
        return object("id", "person", "siteId", "site-1", "expectedVersion", find(saved.get(), "people", "person").getIntValue("version"),
                "operationId", "duty-" + ++operation, "dutyStatus", status);
    }
    JSONObject run(JSONObject input) { return masters.execute(actor.getString("id"), "people.dutyStatus", input); }
    JSONObject query(String kind, JSONObject extra) {
        JSONObject input = object("siteId", "site-1", "entity", "people", "pageSize", 100);
        input.putAll(extra);
        return new JSONObject(queries.query(actor.getString("id"), kind, input));
    }
    JSONObject send(JSONObject input) throws Exception {
        String response = http.perform(post("/api/admin/v1/execute").requestAttr("wearable.actor", actor).contentType(MediaType.APPLICATION_JSON)
                .content(object("type", "people.dutyStatus", "input", input).toJSONString()))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return JSONObject.parseObject(response);
    }

    @Test void manualChangesReachThePortalWithoutDisablingPersonnelOrReturningTheirEquipment() throws Exception {
        JSONArray assignments = JSONArray.parseArray(rows(saved.get(), "assignments").toJSONString());
        JSONArray devices = JSONArray.parseArray(rows(saved.get(), "devices").toJSONString());
        JSONArray bindings = JSONArray.parseArray(rows(projection.get(), "bindings").toJSONString());
        JSONObject input = command("OFF_DUTY"), response = send(input);
        JSONObject row = response.getJSONObject("data");
        assertEquals("OFF_DUTY", row.getString("dutyStatus"));assertTrue(row.getBooleanValue("enabled"));
        assertEquals("MANUAL", row.getString("dutyStatusSource"));assertEquals("值班管理员", row.getString("dutyStatusUpdatedBy"));
        assertNotNull(Instant.parse(row.getString("dutyStatusUpdatedAt")));
        JSONObject portal = find(projection.get(), "people", "P-person");
        assertTrue(portal.getBooleanValue("active"));assertEquals("OFF_DUTY", portal.getString("dutyStatus"));
        assertEquals(row.getString("dutyStatusUpdatedAt"), portal.getString("dutyStatusUpdatedAt"));
        assertEquals("MANUAL", portal.getString("dutyStatusSource"));assertEquals("值班管理员", portal.getString("dutyStatusUpdatedBy"));
        assertEquals(assignments, rows(saved.get(), "assignments"));assertEquals(devices, rows(saved.get(), "devices"));assertEquals(bindings, rows(projection.get(), "bindings"));
        JSONObject audit = rows(saved.get(), "audit").getJSONObject(0);
        assertEquals("people.dutyStatus", audit.getString("action"));assertEquals("UNKNOWN", audit.getJSONObject("before").getString("dutyStatus"));
        assertEquals("OFF_DUTY", audit.getJSONObject("after").getString("dutyStatus"));
        assertEquals(response, send(input));assertEquals(1, rows(saved.get(), "audit").size());
        input.put("dutyStatus", "ON_DUTY");
        assertEquals("IDEMPOTENCY_CONFLICT", assertThrows(AdminQueryService.QueryFailed.class, () -> run(input)).errorCode);
        run(command("ON_DUTY"));
        assertEquals("ON_DUTY", find(projection.get(), "people", "P-person").getString("dutyStatus"));
        assertEquals(bindings, rows(projection.get(), "bindings"));assertEquals(2, rows(saved.get(), "audit").size());
    }

    @Test void missingStatusesStayUnknownAndTheNewFilterDoesNotDependOnArchiveEnabledState() {
        String before = saved.get().toJSONString();
        for (String kind : Arrays.asList("person", "record")) assertEquals("UNKNOWN", query(kind, object("id", "person")).getString("dutyStatus"));
        assertEquals(2, query("master", object("dutyStatus", "UNKNOWN")).getIntValue("total"));
        assertEquals(0, query("master", object("dutyStatus", "ON_DUTY")).getIntValue("total"));
        assertEquals(before, saved.get().toJSONString());
        run(command("ON_DUTY"));
        assertEquals(1, query("master", object("dutyStatus", "ON_DUTY", "status", "enabled")).getIntValue("total"));
        assertEquals(1, query("master", object("dutyStatus", "UNKNOWN", "status", "disabled")).getIntValue("total"));
        assertEquals(0, query("master", object("dutyStatus", "OFF_DUTY")).getIntValue("total"));
        for (Object value : Arrays.asList("enabled", "invalid", 1, new JSONObject()))
            assertEquals("INVALID_FILTER", assertThrows(AdminQueryService.QueryFailed.class, () -> query("master", object("dutyStatus", value))).errorCode);
        JSONObject invalidLegacy = find(saved.get(), "people", "disabled-person");invalidLegacy.put("dutyStatus", "old-value");
        assertEquals("UNKNOWN", query("person", object("id", "disabled-person")).getString("dutyStatus"));
    }

    @Test void onlyDedicatedManualCommandsCanChangeDutyStatusAndTheirMetadata() {
        JSONObject input = object("siteId", "site-1", "operationId", "create-person", "data", object("name", "新人员", "code", "NEW",
                "dutyStatus", "ON_DUTY", "dutyStatusSource", "FORGED"));
        JSONObject created = masters.execute(actor.getString("id"), "people.create", input).getJSONObject("data");
        assertEquals("UNKNOWN", created.getString("dutyStatus"));assertFalse(created.containsKey("dutyStatusSource"));
        JSONObject assigned = run(command("OFF_DUTY")).getJSONObject("data");
        input = object("siteId", "site-1", "id", "person", "operationId", "edit-person", "expectedVersion", assigned.getIntValue("version"),
                "data", object("name", "重命名", "code", "person", "dutyStatus", "ON_DUTY", "dutyStatusUpdatedAt", "forged"));
        JSONObject edited = masters.execute(actor.getString("id"), "people.update", input).getJSONObject("data");
        for (String key : Arrays.asList("dutyStatus", "dutyStatusUpdatedAt", "dutyStatusUpdatedBy", "dutyStatusSource")) assertEquals(assigned.get(key), edited.get(key));
        assertEquals("重命名", edited.getString("name"));
    }

    @Test void invalidCommandsNeverWriteOrChangeBindings() {
        for (Object value : Arrays.asList("UNKNOWN", "enabled", "", 1, true, new JSONObject())) {
            JSONObject input = command("ON_DUTY");input.put("dutyStatus", value);String before = saved.get().toJSONString();
            assertEquals("VALIDATION_ERROR", assertThrows(AdminQueryService.QueryFailed.class, () -> run(input)).errorCode);
            assertEquals(before, saved.get().toJSONString());
        }
        for (String extra : Arrays.asList("enabled", "dutyStatusUpdatedAt", "dutyStatusUpdatedBy", "dutyStatusSource", "data")) {
            JSONObject input = command("ON_DUTY");input.put(extra, "forged");
            assertEquals("VALIDATION_ERROR", assertThrows(AdminQueryService.QueryFailed.class, () -> run(input)).errorCode);
        }
        assertFalse(masters.handles("sites.dutyStatus"));assertFalse(masters.handles("organizations.dutyStatus"));
        assertTrue(rows(saved.get(), "audit").isEmpty());
    }

    @Test void currentPermissionsSiteAndVersionAreRequiredIncludingOnReplay() {
        JSONObject stale = command("ON_DUTY");stale.put("expectedVersion", 0);
        assertEquals("VERSION_CONFLICT", assertThrows(AdminQueryService.QueryFailed.class, () -> run(stale)).errorCode);
        JSONObject foreign = command("ON_DUTY");foreign.put("siteId", "site-2");
        assertEquals("OBJECT_NOT_FOUND", assertThrows(AdminQueryService.QueryFailed.class, () -> run(foreign)).errorCode);
        actor = object("id", "writer", "name", "人员管理员", "enabled", true, "roleIds", JSONArray.of("writer-role"));
        rows(saved.get(), "accounts").add(actor);
        JSONObject grant = object("siteIds", JSONArray.of("site-1"), "operations", JSONArray.of("people:read"));
        rows(saved.get(), "roles").add(object("id", "writer-role", "enabled", true, "grants", JSONArray.of(grant)));
        assertEquals("PERMISSION_DENIED", assertThrows(AdminQueryService.QueryFailed.class, () -> run(command("ON_DUTY"))).errorCode);
        grant.put("operations", JSONArray.of("people:write"));
        assertEquals("PERMISSION_DENIED", assertThrows(AdminQueryService.QueryFailed.class, () -> run(command("ON_DUTY"))).errorCode);
        grant.put("operations", JSONArray.of("people:read", "people:write"));
        JSONObject input = command("ON_DUTY");run(input);
        find(saved.get(), "roles", "writer-role").getJSONArray("grants").getJSONObject(0).getJSONArray("operations").remove("people:write");
        assertEquals("PERMISSION_DENIED", assertThrows(AdminQueryService.QueryFailed.class, () -> run(input)).errorCode);
    }

    @Test void failedPublishLeavesStatusAuditAndPortalUnchanged() {
        String before = saved.get().toJSONString(), portal = projection.get().toJSONString();failPublish = true;
        assertEquals("PORTAL_REJECTED", assertThrows(AdminQueryService.QueryFailed.class, () -> run(command("OFF_DUTY"))).errorCode);
        assertEquals(before, saved.get().toJSONString());assertEquals(portal, projection.get().toJSONString());
    }

    @Test void dutyStatusAndAuditSurviveRealLedgerReloadWithoutASchemaChange() {
        DriverManagerDataSource source = new DriverManagerDataSource();
        source.setDriverClassName("org.h2.Driver");source.setUrl("jdbc:h2:mem:duty-" + UUID.randomUUID() + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE");source.setUsername("sa");
        JdbcTemplate jdbc = new JdbcTemplate(source);
        AdminLedgerStore ledger = new AdminLedgerStore(jdbc);ledger.read();ledger.write(saved.get());
        AdminQueryService persistentQueries = new AdminQueryService(ledger, guardian, null);
        AdminMasterService persistent = new AdminMasterService(ledger, guardian, persistentQueries);
        persistent.execute(actor.getString("id"), "people.dutyStatus", command("OFF_DUTY"));
        JSONObject restarted = new AdminLedgerStore(jdbc).read(), row = find(restarted, "people", "person");
        assertEquals("OFF_DUTY", row.getString("dutyStatus"));assertTrue(row.getBooleanValue("enabled"));
        assertEquals("值班管理员", row.getString("dutyStatusUpdatedBy"));assertEquals("MANUAL", row.getString("dutyStatusSource"));
        assertTrue(find(restarted, "assignments", "assignment-watch").getBooleanValue("active"));
        assertEquals("people.dutyStatus", rows(restarted, "audit").getJSONObject(0).getString("action"));
        JSONObject portal = new JSONObject();GuardianMasterProjection.apply(portal, restarted);
        assertEquals("OFF_DUTY", find(portal, "people", "P-person").getString("dutyStatus"));
    }
}
