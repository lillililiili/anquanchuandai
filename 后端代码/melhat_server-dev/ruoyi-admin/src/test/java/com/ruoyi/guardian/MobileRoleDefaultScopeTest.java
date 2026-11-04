package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class MobileRoleDefaultScopeTest {
    JSONObject productionState() {
        return object("sites", JSONArray.of(object("id", "site-1", "enabled", true), object("id", "site-2", "enabled", true)),
                "roles", new JSONArray(), "accounts", JSONArray.of(object("id", "worker", "enabled", true, "roleIds", JSONArray.of("mobile-user"))));
    }

    GuardianAccess.Context context(JSONObject state) {
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(state));
        return new GuardianAccess(ledger, mock(AdminQueryService.class)).context(object("id", "worker"));
    }

    @Test void productionMigrationNeverGrantsEveryExistingStationToNewOrdinaryRole() {
        JSONObject state = productionState();
        find(state,"accounts","worker").put("siteId","site-1");
        assertTrue(migrate(state));
        JSONObject role = find(state, "roles", "mobile-user");
        assertNotNull(role);
        assertTrue(role.getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds").isEmpty());
        GuardianAccess.Context context = context(state);
        for (String site : new String[]{"site-1", "site-2"}) {
            assertFalse(context.site(site));
            assertFalse(context.can("self:read", site, null));
            assertFalse(context.can("sos:create", site, null));
        }
        assertTrue(context.identity().getJSONArray("sites").isEmpty());
    }

    @Test void existingRoleScopesAndLaterExplicitRevocationsAreNeverRewritten() {
        JSONObject state = productionState();
        find(state,"accounts","worker").put("siteId","site-2");
        JSONObject configured = object("id", "mobile-user", "builtin", true, "enabled", true, "version", 7,
                "grants", JSONArray.of(object("operations", JSONArray.of("self:read", "sos:create"), "siteIds", JSONArray.of("site-2"))));
        rows(state, "roles").add(configured);
        JSONObject before = copy(configured);
        migrate(state);
        assertEquals(before, find(state, "roles", "mobile-user"));
        assertFalse(context(state).site("site-1")); assertTrue(context(state).site("site-2"));
        configured.getJSONArray("grants").getJSONObject(0).put("siteIds", new JSONArray());
        rows(state, "sites").add(object("id", "site-3", "portalStation", "S3", "enabled", true));
        migrate(state);
        assertTrue(configured.getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds").isEmpty());
        assertTrue(context(state).identity().getJSONArray("sites").isEmpty());
    }

    @Test void demoSeedExplicitlyGrantsOnlyItsHomeStationWithoutWideningOnMigration() throws Exception {
        JSONObject state = JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(), StandardCharsets.UTF_8));
        JSONObject role = find(state, "roles", "mobile-user");
        assertNotNull(role, "Demo authorization must be explicit in the fixture, not inferred by production migration");
        JSONObject before = copy(role);
        rows(state, "accounts").add(object("id", "worker", "siteId", "site-1", "enabled", true, "roleIds", JSONArray.of("mobile-user")));
        migrate(state);
        assertEquals(before, find(state, "roles", "mobile-user"));
        assertEquals(JSONArray.of("site-1"), role.getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds"));
        assertTrue(context(state).can("self:read", "site-1", null));
        assertFalse(context(state).site("site-2"));
        rows(state, "sites").add(object("id", "site-3", "portalStation", "S3", "enabled", true));
        migrate(state);
        assertFalse(context(state).site("site-3"));
    }

    JSONObject sharedMobileState() {
        JSONObject state=productionState();
        rows(state,"roles").add(object("id","mobile-user","enabled",true,"grants",JSONArray.of(
                object("operations",JSONArray.of("self:read","sos:create"),"siteIds",JSONArray.of("site-1","site-2")))));
        return state;
    }

    @Test void sharedOrdinaryRoleGrantRemainsAnIntersectionWithEachAccountsHome() {
        JSONObject state=sharedMobileState();
        JSONObject worker=find(state,"accounts","worker");
        worker.put("siteId","site-1");
        GuardianAccess.Context local=context(state);
        assertTrue(local.site("site-1")); assertTrue(local.can("sos:create","site-1",null));
        assertFalse(local.site("site-2")); assertFalse(local.can("self:read","site-2",null));
        worker.put("siteId","site-2");
        assertTrue(context(state).site("site-2")); assertTrue(context(state).can("self:read","site-2",null));
        assertFalse(context(state).site("site-1"));
        find(state,"roles","mobile-user").getJSONArray("grants").getJSONObject(0).put("siteIds",new JSONArray());
        assertFalse(context(state).site("site-2")); assertFalse(context(state).can("self:read","site-2",null));
    }

    @Test void additionalManagementRoleRetainsOnlyItsExplicitCrossSiteOperations() {
        JSONObject state=sharedMobileState();
        JSONObject worker=find(state,"accounts","worker");
        worker.put("siteId","site-1");worker.getJSONArray("roleIds").add("duty");
        rows(state,"roles").add(object("id","duty","enabled",true,"grants",JSONArray.of(
                object("operations",JSONArray.of("events:read","events:claim"),"siteIds",JSONArray.of("site-2")))));
        GuardianAccess.Context manager=context(state);
        assertTrue(manager.site("site-2")); assertTrue(manager.can("events:claim","site-2",null));
        assertFalse(manager.can("self:read","site-2",null),"A management grant cannot widen the separate ordinary role");
        find(state,"roles","duty").put("enabled",false);
        assertFalse(context(state).site("site-2")); assertFalse(context(state).can("events:claim","site-2",null));
    }

    @Test void legacyLinkedPersonCanSupplyHomeButConflictingOrUnknownIdentityCannot() {
        JSONObject state=sharedMobileState();
        JSONObject worker=find(state,"accounts","worker");
        assertFalse(context(state).site("site-1")); assertFalse(context(state).can("self:read","site-2",null));
        worker.put("personId","person-1");
        JSONObject person=object("id","person-1","portalId","P1","siteId","site-1","enabled",true);
        rows(state,"people").add(person);
        assertTrue(context(state).site("site-1")); assertTrue(context(state).can("self:read","site-1",null));
        assertFalse(context(state).site("site-2"));
        worker.put("siteId","site-2");
        for (String site : new String[]{"site-1","site-2"}) {
            assertFalse(context(state).site(site)); assertFalse(context(state).can("self:read",site,null));
        }
        worker.remove("siteId");person.put("enabled",false);
        assertFalse(context(state).site("site-1")); assertFalse(context(state).can("self:read","site-1",null));
    }
}
