package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AccountRoleInheritanceTest {
    AtomicReference<JSONObject> saved;
    AdminAccessService access;
    AdminQueryService queries;
    GuardianAccess guardian;
    int operation;

    @BeforeEach void setup() {
        saved = new AtomicReference<>(object("revision", 1, "nextId", 100,
                "sites", JSONArray.of(object("id", "site-1", "name", "一厂", "enabled", true), object("id", "site-2", "name", "二厂", "enabled", true)),
                "accounts", JSONArray.of(object("id", "demo-system", "name", "管理员", "enabled", true, "roleIds", new JSONArray())),
                "roles", new JSONArray()));
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        access = new AdminAccessService(ledger);
        queries = new AdminQueryService(ledger, mock(GuardianStore.class), mock(ObjectProvider.class));
        guardian = new GuardianAccess(ledger, queries);
    }

    JSONObject execute(String actor, String type, JSONObject command) {
        command.put("siteId", "site-1");
        command.put("operationId", "inheritance-" + ++operation);
        return access.execute(actor, type, command).getJSONObject("data");
    }

    JSONObject createRole(String... sites) {
        return execute("demo-system", "roles.create", object("data", object("name", "共享范围角色",
                "operations", JSONArray.of("assets:read", "events:read", "audit:read"), "siteIds", JSONArray.of((Object[]) sites))));
    }

    JSONObject createAccount(String name, String roleId) {
        return execute("demo-system", "accounts.create", object("data", object("name", name, "loginName", name,
                "password", "RoleInheritance@2026", "bindings", JSONArray.of(object("roleId", roleId)))));
    }

    Map<String, Object> updateRole(JSONObject role, String... sites) {
        JSONObject command = object("siteId", "site-1", "operationId", "inheritance-" + ++operation,
                "id", role.getString("id"), "expectedVersion", find(saved.get(), "roles", role.getString("id")).getIntValue("version"),
                "data", object("name", role.getString("name"), "operations", JSONArray.of("assets:read", "events:read", "audit:read"), "siteIds", JSONArray.of((Object[]) sites)));
        Map<String, Object> preview = access.query("demo-system", "authorizationPreview", object("siteId", "site-1", "type", "roles.update", "command", command));
        command.put("previewId", preview.get("previewId"));
        access.execute("demo-system", "roles.update", command);
        return preview;
    }

    void assertSiteAccess(String accountId, String siteId, boolean allowed) {
        JSONObject account = find(saved.get(), "accounts", accountId);
        assertEquals(allowed, queries.allows(saved.get(), account, "assets:read", siteId, null));
        GuardianAccess.Context context = guardian.context(object("id", accountId));
        assertEquals(allowed, context.site(siteId));
        assertEquals(allowed, context.can("events:read", siteId, null));
        boolean identityHasSite = context.identity().getJSONArray("sites").stream().anyMatch(raw -> siteId.equals(((JSONObject) raw).getString("id")));
        assertEquals(allowed, identityHasSite);
        if (allowed) assertNotNull(access.query(accountId, "audit", object("siteId", siteId)));
        else assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.query(accountId, "audit", object("siteId", siteId))).code);
    }

    @Test void sharedRoleScopeChangesReachBothAccountsAndEveryPermissionReaderWithoutAccountWrites() {
        JSONObject role = createRole("site-1");
        JSONObject first = createAccount("first-user", role.getString("id"));
        JSONObject second = createAccount("second-user", role.getString("id"));
        assertFalse(first.containsKey("roleScopes"));assertFalse(second.containsKey("roleScopes"));
        find(saved.get(), "accounts", first.getString("id")).put("roleScopes", object(role.getString("id"), object("siteIds", JSONArray.of("site-1"))));
        String accountSnapshot = rows(saved.get(), "accounts").toJSONString();
        for (JSONObject user : new JSONObject[]{first, second}) {
            assertSiteAccess(user.getString("id"), "site-1", true);
            assertSiteAccess(user.getString("id"), "site-2", false);
        }
        Map<String, Object> expanded = updateRole(role, "site-1", "site-2");
        assertEquals(2, ((List<?>) expanded.get("accounts")).size());
        for (JSONObject user : new JSONObject[]{first, second}) assertSiteAccess(user.getString("id"), "site-2", true);
        Map<String, Object> reduced = updateRole(role, "site-2");
        for (Map<String, Object> change : (List<Map<String, Object>>) reduced.get("accounts")) {
            assertEquals(1, ((List<?>) change.get("lostSites")).size());
            assertFalse(((List<?>) change.get("removed")).isEmpty());
        }
        for (JSONObject user : new JSONObject[]{first, second}) {
            assertSiteAccess(user.getString("id"), "site-1", false);
            assertSiteAccess(user.getString("id"), "site-2", true);
        }
        assertEquals(accountSnapshot, rows(saved.get(), "accounts").toJSONString());
    }

    @Test void staleBindingScopeCannotHideADelegatedRolesFullScopeOrBypassTargetProtection() {
        rows(saved.get(), "roles").add(object("id", "viewer", "enabled", true, "version", 1,
                "grants", JSONArray.of(object("operations", JSONArray.of("assets:read"), "siteIds", JSONArray.of("site-1", "site-2")))));
        rows(saved.get(), "roles").add(object("id", "delegator", "enabled", true,
                "grants", JSONArray.of(object("operations", JSONArray.of("accounts:write", "access:read", "assets:read"), "siteIds", JSONArray.of("site-1")))));
        rows(saved.get(), "accounts").add(object("id", "limited-admin", "siteId", "site-1", "enabled", true, "roleIds", JSONArray.of("delegator")));
        JSONObject data = object("name", "scoped-user", "loginName", "scoped-user", "password", "RoleInheritance@2026",
                "bindings", JSONArray.of(object("roleId", "viewer", "siteIds", JSONArray.of("site-1"))));
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> execute("limited-admin", "accounts.create", object("data", data))).code);
        JSONObject target = execute("demo-system", "accounts.create", object("data", data));
        find(saved.get(), "accounts", target.getString("id")).put("roleScopes", object("viewer", object("siteIds", JSONArray.of("site-1"))));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> execute("limited-admin", "accounts.delete", object("id", target.getString("id"), "expectedVersion", target.getIntValue("version")))).code);
        find(saved.get(), "roles", "delegator").getJSONArray("grants").getJSONObject(0).put("siteIds", JSONArray.of("site-1", "site-2"));
        data.put("loginName", "covered-user");data.put("name", "covered-user");
        JSONObject allowed = execute("limited-admin", "accounts.create", object("data", data));
        assertEquals(JSONArray.of("viewer"), allowed.getJSONArray("roleIds"));assertFalse(allowed.containsKey("roleScopes"));
    }

    @Test void removingLegacyAccountScopeWithoutRebindingRequiresNoAuthorizationPreview() {
        JSONObject role = createRole("site-1", "site-2"), account = createAccount("legacy-user", role.getString("id"));
        find(saved.get(), "accounts", account.getString("id")).put("roleScopes", object(role.getString("id"), object("siteIds", new JSONArray())));
        JSONObject command = object("siteId", "site-1", "operationId", "legacy-scope-cleanup", "id", account.getString("id"), "expectedVersion", account.getIntValue("version"),
                "data", object("name", "legacy-user", "loginName", "legacy-user", "bindings", JSONArray.of(object("roleId", role.getString("id"), "siteIds", "ignored"))));
        Map<String, Object> preview = access.query("demo-system", "authorizationPreview", object("siteId", "site-1", "type", "accounts.update", "command", command));
        assertEquals(false, preview.get("required"));
        access.execute("demo-system", "accounts.update", command);
        assertFalse(find(saved.get(), "accounts", account.getString("id")).containsKey("roleScopes"));
        assertSiteAccess(account.getString("id"), "site-1", true);assertSiteAccess(account.getString("id"), "site-2", true);
    }
}
