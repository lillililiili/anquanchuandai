package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import java.util.concurrent.atomic.AtomicReference;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Retrying a completed command must not outlive the caller's current scope. */
class AdminReplayScopeTest {
    AtomicReference<JSONObject> state;
    AdminLedgerStore ledger;
    AdminAccessService accounts;
    AdminMaintenanceService maintenance;

    @BeforeEach void setup() {
        state = new AtomicReference<>(object("revision", 1, "nextId", 100,
                "sites", JSONArray.of(object("id", "A", "enabled", true), object("id", "B", "enabled", true)),
                "accounts", JSONArray.of(object("id", "manager", "name", "Manager", "enabled", true,
                        "roleIds", JSONArray.of("manager-role"))),
                "roles", JSONArray.of(object("id", "manager-role", "enabled", true,
                        "grants", JSONArray.of(object("siteIds", JSONArray.of("A"),
                                "operations", JSONArray.of("accounts:write", "assets:read", "assets:write"))))),
                "devices", JSONArray.of(object("id", "device-A", "siteId", "A", "version", 2, "lifecycle", "DISABLED")),
                "idempotency", new JSONObject()));
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(state.get()));
        doAnswer(call -> { state.set(copy(call.getArgument(0))); return null; }).when(ledger).write(any());
        accounts = new AdminAccessService(ledger);
        AdminQueryService queries = new AdminQueryService(ledger, mock(GuardianStore.class), mock(ObjectProvider.class));
        maintenance = new AdminMaintenanceService(ledger, queries, mock(AdminAssignmentService.class));
    }

    JSONObject grant() { return find(state.get(), "roles", "manager-role").getJSONArray("grants").getJSONObject(0); }
    JSONObject createCommand(String site) {
        return object("siteId", site, "operationId", "create-user-" + site,
                "data", object("name", "New user", "loginName", "new-user-" + site,
                        "password", "FixtureOnly!2026", "bindings", new JSONArray()));
    }

    @Test void authorizedReplayDoesNotRepeatTheMutationButScopeRevocationDeniesIt() {
        JSONObject command = createCommand("A");
        JSONObject first = accounts.execute("manager", "accounts.create", command);
        int revision = state.get().getIntValue("revision");
        assertEquals(first, accounts.execute("manager", "accounts.create", command));
        assertEquals(revision, state.get().getIntValue("revision"));
        grant().put("siteIds", JSONArray.of("B"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> accounts.execute("manager", "accounts.create", command)).code);
        assertEquals(revision, state.get().getIntValue("revision"));
    }

    @Test void replayUsesCurrentTargetAuthorityNotCapturedAccountRoles() {
        JSONObject command = createCommand("A");
        JSONObject first = accounts.execute("manager", "accounts.create", command);
        JSONObject target = find(state.get(), "accounts", first.getJSONObject("data").getString("id"));
        target.put("roleIds", JSONArray.of("upper-administrator"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> accounts.execute("manager", "accounts.create", command)).code);
    }

    @Test void upperManagerCanReplayGrantedSecondSiteButNotAfterGrantDisabled() {
        JSONObject command = createCommand("B");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> accounts.execute("manager", "accounts.create", command)).code);
        grant().getJSONArray("siteIds").add("B");
        JSONObject first = accounts.execute("manager", "accounts.create", command);
        assertEquals(first, accounts.execute("manager", "accounts.create", command));
        find(state.get(), "roles", "manager-role").put("enabled", false);
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> accounts.execute("manager", "accounts.create", command)).code);
    }

    JSONObject maintenanceReplay() {
        JSONObject input = object("siteId", "A", "deviceId", "device-A", "operationId", "disable-A");
        JSONObject result = object("code", 200, "data", object("id", "device-A", "siteId", "A"));
        state.get().getJSONObject("idempotency").put("manager\ndevices.disable\ndisable-A",
                object("fingerprint", input.toJSONString(), "result", result));
        return input;
    }

    @Test void maintenanceReplayRequiresCurrentWritePermission() {
        JSONObject input = maintenanceReplay();
        assertEquals(200, maintenance.execute("manager", "devices.disable", input).getIntValue("code"));
        grant().put("operations", JSONArray.of("assets:read"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> maintenance.execute("manager", "devices.disable", input)).code);
        verify(ledger, never()).write(any());
    }

    @Test void maintenanceReplayCannotReadAnObjectMovedOutsideOriginalSite() {
        JSONObject input = maintenanceReplay();
        find(state.get(), "devices", "device-A").put("siteId", "B");
        assertEquals(404, assertThrows(AdminQueryService.QueryFailed.class,
                () -> maintenance.execute("manager", "devices.disable", input)).code);
        verify(ledger, never()).write(any());
    }
}
