package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Map;

import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminQueryAreaScopeTest {
    private JSONObject state;
    private JSONObject actor;
    private JSONObject grant;
    private AdminLedgerStore ledger;
    private GuardianStore guardian;
    private AdminQueryService queries;

    @BeforeEach void setup() {
        actor = object("id", "area-editor", "enabled", true, "roleIds", JSONArray.of("asset-role"),
                "roleScopes", object("asset-role", object("siteIds", JSONArray.of("site-1"), "areaIds", JSONArray.of("area-A"))));
        grant = object("operations", JSONArray.of("assets:read", "assets:write"), "siteIds", JSONArray.of("site-1"), "areaIds", "*");
        state = object("accounts", JSONArray.of(actor),
                "roles", JSONArray.of(object("id", "asset-role", "enabled", true, "grants", JSONArray.of(grant))),
                "sites", JSONArray.of(object("id", "site-1", "enabled", true)),
                "areas", JSONArray.of(object("id", "area-A", "siteId", "site-1", "enabled", true),
                        object("id", "area-B", "siteId", "site-1", "enabled", true)),
                "devices", JSONArray.of(device("A", "area-A"), device("B", "area-B"), device("UNASSIGNED", null)),
                "assignments", new JSONArray(), "people", new JSONArray(), "maintenanceOrders", new JSONArray());
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> JSONObject.parseObject(state.toJSONString()));
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenReturn(object("devices", new JSONArray()));
        queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
    }

    private JSONObject device(String suffix, String areaId) {
        return object("id", "asset-" + suffix, "siteId", "site-1", "areaId", areaId,
                "type", "HELMET", "source", "DIRECT_HELMET", "code", "CODE-" + suffix,
                "deviceNumber", "LOGIN-" + suffix, "portalDeviceId", "LOGIN-" + suffix, "sn", "SERIAL-" + suffix,
                "name", suffix, "modelId", "unknown-HELMET", "lifecycle", "STOCK", "relation", "UNASSIGNED", "version", 1);
    }

    @Test void legacyAreaScopeNowAllowsEveryDeviceInItsAuthorizedSite() {
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", "area-A"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", "area-B"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", null));
        assertFalse(queries.allows(state, actor, "events:read", "site-1", null));
        JSONObject input = object("siteId", "site-1", "source", "DIRECT_HELMET", "areaId", "area-A");
        List<JSONObject> rows = (List<JSONObject>) queries.query("area-editor", "devices", input).get("rows");
        assertEquals(3, rows.size(), "legacy area filters must not narrow site results");
        assertNotNull(queries.query("area-editor", "device", object("siteId", "site-1", "id", "asset-UNASSIGNED")));
        Map<String, Object> options = queries.query("area-editor", "deviceOptions", input);
        assertFalse(options.containsKey("areas"));
        assertFalse(options.containsKey("writableAreas"));
    }

    @Test void registrationNoLongerRequiresOrAssignsAnAdministrativeArea() {
        GuardianHatArchive archive = mock(GuardianHatArchive.class);
        AdminDeviceService service = new AdminDeviceService(ledger, archive);
        ReflectionTestUtils.setField(service, "queries", queries);
        JSONObject data = object("type", "HELMET", "source", "DIRECT_HELMET", "deviceNumber", "NEW-LOGIN",
                "code", "NEW-ASSET", "sn", "NEW-SERIAL", "name", "测试直连帽", "areaId", "retired-or-foreign-area");
        JSONObject input = object("siteId", "site-1", "operationId", "new-direct", "data", data);
        assertNull(service.execute("area-editor", "devices.create", input).getJSONObject("data").get("areaId"));
        verify(archive).ensureDirectUnassigned("NEW-LOGIN");
        input.put("siteId", "site-2");input.put("operationId", "foreign-direct");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> service.execute("area-editor", "devices.create", input)).code);
    }

    @Test void incompatibleLegacyAreaScopesDoNotRemoveSiteAccess() {
        grant.put("areaIds", JSONArray.of("area-B"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", null));
        state.put("areas", new JSONArray());
        assertEquals(3, ((List<?>) queries.query("area-editor", "devices", object("siteId", "site-1")).get("rows")).size());
        GuardianAccess.Context context = new GuardianAccess(ledger, queries).context(actor);
        assertTrue(context.can("assets:write", "site-1", null));
        assertFalse(context.can("assets:write", "site-2", null));
    }

    @Test void roleSitesOverrideLegacyAccountScopesAndRemainDynamic() {
        state.getJSONArray("sites").add(object("id", "site-2", "enabled", true));
        grant.put("siteIds", JSONArray.of("site-1", "site-2"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-2", null));
        assertNotNull(queries.query("area-editor", "devices", object("siteId", "site-2")));
        GuardianAccess.Context context = new GuardianAccess(ledger, queries).context(actor);
        assertTrue(context.can("assets:read", "site-2", null));
        assertTrue(context.site("site-2"));
        assertTrue(actor.containsKey("roleScopes"), "reads must not rewrite legacy records");
        assertTrue(queries.allows(state, actor, "assets:read", "site-2", null));
        grant.put("siteIds", JSONArray.of("site-1"));
        assertFalse(queries.allows(state, actor, "assets:read", "site-2", null));
    }
}
