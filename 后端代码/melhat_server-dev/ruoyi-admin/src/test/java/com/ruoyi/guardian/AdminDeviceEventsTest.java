package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;
import java.util.Map;

import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminDeviceEventsTest {
    JSONObject state, actor, grant, snapshot, belt;
    GuardianStore guardian;
    AdminQueryService queries;

    @BeforeEach void setup() {
        actor = object("id", "reader", "enabled", true, "roleIds", JSONArray.of("reader-role"));
        grant = object("operations", JSONArray.of("assets:read", "events:read"),
                "siteIds", JSONArray.of("site-1"), "areaIds", "*");
        belt = object("id", "belt-ledger", "deviceNumber", "belt-physical", "portalDeviceId", "belt-physical",
                "siteId", "site-1", "areaId", null, "type", "BELT", "source", "DIRECT_BELT", "lifecycle", "STOCK");
        state = object("accounts", JSONArray.of(actor),
                "roles", JSONArray.of(object("id", "reader-role", "enabled", true, "grants", JSONArray.of(grant))),
                "sites", JSONArray.of(object("id", "site-1", "enabled", true), object("id", "site-2", "enabled", true)),
                "areas", JSONArray.of(object("id", "area-A", "siteId", "site-1", "enabled", true),
                        object("id", "area-B", "siteId", "site-1", "enabled", true)),
                "devices", JSONArray.of(belt), "assignments", new JSONArray(), "people", new JSONArray());
        snapshot = object("events", new JSONArray());
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> JSON.parseObject(state.toJSONString()));
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(i -> JSON.parseObject(snapshot.toJSONString()));
        queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
    }

    JSONObject input() { return object("siteId", "site-1", "id", "belt-ledger", "pageNum", 1, "pageSize", 10); }
    JSONObject event(String id, String time) {
        return object("id", id, "deviceId", "belt-physical", "siteId", "site-1", "areaId", null,
                "protocol", "direct-belt", "source", "device", "personId", "", "rawAlarmType", "unmapped-6",
                "title", "安全带告警（unmapped-6）", "type", "设备通信", "status", "待认领",
                "date", "2026-10-26", "time", time, "createdAt", "2026-10-26T" + time + "Z",
                "latitude", "private-location", "snapshot", object("personName", "private-person"),
                "observations", JSONArray.of(object("situation", "private-note")));
    }
    void add(JSONObject event) { snapshot.getJSONArray("events").add(event); }
    Map<String, Object> read(JSONObject input) { return queries.query("reader", "deviceEvents", input); }
    @SuppressWarnings("unchecked") List<JSONObject> rows(Map<String, Object> result) { return (List<JSONObject>) result.get("rows"); }

    @Test void unassignedStockDeviceShowsOnlyItsActualBeltEventsAndMinimalFields() {
        add(event("first", "01:00:00"));
        JSONObject otherDevice = event("other-device", "02:00:00"); otherDevice.put("deviceId", "other"); add(otherDevice);
        JSONObject otherSite = event("other-site", "02:00:00"); otherSite.put("siteId", "site-2"); add(otherSite);
        JSONObject otherProtocol = event("helmet", "02:00:00"); otherProtocol.put("protocol", "direct-helmet"); add(otherProtocol);
        JSONObject manual = event("manual", "02:00:00"); manual.put("source", "manual_sos"); add(manual);
        Map<String, Object> result = read(input());
        assertEquals("AVAILABLE", result.get("availability")); assertEquals(1, result.get("total"));
        JSONObject row = rows(result).get(0);
        assertEquals("first", row.getString("sourceEventId"));
        assertEquals("unmapped-6", row.getString("alarmCode"));
        assertEquals("安全带告警（unmapped-6）", row.getString("alarmName"));
        assertFalse(JSON.toJSONString(result).contains("private-"));
        assertFalse(row.containsKey("personId")); assertFalse(row.containsKey("snapshot"));
        verify(guardian, times(1)).snapshot();
    }

    @Test void missingEventPermissionFailsBeforeBusinessSnapshot() {
        grant.put("operations", JSONArray.of("assets:read"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        verifyNoInteractions(guardian);
    }

    @Test void assetVisibilityAndRequestedSiteAreRequiredBeforeReadingEvents() {
        grant.put("operations", JSONArray.of("events:read"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        grant.put("operations", JSONArray.of("assets:read", "events:read"));
        JSONObject wrongSite = input(); wrongSite.put("siteId", "site-2");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(wrongSite)).code);
        JSONObject wrongId = input(); wrongId.put("id", "belt-physical");
        assertEquals(404, assertThrows(AdminQueryService.QueryFailed.class, () -> read(wrongId)).code);
        verifyNoInteractions(guardian);
    }

    @Test void legacyAreaScopeDoesNotNarrowAuthorizedSiteEvents() {
        grant.put("areaIds", JSONArray.of("area-A"));
        JSONObject allowed = event("allowed", "01:00:00"); allowed.put("areaId", "area-A"); add(allowed);
        JSONObject otherArea = event("other-area", "02:00:00"); otherArea.put("areaId", "area-B"); add(otherArea);
        add(event("unassigned-historical", "03:00:00"));
        JSONObject foreignSite = event("foreign-site", "04:00:00"); foreignSite.put("siteId", "site-2"); add(foreignSite);
        assertEquals(3, read(input()).get("total"));
        belt.put("areaId", "area-A");
        Map<String, Object> result = read(input());
        assertEquals(3, result.get("total"));
        assertEquals("unassigned-historical", rows(result).get(0).getString("id"));
        assertTrue(rows(result).stream().noneMatch(row -> "foreign-site".equals(row.getString("id"))));
        clearInvocations(guardian);
        JSONObject wrongSite = input(); wrongSite.put("siteId", "site-2");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(wrongSite)).code);
        verifyNoInteractions(guardian);
    }

    @Test void paginationIsNewestFirstBoundedAndCannotOverflow() {
        add(event("old", "01:00:00")); add(event("new", "03:00:00")); add(event("middle", "02:00:00"));
        JSONObject input = input(); input.put("pageSize", 1);
        assertEquals("new", rows(read(input)).get(0).getString("id"));
        input.put("pageNum", 2);
        Map<String, Object> second = read(input);
        assertEquals(3, second.get("total")); assertEquals("middle", rows(second).get(0).getString("id"));
        input.put("pageNum", Integer.MAX_VALUE); input.put("pageSize", 100);
        assertTrue(rows(read(input)).isEmpty());
        clearInvocations(guardian);
        input.put("pageNum", -1);
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input)).code);
        input.put("pageNum", 1); input.put("pageSize", 101);
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input)).code);
        verifyNoInteractions(guardian);
    }

    @Test void unavailableSourceIsNotReportedAsNoAlarms() {
        when(guardian.snapshot()).thenReturn(null);
        assertEquals(503, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
    }

    @Test void systemAdminRetainsExistingSiteWideAccessWithoutRoleExpansion() {
        actor.put("id", "demo-system"); actor.put("roleIds", new JSONArray());
        add(event("existing", "01:00:00"));
        assertEquals(1, queries.query("demo-system", "deviceEvents", input()).get("total"));
    }

    @Test void contradictoryDeviceRegistrationOrUnsupportedSourceCannotReadBeltEvents() {
        belt.put("portalDeviceId", "other-device");
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        belt.put("portalDeviceId", "belt-physical"); belt.put("source", "MOCK");
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        verifyNoInteractions(guardian);
    }

    void useHelmet() { belt.put("source", "DIRECT_HELMET"); belt.put("type", "HELMET"); }
    JSONObject helmetEvent(String id, String time, boolean legacy) {
        JSONObject row = event(id, time);
        row.put("title", "安全帽告警（77）"); row.put("rawAlarmType", "77");
        row.put("protocol", legacy ? null : "direct-helmet");
        row.put("sourceKey", "belt-physical:alarm:77:2026-10-26T" + time + "Z");
        return row;
    }

    @Test void helmetIncludesVerifiedLegacyAlarmsAndSosWithoutRewritingStoredProvenance() {
        useHelmet();
        JSONObject legacy = helmetEvent("legacy", "01:00:00", true); add(legacy);
        add(helmetEvent("journal", "03:00:00", false));
        JSONObject sos = helmetEvent("legacy-sos", "02:00:00", true);
        sos.put("type", "人员求助"); sos.put("title", "安全帽发起 SOS"); sos.remove("rawAlarmType");
        sos.put("sourceKey", "belt-physical:sos:2026-10-26T02:00:00Z"); add(sos);
        JSONObject input = input(); input.put("pageSize", 1);
        Map<String, Object> first = read(input);
        assertEquals(3, first.get("total")); assertEquals("journal", rows(first).get(0).getString("id"));
        input.put("pageNum", 2);
        JSONObject second = rows(read(input)).get(0);
        assertEquals("legacy-sos", second.getString("id")); assertEquals("direct-helmet", second.getString("protocol"));
        input.put("pageNum", 3);
        JSONObject third = rows(read(input)).get(0);
        assertEquals("legacy", third.getString("sourceEventId")); assertEquals("77", third.getString("alarmCode"));
        assertEquals("安全帽告警（77）", third.getString("alarmName")); assertEquals("direct-helmet", third.getString("protocol"));
        assertFalse(JSON.toJSONString(first).contains("private-"));
        assertFalse(third.containsKey("sourceKey")); assertFalse(third.containsKey("personId"));
        assertNull(legacy.get("protocol"), "compatibility must normalize only the read projection");
    }

    @Test void helmetLegacyCompatibilityRejectsManualSimulatedForeignAndUnprovenEvents() {
        useHelmet(); add(helmetEvent("valid", "01:00:00", true));
        JSONObject manual = helmetEvent("manual", "02:00:00", true); manual.put("source", "manual_sos"); add(manual);
        JSONObject demo = helmetEvent("demo", "02:00:00", true); demo.put("demo", true); add(demo);
        JSONObject modernDemo = helmetEvent("modern-demo", "02:00:00", false); modernDemo.put("demo", true); add(modernDemo);
        JSONObject otherProtocol = helmetEvent("other-protocol", "02:00:00", true); otherProtocol.put("protocol", "direct-belt"); add(otherProtocol);
        JSONObject absent = helmetEvent("no-evidence", "02:00:00", true); absent.remove("sourceKey"); add(absent);
        JSONObject wrongKey = helmetEvent("wrong-key", "02:00:00", true); wrongKey.put("sourceKey", "another-device:alarm:77:2026-10-26T02:00:00Z"); add(wrongKey);
        JSONObject wrongCode = helmetEvent("wrong-code", "02:00:00", true); wrongCode.put("rawAlarmType", "78"); add(wrongCode);
        JSONObject missingCode = helmetEvent("missing-code", "02:00:00", true); missingCode.remove("rawAlarmType"); add(missingCode);
        JSONObject wrongType = helmetEvent("wrong-type", "02:00:00", true); wrongType.put("type", "人员求助"); add(wrongType);
        JSONObject invalidTime = helmetEvent("invalid-time", "02:00:00", true); invalidTime.put("sourceKey", "belt-physical:alarm:77:not-a-timestamp"); add(invalidTime);
        JSONObject otherDevice = helmetEvent("other-device", "02:00:00", false); otherDevice.put("deviceId", "another-device"); add(otherDevice);
        JSONObject otherSite = helmetEvent("other-site", "02:00:00", true); otherSite.put("siteId", "site-2"); add(otherSite);
        Map<String, Object> result = read(input());
        assertEquals(1, result.get("total")); assertEquals("valid", rows(result).get(0).getString("id"));
    }

    @Test void legacyHelmetServerLocalTimestampIsAcceptedOnlyWithExactValidCalendarFormat() {
        useHelmet();
        JSONObject oldIngress = helmetEvent("old-ingress", "01:00:00", true);
        oldIngress.put("sourceKey", "belt-physical:alarm:77:2026-10-21 10:00:59"); add(oldIngress);
        JSONObject impossibleDate = helmetEvent("invalid-calendar", "02:00:00", true);
        impossibleDate.put("sourceKey", "belt-physical:alarm:77:2026-02-30 10:00:59"); add(impossibleDate);
        JSONObject invalidTime = helmetEvent("invalid-clock", "02:00:00", true);
        invalidTime.put("sourceKey", "belt-physical:alarm:77:2026-10-21 24:00:00"); add(invalidTime);
        JSONObject looseFormat = helmetEvent("loose-format", "02:00:00", true);
        looseFormat.put("sourceKey", "belt-physical:alarm:77:2026-1-21 10:00:59"); add(looseFormat);
        JSONObject suffix = helmetEvent("unexpected-suffix", "02:00:00", true);
        suffix.put("sourceKey", "belt-physical:alarm:77:2026-10-21 10:00:59 trailing"); add(suffix);
        Map<String, Object> result = read(input());
        assertEquals(1, result.get("total"));
        assertEquals("old-ingress", rows(result).get(0).getString("sourceEventId"));
        assertEquals("direct-helmet", rows(result).get(0).getString("protocol"));
        assertNull(oldIngress.get("protocol"));
    }

    @Test void helmetEnforcesPermissionsSiteRegistrationAndPaginationBeforeSnapshot() {
        useHelmet();
        grant.put("operations", JSONArray.of("assets:read"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        grant.put("operations", JSONArray.of("events:read"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        grant.put("operations", JSONArray.of("assets:read", "events:read"));
        JSONObject foreignSite = input(); foreignSite.put("siteId", "site-2");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> read(foreignSite)).code);
        JSONObject invalidPage = input(); invalidPage.put("pageSize", 101);
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(invalidPage)).code);
        belt.put("type", "BELT");
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        belt.put("type", "HELMET"); belt.put("portalDeviceId", "another-device");
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> read(input())).code);
        verifyNoInteractions(guardian);
    }

    @Test void helmetUsesItsOwnFallbackAlarmName() {
        useHelmet(); JSONObject row = helmetEvent("no-title", "01:00:00", false); row.remove("title"); add(row);
        assertEquals("安全帽设备告警", rows(read(input())).get(0).getString("alarmName"));
    }
}
