package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class RoleLifecycleTest {
    AtomicReference<JSONObject> saved;
    AdminAccessService access;
    AdminQueryService queries;
    MockMvc http;
    JSONObject actor;
    int operation;

    @BeforeEach void setup() {
        actor = object("id", "demo-system", "name", "管理员", "enabled", true, "roleIds", new JSONArray());
        saved = new AtomicReference<>(object("revision", 1, "nextId", 100,
                "sites", JSONArray.of(object("id", "site-1", "name", "一厂", "enabled", true)),
                "accounts", JSONArray.of(actor), "roles", new JSONArray()));
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        access = new AdminAccessService(ledger);
        queries = new AdminQueryService(ledger, mock(GuardianStore.class), mock(ObjectProvider.class));
        http = MockMvcBuilders.standaloneSetup(new AdminLedgerController(ledger, queries, mock(AdminDeviceService.class),
                mock(AdminAssignmentService.class), mock(AdminMaintenanceService.class), mock(AdminMasterService.class), access)).build();
    }

    JSONObject send(String path, JSONObject body, int code) throws Exception {
        String response = http.perform(post(path).requestAttr("wearable.actor", actor).contentType(MediaType.APPLICATION_JSON)
                        .content(new ObjectMapper().writeValueAsBytes(body))).andExpect(status().is(code)).andReturn().getResponse().getContentAsString();
        return JSONObject.parseObject(response);
    }

    JSONObject execute(String type, JSONObject command, int code) throws Exception {
        return send("/api/admin/v1/execute", object("type", type, "input", command), code);
    }

    JSONObject roleData() {
        return object("name", "现场查看角色", "operations", JSONArray.of("assets:read"), "siteIds", JSONArray.of("site-1"),
                "createdAt", "1900-01-01T00:00:00Z", "updatedAt", "1900-01-01T00:00:00Z");
    }

    JSONObject command(JSONObject role) {
        return object("operationId", "role-lifecycle-" + ++operation, "siteId", "site-1", "id", role.getString("id"), "expectedVersion", role.getIntValue("version"));
    }

    JSONObject createRole() throws Exception {
        return execute("roles.create", object("operationId", "role-create-" + ++operation, "siteId", "site-1", "data", roleData()), 200).getJSONObject("data");
    }

    void preview(String type, JSONObject command) {
        Map<String, Object> preview = access.query("demo-system", "authorizationPreview", object("siteId", "site-1", "type", type, "command", command));
        command.put("previewId", preview.get("previewId"));
    }

    @Test void unreferencedRoleDeletesThroughHttpWithAuditAndIdempotentReplay() throws Exception {
        JSONObject role = createRole(), command = command(role);
        int auditCount = rows(saved.get(), "audit").size();
        String accounts = rows(saved.get(), "accounts").toJSONString();
        JSONObject deleted = execute("roles.delete", command, 200);
        assertTrue(deleted.getJSONObject("data").getBooleanValue("deleted"));
        assertNull(find(saved.get(), "roles", role.getString("id")));
        assertEquals(accounts, rows(saved.get(), "accounts").toJSONString());
        assertEquals(auditCount + 1, rows(saved.get(), "audit").size());
        JSONObject audit = rows(saved.get(), "audit").getJSONObject(auditCount);
        assertEquals("roles.delete", audit.getString("action"));assertEquals(role.getString("id"), audit.getString("objectId"));
        assertEquals(role.getString("id"), audit.getJSONObject("before").getString("id"));assertTrue(audit.getJSONObject("after").getBooleanValue("deleted"));
        assertEquals(deleted, execute("roles.delete", command, 200));
        assertEquals(auditCount + 1, rows(saved.get(), "audit").size());
        command.put("expectedVersion", 0);assertEquals("IDEMPOTENCY_CONFLICT", execute("roles.delete", command, 409).getString("errorCode"));
    }

    @Test void enabledAndDisabledAccountReferencesBothBlockDeletionAndAppearInImpacts() throws Exception {
        JSONObject role = createRole();
        rows(saved.get(), "accounts").add(object("id", "active-user", "name", "启用用户", "enabled", true, "roleIds", JSONArray.of(role.getString("id"))));
        rows(saved.get(), "accounts").add(object("id", "disabled-user", "name", "停用用户", "enabled", false, "roleIds", JSONArray.of(role.getString("id"))));
        JSONObject input = object("siteId", "site-1", "entity", "roles", "id", role.getString("id"), "all", true);
        JSONObject impacts = send("/api/admin/v1/query", object("kind", "impacts", "input", input), 200).getJSONObject("data");
        assertEquals(2, impacts.getJSONArray("rows").size());
        String baseline = saved.get().toJSONString();
        assertEquals("REFERENCED", execute("roles.delete", command(role), 409).getString("errorCode"));
        assertEquals(baseline, saved.get().toJSONString());
        rows(find(saved.get(), "accounts", "active-user"), "roleIds").clear();
        assertEquals("REFERENCED", execute("roles.delete", command(role), 409).getString("errorCode"));
        input.put("all", false);
        assertTrue(send("/api/admin/v1/query", object("kind", "impacts", "input", input), 200).getJSONObject("data").getJSONArray("rows").isEmpty());
    }

    @Test void roleDeletionProtectsBuiltinsChecksVersionAndRequiresSystemIdentityIncludingReplay() throws Exception {
        JSONObject role = createRole();
        JSONObject stale = command(role);stale.put("expectedVersion", 0);
        assertEquals("VERSION_CONFLICT", execute("roles.delete", stale, 409).getString("errorCode"));
        find(saved.get(), "roles", role.getString("id")).put("builtin", true);
        assertEquals("BUILTIN_PROTECTED", execute("roles.delete", command(role), 403).getString("errorCode"));
        find(saved.get(), "roles", role.getString("id")).put("builtin", false);
        actor = object("id", "ordinary-admin", "enabled", true, "roleIds", new JSONArray());rows(saved.get(), "accounts").add(actor);
        assertEquals("PERMISSION_DENIED", execute("roles.delete", command(role), 403).getString("errorCode"));
        actor = find(saved.get(), "accounts", "demo-system");JSONObject deletion = command(role);
        execute("roles.delete", deletion, 200);
        find(saved.get(), "accounts", "demo-system").put("enabled", false);
        execute("roles.delete", deletion, 401);
    }

    @Test void roleDatesUseServerTimePreserveCreationAndLeaveLegacyCreationUnknown() throws Exception {
        Instant before = Instant.now();JSONObject created = createRole();Instant after = Instant.now();
        Instant createdAt = Instant.parse(created.getString("createdAt"));
        assertFalse(createdAt.isBefore(before));assertFalse(createdAt.isAfter(after));
        assertEquals(created.getString("createdAt"), created.getString("updatedAt"));
        find(saved.get(), "roles", created.getString("id")).put("updatedAt", "2000-01-01T00:00:00Z");
        JSONObject update = command(created);update.put("data", roleData());
        JSONObject edited = execute("roles.update", update, 200).getJSONObject("data");
        assertEquals(created.getString("createdAt"), edited.getString("createdAt"));
        assertFalse(Instant.parse(edited.getString("updatedAt")).isBefore(before));
        JSONObject disable = command(edited);disable.put("enabled", false);preview("roles.status", disable);
        JSONObject disabled = execute("roles.status", disable, 200).getJSONObject("data");
        assertEquals(created.getString("createdAt"), disabled.getString("createdAt"));
        assertFalse(Instant.parse(disabled.getString("updatedAt")).isBefore(Instant.parse(edited.getString("updatedAt"))));
        JSONObject legacy = find(saved.get(), "roles", created.getString("id"));legacy.remove("createdAt");legacy.remove("updatedAt");
        JSONObject legacyUpdate = command(legacy);legacyUpdate.put("data", roleData());
        JSONObject savedLegacy = execute("roles.update", legacyUpdate, 200).getJSONObject("data");
        assertFalse(savedLegacy.containsKey("createdAt"));assertNotNull(savedLegacy.getString("updatedAt"));
        JSONObject enable = command(savedLegacy);enable.put("enabled", true);preview("roles.status", enable);
        JSONObject enabled = execute("roles.status", enable, 200).getJSONObject("data");
        assertFalse(enabled.containsKey("createdAt"));assertNotNull(enabled.getString("updatedAt"));
    }
}
