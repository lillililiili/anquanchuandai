package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Uses actual role resolution and service boundaries; never connects to runtime storage. */
class StationIsolationTest {
    JSONObject state;
    AdminLedgerStore ledger;
    AdminQueryService queries;
    GuardianAccess access;

    @BeforeEach void setup() {
        state = object("nextId", 100, "revision", 1,
                "sites", JSONArray.of(site("site-a", "A"), site("site-b", "B")),
                "accounts", JSONArray.of(account("local", "local-role"), account("regional", "regional-role"),
                        object("id", "demo-system", "enabled", true)),
                "roles", JSONArray.of(role("local-role", "site-a"), role("regional-role", "site-a", "site-b")),
                "people", JSONArray.of(person("person-a", "P-a", "site-a"), person("person-b", "P-b", "site-b")),
                "devices", JSONArray.of(device("device-a", "site-a"), device("device-b", "site-b")));
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(state));
        doAnswer(call -> { state = copy(call.getArgument(0)); return null; }).when(ledger).write(any());
        queries = new AdminQueryService(ledger, mock(GuardianStore.class), mock(ObjectProvider.class));
        access = new GuardianAccess(ledger, queries);
    }

    JSONObject site(String id, String station) { return object("id", id, "portalStation", station, "enabled", true); }
    JSONObject account(String id, String role) { return object("id", id, "name", id, "siteId", "site-a", "enabled", true, "roleIds", JSONArray.of(role)); }
    JSONObject role(String id, String... sites) {
        return object("id", id, "enabled", true, "grants", JSONArray.of(object("siteIds", JSONArray.of((Object[]) sites),
                "operations", JSONArray.of("overview:read", "people:read", "people:write", "assets:read", "assets:write", "events:read", "organization:read", "organization:write"))));
    }
    JSONObject person(String id, String portalId, String site) { return object("id", id, "portalId", portalId, "siteId", site, "name", id, "enabled", true, "version", 1); }
    JSONObject device(String id, String site) { return object("id", id, "siteId", site, "portalDeviceId", id, "name", id, "code", id, "type", "BELT", "version", 1, "lifecycle", "STOCK"); }
    JSONObject actor(String id) { return object("id", id); }
    List<String> ids(JSONObject snapshot, String key) { return rows(snapshot, key).stream().map(row -> ((JSONObject) row).getString("id")).collect(Collectors.toList()); }
    void deny(int status, org.junit.jupiter.api.function.Executable action) { assertEquals(status, assertThrows(AdminQueryService.QueryFailed.class, action).code); }

    @Test void actualQueryScopesRejectForeignSiteAndTamperedObjectButAllowGrantedRegion() {
        JSONObject input = object("entity", "people", "siteId", "site-b");
        deny(403, () -> queries.query("local", "master", input));
        Map<String, Object> result = queries.query("regional", "master", input);
        assertEquals(1, ((List<?>) result.get("rows")).size());
        input.put("siteId", "site-a"); input.put("id", "person-b");
        deny(404, () -> queries.query("local", "person", input));
        assertTrue(access.context(actor("regional")).can("assets:write", "site-b", null));
        assertFalse(access.context(actor("local")).can("assets:write", "site-b", null));
    }

    @Test void devicesAreWritableOnlyInAuthorizedSitesIncludingActualCreation() {
        AdminDeviceService service = new AdminDeviceService(ledger, mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(service, "queries", queries);
        JSONObject input = object("siteId", "site-b", "operationId", "site-write-1", "data", object("type", "BELT", "code", "new-belt", "name", "New belt"));
        deny(403, () -> service.execute("local", "devices.create", input));
        verify(ledger, never()).write(any());
        JSONObject created = service.execute("regional", "devices.create", input).getJSONObject("data");
        assertEquals("site-b", created.getString("siteId"));
        JSONObject tampered = object("siteId", "site-a", "id", created.getString("id"), "expectedVersion", 1,
                "operationId", "tampered-id", "data", object("name", "Changed"));
        deny(404, () -> service.execute("local", "devices.update", tampered));
    }

    @Test void freshContextsHonorRoleRevocationAndDisabledAccounts() {
        assertTrue(access.context(actor("regional")).site("site-b"));
        find(state, "roles", "regional-role").getJSONArray("grants").getJSONObject(0).put("siteIds", JSONArray.of("site-a"));
        assertFalse(access.context(actor("regional")).site("site-b"));
        deny(403, () -> queries.query("regional", "master", object("entity", "people", "siteId", "site-b")));
        find(state, "roles", "local-role").put("enabled", false);
        assertFalse(access.context(actor("local")).can("people:read", "site-a", null));
        find(state, "accounts", "regional").put("enabled", false);
        deny(401, () -> access.context(actor("regional")));
    }

    @Test void disabledOrUnknownSitesNeverBecomeVisibleThroughAStaleRoleGrant() {
        find(state, "sites", "site-b").put("enabled", false);
        assertFalse(access.context(actor("regional")).site("site-b"));
        assertFalse(access.context(actor("regional")).can("assets:write", "site-b", null));
        deny(403, () -> queries.query("regional", "master", object("entity", "people", "siteId", "site-b")));
        find(state, "roles", "regional-role").getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds").add("missing-site");
        assertFalse(access.context(actor("regional")).site("missing-site"));
        deny(403, () -> queries.query("regional", "master", object("entity", "people", "siteId", "missing-site")));
        assertFalse(queries.allows(state, find(state, "accounts", "regional"), "assets:write", "missing-site", null));
        AdminDeviceService service = new AdminDeviceService(ledger, mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(service, "queries", queries);
        deny(403, () -> service.execute("regional", "devices.create", object("siteId", "missing-site", "operationId", "stale-grant",
                "data", object("type", "BELT", "code", "orphan-belt", "name", "Orphan belt"))));
        verify(ledger, never()).write(any());
    }

    @Test void selfOnlyAccountWithoutLinkedPersonCannotTreatNullIdsAsOwnership() {
        find(state, "roles", "local-role").getJSONArray("grants").getJSONObject(0).put("operations", JSONArray.of("self:read"));
        find(state, "people", "person-a").remove("portalId");
        GuardianAccess.Context context = access.context(actor("local"));
        assertNull(context.personId());
        assertFalse(context.person(find(state, "people", "person-a")));
    }

    JSONObject history() {
        JSONObject source = object("people", JSONArray.of(object("id", "P-a"), object("id", "P-b")),
                "events", JSONArray.of(object("id", "event-a", "personId", "P-a", "siteId", "site-a")));
        for (String collection : new String[]{"locations", "fenceRecords", "media"}) {
            rows(source, collection).add(object("id", "a", "personId", "P-a", "siteId", "site-a"));
            rows(source, collection).add(object("id", "b", "personId", "P-a", "siteId", "site-b", "blobId", "foreign-blob"));
            rows(source, collection).add(object("id", "legacy-a", "personId", "P-a", "station", "A"));
            rows(source, collection).add(object("id", "unknown", "personId", "P-a"));
            rows(source, collection).add(object("id", "conflict", "personId", "P-a", "siteId", "site-a", "station", "B"));
        }
        rows(source, "media").add(object("id", "event-photo", "eventId", "event-a", "personId", "P-a", "blobId", "event-blob"));
        return source;
    }

    @Test void historicalRecordsUseCapturedSiteEvenWhenPersonIsCurrentlyVisible() {
        JSONObject source = history();
        JSONObject local = access.context(actor("local")).snapshot(source);
        for (String key : new String[]{"locations", "fenceRecords", "media"}) {
            assertTrue(ids(local, key).contains("a")); assertTrue(ids(local, key).contains("legacy-a"));
            assertFalse(ids(local, key).contains("b")); assertFalse(ids(local, key).contains("unknown"));
            assertFalse(ids(local, key).contains("conflict"));
        }
        assertTrue(ids(local, "media").contains("event-photo"));
        JSONObject regional = access.context(actor("regional")).snapshot(source);
        for (String key : new String[]{"locations", "fenceRecords", "media"}) assertTrue(ids(regional, key).contains("b"));
        assertEquals(5, rows(source, "locations").size(), "Filtering cannot rewrite stored history");
        assertTrue(ids(access.context(actor("demo-system")).snapshot(source), "locations").contains("unknown"));
    }

    @Test void mediaDownloadCannotBypassHistoricalSiteFilterAndEventUploadsRemainAccessible() {
        GuardianStore store = mock(GuardianStore.class); when(store.snapshot()).thenReturn(history());
        GuardianFiles files = mock(GuardianFiles.class);
        GuardianEvents events = new GuardianEvents(store, access, files);
        deny(404, () -> events.file(actor("local"), "foreign-blob"));
        verify(files, never()).read("foreign-blob");
        events.file(actor("regional"), "foreign-blob"); verify(files).read("foreign-blob");
        events.file(actor("local"), "event-blob"); verify(files).read("event-blob");
    }

    JSONObject equipmentHistory() {
        return object("people", JSONArray.of(object("id", "P-a")),
                "devices", JSONArray.of(object("id", "device-a", "station", "A")));
    }

    JSONObject assignment(String id, String site) {
        return object("id", id, "siteId", site, "personId", "person-a", "deviceId", "device-a",
                "active", true, "version", 1, "startedAt", "2026-11-01T00:00:00Z");
    }

    @Test void vitalsAndBindingsRetainCapturedScopeAfterParticipantsMove() {
        rows(state, "assignments").add(assignment("assignment-a", "site-a"));
        rows(state, "assignments").add(assignment("assignment-b", "site-b"));
        rows(state, "assignments").add(object("id", "assignment-other", "siteId", "site-a", "personId", "person-b", "deviceId", "device-b"));
        JSONObject source=equipmentHistory();
        for (String key : new String[]{"vitals", "bindings"}) {
            rows(source,key).add(object("id", "a", "personId", "P-a", "deviceId", "device-a", "siteId", "site-a"));
            rows(source,key).add(object("id", "b", "personId", "P-a", "deviceId", "device-a", "siteId", "site-b"));
            rows(source,key).add(object("id", "unknown", "personId", "P-a", "deviceId", "device-a"));
            rows(source,key).add(object("id", "conflict", "personId", "P-a", "deviceId", "device-a", "siteId", "site-a", "station", "B"));
            rows(source,key).add(object("id", "trace-a", "personId", "P-a", "deviceId", "device-a", "assignmentId", "assignment-a"));
            rows(source,key).add(object("id", "trace-b", "personId", "P-a", "deviceId", "device-a", "assignmentId", "assignment-b"));
            rows(source,key).add(object("id", "wrong-assignment", "personId", "P-a", "deviceId", "device-a", "assignmentId", "assignment-other"));
        }
        JSONObject local=access.context(actor("local")).snapshot(source);
        JSONObject regional=access.context(actor("regional")).snapshot(source);
        for (String key : new String[]{"vitals", "bindings"}) {
            assertEquals(java.util.Arrays.asList("a", "trace-a"),ids(local,key));
            assertEquals(java.util.Arrays.asList("a", "b", "trace-a", "trace-b"),ids(regional,key));
            assertEquals(7,rows(source,key).size(),"Read filtering must preserve durable history");
        }
    }

    @Test void ordinaryWearerKeepsTrustedLegacyAssignmentButNotUnknownOrForeignBinding() {
        find(state,"accounts","local").put("personId","person-a");
        find(state,"roles","local-role").getJSONArray("grants").getJSONObject(0).put("operations",JSONArray.of("self:read"));
        rows(state,"assignments").add(assignment("assignment-a","site-a"));
        JSONObject source=equipmentHistory();
        JSONObject binding=object("id","legacy","personId","P-a","deviceId","device-a","assignmentId","assignment-a","end",null);
        rows(source,"bindings").add(binding);
        JSONObject visible=access.context(actor("local")).snapshot(source);
        assertEquals(java.util.Collections.singletonList("device-a"),ids(visible,"devices"));
        assertEquals(java.util.Collections.singletonList("legacy"),ids(visible,"bindings"));
        binding.remove("assignmentId");
        assertTrue(rows(access.context(actor("local")).snapshot(source),"devices").isEmpty());
        binding.put("assignmentId","assignment-a");
        find(state,"assignments","assignment-a").put("siteId","site-b");
        assertTrue(rows(access.context(actor("local")).snapshot(source),"devices").isEmpty());
        binding.put("siteId","site-b");
        assertTrue(rows(access.context(actor("local")).snapshot(source),"bindings").isEmpty());
    }

    @Test void projectedBindingCapturesAssignmentSiteAndNeverRewritesItsHistory() {
        find(state,"devices","device-a").put("lifecycle","IN_USE");
        JSONObject original=assignment("assignment-a","site-a");
        rows(state,"assignments").add(original);
        JSONObject snapshot=new JSONObject();
        GuardianMasterProjection.apply(snapshot,state);
        JSONObject binding=find(snapshot,"bindings","BIND-assignment-a-1");
        assertNotNull(binding); assertEquals("site-a",binding.getString("siteId"));
        find(state,"people","person-a").put("siteId","site-b");
        find(state,"devices","device-a").put("siteId","site-b");
        GuardianMasterProjection.apply(snapshot,state);
        assertEquals("site-a",binding.getString("siteId"),"Moving current participants cannot rewrite captured ownership");
        original.put("active",false);
        rows(state,"assignments").add(assignment("assignment-b","site-b"));
        GuardianMasterProjection.apply(snapshot,state);
        assertNotNull(binding.get("end")); assertEquals("site-a",binding.getString("siteId"));
        assertEquals("site-b",find(snapshot,"bindings","BIND-assignment-b-1").getString("siteId"));
    }

    @Test void simulatedVitalsCannotWaiveExplicitHistoryScopeOrExposeUnattributedRealSamples() {
        JSONObject source=equipmentHistory();
        rows(source,"bindings").add(object("id","current","personId","P-a","deviceId","device-a","siteId","site-a","end",null));
        JSONObject simulated=object("id","simulation","personId","P-a","deviceId","device-a","demo",true,"dataOrigin","GUARDIAN_SEED","source","DEMO_WATCH");
        rows(source,"vitals").add(simulated);
        rows(source,"vitals").add(object("id","unknown-real","personId","P-a","deviceId","device-a","source","DEVICE"));
        assertEquals(java.util.Collections.singletonList("simulation"),ids(access.context(actor("local")).snapshot(source),"vitals"));
        simulated.put("siteId","site-b");
        assertTrue(rows(access.context(actor("local")).snapshot(source),"vitals").isEmpty());
        ReflectionTestUtils.setField(access,"demoMode",true);
        assertTrue(rows(access.context(actor("local")).snapshot(source),"vitals").isEmpty(),"Demo mode cannot bypass an explicit foreign site or unknown real history");
        assertEquals(java.util.Collections.singletonList("simulation"),ids(access.context(actor("regional")).snapshot(source),"vitals"));
    }

    void remember(String actor, String type, JSONObject input, JSONObject output) {
        JSONObject memory = state.getJSONObject("idempotency");
        if (memory == null) { memory = new JSONObject(); state.put("idempotency", memory); }
        memory.put(actor + "\n" + type + "\n" + input.getString("operationId"),
                object("fingerprint", input.toJSONString(), "result", object("code", 200, "data", output)));
    }

    @Test void assignmentReplayRechecksRevokedSiteAndEveryDeviceOwnership() {
        AdminAssignmentService service = new AdminAssignmentService(ledger, mock(GuardianStore.class), queries);
        JSONObject input = object("siteId", "site-a", "personId", "person-a", "personVersion", 1, "operationId", "issued-once",
                "items", JSONArray.of(object("deviceId", "device-a")));
        remember("local", "assignments.issue", input, object("issued", true));
        assertEquals(200, service.execute("local", "assignments.issue", input).getIntValue("code"));
        find(state, "roles", "local-role").put("enabled", false);
        deny(403, () -> service.execute("local", "assignments.issue", input));
        find(state, "roles", "local-role").put("enabled", true);
        find(state, "devices", "device-a").put("siteId", "site-b");
        deny(404, () -> service.execute("local", "assignments.issue", input));
        verify(ledger, never()).write(any());
    }

    @Test void masterReplayRechecksCurrentGrantAndCapturedObjectSite() {
        AdminMasterService service = new AdminMasterService(ledger, mock(GuardianStore.class), queries);
        JSONObject input = object("siteId", "site-a", "id", "person-a", "operationId", "person-updated",
                "expectedVersion", 1, "data", object("name", "Updated"));
        remember("local", "people.update", input, copy(find(state, "people", "person-a")));
        assertEquals(200, service.execute("local", "people.update", input).getIntValue("code"));
        find(state, "roles", "local-role").put("enabled", false);
        deny(403, () -> service.execute("local", "people.update", input));
        find(state, "roles", "local-role").put("enabled", true);
        find(state, "people", "person-a").put("siteId", "site-b");
        deny(404, () -> service.execute("local", "people.update", input));
        verify(ledger, never()).write(any());
    }

    @Test void deviceReplayCannotReturnAnObjectThatNoLongerBelongsToTheRequestedSite() {
        AdminDeviceService service = new AdminDeviceService(ledger, mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(service, "queries", queries);
        JSONObject input = object("siteId", "site-a", "id", "device-a", "operationId", "device-updated",
                "expectedVersion", 1, "data", object("name", "Updated"));
        remember("local", "devices.update", input, copy(find(state, "devices", "device-a")));
        assertEquals(200, service.execute("local", "devices.update", input).getIntValue("code"));
        find(state, "devices", "device-a").put("siteId", "site-b");
        deny(404, () -> service.execute("local", "devices.update", input));
        verify(ledger, never()).write(any());
    }
}
