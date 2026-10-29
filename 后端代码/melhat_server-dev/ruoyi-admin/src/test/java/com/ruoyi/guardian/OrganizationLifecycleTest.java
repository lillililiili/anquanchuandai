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

class OrganizationLifecycleTest {
    AtomicReference<JSONObject> saved;
    AdminMasterService masters;
    AdminQueryService queries;
    JSONObject actor;
    MockMvc http;
    int operation;

    @BeforeEach void setup() {
        actor = object("id", "demo-system", "name", "管理员", "enabled", true, "roleIds", new JSONArray());
        saved = new AtomicReference<>(object("revision", 1, "nextId", 100,
                "sites", JSONArray.of(object("id", "site-1", "name", "测试厂区", "enabled", true, "version", 1), object("id", "site-2", "name", "外厂", "enabled", true, "version", 1)),
                "accounts", JSONArray.of(actor), "roles", new JSONArray(),
                "organizations", JSONArray.of(org("legacy", "site-1", null, false), org("normal", "site-1", null, true), org("foreign", "site-2", null, false)),
                "people", new JSONArray()));
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        GuardianStore guardian = mock(GuardianStore.class);
        queries = new AdminQueryService(ledger, guardian, null);
        masters = new AdminMasterService(ledger, guardian, queries);
        http = MockMvcBuilders.standaloneSetup(new AdminLedgerController(ledger, queries, mock(AdminDeviceService.class),
                mock(AdminAssignmentService.class), mock(AdminMaintenanceService.class), masters, mock(AdminAccessService.class))).build();
    }
    JSONObject org(String id, String site, String parent, boolean enabled) { return object("id", id, "siteId", site, "code", id, "name", id, "parentId", parent, "enabled", enabled, "version", 1); }
    JSONObject command(JSONObject row) { return object("siteId", "site-1", "operationId", "organization-" + ++operation, "id", row == null ? null : row.getString("id"), "expectedVersion", row == null ? null : row.getIntValue("version")); }
    JSONObject run(String type, JSONObject input) { return masters.execute("demo-system", type, input).getJSONObject("data"); }
    JSONObject query(String kind, JSONObject input) { return JSONObject.parseObject(JSONObject.toJSONString(queries.query("demo-system", kind, input))); }
    JSONObject create(String entity, String code, String relation, String id) {
        JSONObject input = command(null);input.put("data", object("code", code, "name", code, relation, id, "enabled", false));
        if (id != null) input.put("relatedVersions", object(id, find(saved.get(), "organizations", id).getIntValue("version")));
        return run(entity + ".create", input);
    }

    @Test void organizationStatusCommandsAreUnavailableWithoutChangingTheLedger() throws Exception {
        String before = saved.get().toJSONString();
        assertFalse(masters.handles("organizations.status"));
        for (boolean enabled : new boolean[]{true, false}) {
            JSONObject input = command(find(saved.get(), "organizations", "legacy"));input.put("enabled", enabled);
            assertEquals("UNKNOWN_COMMAND", assertThrows(AdminQueryService.QueryFailed.class, () -> run("organizations.status", input)).errorCode);
            String body = http.perform(post("/api/admin/v1/execute").requestAttr("wearable.actor", actor).contentType(MediaType.APPLICATION_JSON)
                    .content(object("type", "organizations.status", "input", input).toJSONString())).andExpect(status().isBadRequest()).andReturn().getResponse().getContentAsString();
            assertEquals("UNKNOWN_COMMAND", JSONObject.parseObject(body).getString("errorCode"));
        }
        assertEquals(before, saved.get().toJSONString());
    }

    @Test void legacyDisabledOrganizationsRemainInOptionsAndIgnoreStatusFilters() {
        rows(saved.get(), "people").add(object("id", "disabled-person", "siteId", "site-1", "enabled", false));
        JSONObject options = query("options", object("siteId", "site-1"));
        assertEquals(2, options.getJSONArray("organizations").size());assertTrue(options.getJSONArray("people").isEmpty());
        for (String filter : new String[]{"enabled", "disabled", "obsolete"}) {
            JSONObject result = query("master", object("entity", "organizations", "siteId", "site-1", "status", filter, "pageSize", 100));
            assertEquals(2, result.getIntValue("total"));
        }
        assertEquals("legacy", query("record", object("entity", "organizations", "siteId", "site-1", "id", "legacy")).getString("id"));
    }

    @Test void legacyOrganizationCanHaveChildrenAndPersonnelWithoutAnEnabledField() {
        JSONObject child = create("organizations", "new-child", "parentId", "legacy");
        assertEquals("legacy", child.getString("parentId"));assertFalse(child.containsKey("enabled"));
        JSONObject person = create("people", "new-person", "organizationId", "legacy");assertTrue(person.getBooleanValue("enabled"));
        JSONObject input = command(person);input.put("enabled", false);person = run("people.status", input);assertFalse(person.getBooleanValue("enabled"));
        input = command(person);input.put("enabled", true);assertTrue(run("people.status", input).getBooleanValue("enabled"));
        JSONObject legacy = find(saved.get(), "organizations", "legacy");input = command(legacy);
        input.put("data", object("name", "改名", "code", "legacy", "enabled", true));
        assertFalse(run("organizations.update", input).containsKey("enabled"));
    }

    @Test void organizationReferencesStillEnforceSiteVersionHierarchyAndPermissions() {
        JSONObject input = command(null);input.put("data", object("name", "子组织", "code", "child", "parentId", "foreign"));
        assertEquals("VALIDATION_ERROR", assertThrows(AdminQueryService.QueryFailed.class, () -> run("organizations.create", input)).errorCode);
        input.getJSONObject("data").put("parentId", "legacy");input.put("relatedVersions", object("legacy", 0));
        assertEquals("VERSION_CONFLICT", assertThrows(AdminQueryService.QueryFailed.class, () -> run("organizations.create", input)).errorCode);
        JSONObject cycle = command(find(saved.get(), "organizations", "legacy"));cycle.put("data", object("name", "循环", "code", "legacy", "parentId", "legacy"));
        assertEquals("VALIDATION_ERROR", assertThrows(AdminQueryService.QueryFailed.class, () -> run("organizations.update", cycle)).errorCode);
        rows(saved.get(), "accounts").add(object("id", "reader", "enabled", true, "roleIds", new JSONArray()));
        assertEquals("PERMISSION_DENIED", assertThrows(AdminQueryService.QueryFailed.class, () -> masters.execute("reader", "organizations.create", input)).errorCode);
    }

    @Test void disabledAndStatuslessReferencesBlockDeletionAndAreReported() {
        JSONObject child = org("child", "site-1", "legacy", false);child.remove("enabled");rows(saved.get(), "organizations").add(child);
        rows(saved.get(), "people").add(object("id", "disabled-person", "name", "历史人员", "organizationId", "legacy", "siteId", "site-1", "enabled", false));
        JSONObject input = object("entity", "organizations", "siteId", "site-1", "id", "legacy");
        assertEquals(2, query("impacts", input).getJSONArray("rows").size());
        assertEquals("REFERENCED", assertThrows(AdminQueryService.QueryFailed.class, () -> run("organizations.delete", command(find(saved.get(), "organizations", "legacy")))).errorCode);
        run("organizations.delete", command(child));rows(saved.get(), "people").clear();
        assertTrue(run("organizations.delete", command(find(saved.get(), "organizations", "legacy"))).getBooleanValue("deleted"));
    }

    @Test void allOrganizationsProtectTheirSiteEvenWhenOldFlagsWereDisabled() {
        rows(saved.get(), "organizations").clear();rows(saved.get(), "organizations").add(org("legacy", "site-1", null, false));
        for (boolean removeFlag : new boolean[]{false, true}) {
            if (removeFlag) find(saved.get(), "organizations", "legacy").remove("enabled");
            assertEquals(1, query("impacts", object("entity", "sites", "siteId", "site-1", "id", "site-1")).getJSONArray("rows").size());
            JSONObject input = command(find(saved.get(), "sites", "site-1"));input.put("enabled", false);
            assertEquals("REFERENCED", assertThrows(AdminQueryService.QueryFailed.class, () -> run("sites.status", input)).errorCode);
        }
    }
}
