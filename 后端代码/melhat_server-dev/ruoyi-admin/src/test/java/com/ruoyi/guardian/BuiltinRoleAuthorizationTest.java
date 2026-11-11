package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class BuiltinRoleAuthorizationTest {
    AtomicReference<JSONObject> saved;
    AdminAccessService access;

    @BeforeEach void setup() {
        saved = new AtomicReference<>(object("revision", 1, "nextId", 100,
            "sites", JSONArray.of(object("id", "site-1", "enabled", true)),
            "accounts", JSONArray.of(
                object("id", "demo-system", "name", "系统管理员", "enabled", true, "siteId", "site-1", "roleIds", new JSONArray()),
                object("id", "demo-duty", "name", "值守员", "enabled", true, "siteId", "site-1", "roleIds", JSONArray.of("duty"))),
            "roles", JSONArray.of(object("id", "duty", "name", "平台值守员", "enabled", true, "builtin", true, "version", 2,
                "grants", JSONArray.of(object("operations", JSONArray.of("assets:read"), "siteIds", JSONArray.of("site-1")))))));
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        doAnswer(call -> { saved.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        access = new AdminAccessService(ledger);
    }

    JSONObject update() {
        return object("operationId", "builtin-role-edit-001", "siteId", "site-1", "id", "duty", "expectedVersion", 2,
            "data", object("name", "平台值守员", "operations", JSONArray.of("assets:read", "assets:write"), "siteIds", JSONArray.of("site-1")));
    }

    @Test void builtinDutyRoleAcceptsPreviewAndConfirmedUpdateWithoutBypassingPreview() {
        JSONObject command = update();
        String before = saved.get().toJSONString();
        assertEquals("PREVIEW_EXPIRED", assertThrows(AdminQueryService.QueryFailed.class,
            () -> access.execute("demo-system", "roles.update", command)).errorCode);
        assertEquals(before, saved.get().toJSONString());
        Map<String, Object> preview = access.query("demo-system", "authorizationPreview",
            object("siteId", "site-1", "type", "roles.update", "command", command));
        assertEquals(Boolean.TRUE, preview.get("required"));
        assertEquals(before, saved.get().toJSONString());
        command.put("previewId", preview.get("previewId"));
        JSONObject result = access.execute("demo-system", "roles.update", command);
        assertTrue(result.getJSONObject("data").getBooleanValue("builtin"));
        assertTrue(find(saved.get(), "roles", "duty").getJSONArray("grants").getJSONObject(0).getJSONArray("operations").contains("assets:write"));
        assertEquals(3, find(saved.get(), "roles", "duty").getIntValue("version"));
        assertEquals(result, access.execute("demo-system", "roles.update", command));
        assertEquals(1, rows(saved.get(), "audit").size());
    }

    @Test void grantingAllOperationsToAnOrdinaryAccountDoesNotPermitRoleMaintenance() {
        find(saved.get(), "roles", "duty").getJSONArray("grants").getJSONObject(0).put("operations", JSONArray.of("*"));
        String before = saved.get().toJSONString();
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.query("demo-duty", "authorizationPreview",
            object("siteId", "site-1", "type", "roles.update", "command", update()))).code);
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
            () -> access.execute("demo-duty", "roles.update", update())).code);
        assertEquals(before, saved.get().toJSONString());
    }

    @Test void systemAccountRemainsProtectedFromEditsStatusAndDeletion() {
        for (String action : new String[]{"update", "status", "delete"}) {
            JSONObject command = object("operationId", "protect-system-" + action, "siteId", "site-1", "id", "demo-system",
                "expectedVersion", 0, "enabled", false, "data", object("name", "changed"));
            assertEquals("BUILTIN_PROTECTED", assertThrows(AdminQueryService.QueryFailed.class,
                () -> access.execute("demo-system", "accounts." + action, command)).errorCode);
        }
        assertTrue(find(saved.get(), "accounts", "demo-system").getBooleanValue("enabled"));
    }

    @Test void disabledSystemAccountCannotPreviewOrApplyARoleEdit() {
        find(saved.get(), "accounts", "demo-system").put("enabled", false);
        assertEquals(401, assertThrows(AdminQueryService.QueryFailed.class, () -> access.query("demo-system", "authorizationPreview",
            object("siteId", "site-1", "type", "roles.update", "command", update()))).code);
        assertEquals(401, assertThrows(AdminQueryService.QueryFailed.class,
            () -> access.execute("demo-system", "roles.update", update())).code);
    }
}
