package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;

import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminHelmetTelemetryTest {
    JSONObject ledger, remote, snapshot;
    AdminQueryService queries;

    @BeforeEach void setup() {
        JSONObject asset = object("id", "helmet-asset", "siteId", "site-1", "type", "HELMET", "source", "DIRECT_HELMET",
                "deviceNumber", "helmet-physical", "portalDeviceId", "helmet-physical", "lifecycle", "STOCK", "relation", "UNASSIGNED");
        ledger = object("accounts", JSONArray.of(object("id", "demo-system", "enabled", true)),
                "sites", JSONArray.of(object("id", "site-1", "enabled", true)), "devices", JSONArray.of(asset),
                "assignments", new JSONArray(), "people", new JSONArray());
        remote = object("id", "helmet-physical", "source", "DIRECT_HELMET", "active", true);
        snapshot = object("devices", JSONArray.of(remote));
        AdminLedgerStore store = mock(AdminLedgerStore.class);
        when(store.read()).thenAnswer(i -> JSON.parseObject(ledger.toJSONString()));
        GuardianStore guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(i -> JSON.parseObject(snapshot.toJSONString()));
        queries = new AdminQueryService(store, guardian, mock(ObjectProvider.class));
    }

    JSONObject input() { return object("siteId", "site-1", "id", "helmet-asset"); }
    JSONObject detail() { return new JSONObject(queries.query("demo-system", "device", input())); }

    @Test void listAndDetailRetainIndependentBatteryAndWearObservationTimes() {
        JSONObject status = object("online", true, "freshness", "CURRENT", "lastSeenAt", "2026-10-27T01:02:03Z",
                "battery", 61, "batteryReportedAt", "2026-10-27T01:01:03Z", "batteryFreshness", "CURRENT",
                "isWeared", "2", "isWearedReportedAt", "2026-10-27T00:00:03Z", "isWearedFreshness", "STALE",
                "networkType", "4G", "networkTypeReportedAt", "2026-10-27T01:01:03Z", "networkTypeFreshness", "CURRENT");
        DirectHelmetProjection.applyStatus(remote, status);
        JSONObject detail = detail();
        @SuppressWarnings("unchecked") List<JSONObject> list = (List<JSONObject>) queries.query("demo-system", "devices", input()).get("rows");
        for (JSONObject view : new JSONObject[]{detail, list.get(0)}) {
            assertEquals("ONLINE", view.getString("communication")); assertEquals(61, view.getIntValue("battery"));
            assertEquals("CURRENT", view.getString("batteryFreshness"));
            assertEquals("2026-10-27T01:01:03Z", view.getString("batteryReportedAt"));
            assertEquals("STALE", view.getString("isWearedFreshness"));
            assertEquals("2026-10-27T00:00:03Z", view.getString("isWearedReportedAt"));
            assertNull(view.get("worn"), "a current heartbeat must not make older wear data current");
            assertEquals("CURRENT", view.getString("networkTypeFreshness"));
            assertEquals("2026-10-27T01:01:03Z", view.getString("networkTypeReportedAt"));
        }
    }

    @Test void offlineObservationRemainsStaleAndIsNotRedatedByARead() {
        DirectHelmetProjection.applyStatus(remote, object("online", true, "freshness", "CURRENT", "lastSeenAt", "2026-10-27T01:02:03Z",
                "battery", 61, "batteryReportedAt", "2026-10-27T01:01:03Z", "batteryFreshness", "CURRENT",
                "isWeared", "2", "isWearedReportedAt", "2026-10-27T01:01:04Z", "isWearedFreshness", "CURRENT"));
        assertEquals(Boolean.TRUE, detail().getBoolean("worn"));
        DirectHelmetProjection.applyStatus(remote, object("online", false, "freshness", "STALE", "batteryFreshness", "STALE", "isWearedFreshness", "STALE"));
        JSONObject stale = detail();
        assertEquals("OFFLINE", stale.getString("communication")); assertNull(stale.get("worn"));
        assertEquals("STALE", stale.getString("batteryFreshness")); assertEquals("STALE", stale.getString("isWearedFreshness"));
        assertEquals("2026-10-27T01:01:03Z", stale.getString("batteryReportedAt"));
        assertEquals("2026-10-27T01:01:04Z", stale.getString("isWearedReportedAt"));
        assertEquals("2026-10-27T01:02:03Z", stale.getString("sourceTime"));
    }

    @Test void missingFieldEvidenceOrForeignSourceCannotInheritCurrentFreshnessFromLedger() {
        ledger.getJSONArray("devices").getJSONObject(0).putAll(object("batteryFreshness", "CURRENT", "isWearedFreshness", "CURRENT"));
        remote.putAll(object("online", true, "freshness", "CURRENT"));
        JSONObject missing = detail();
        assertEquals("UNKNOWN", missing.getString("batteryFreshness")); assertEquals("UNKNOWN", missing.getString("isWearedFreshness"));
        remote.putAll(object("source", "DIRECT_BELT", "batteryFreshness", "CURRENT", "isWearedFreshness", "CURRENT"));
        JSONObject foreign = detail();
        assertEquals("UNKNOWN", foreign.getString("communication")); assertEquals("UNKNOWN", foreign.getString("batteryFreshness"));
        assertEquals("UNKNOWN", foreign.getString("isWearedFreshness"));
    }

    @Test void beltKeepsPacketFreshnessWithoutInventingHelmetFieldFreshness() {
        ledger.getJSONArray("devices").getJSONObject(0).putAll(object("source", "DIRECT_BELT", "type", "BELT"));
        remote.putAll(object("source", "DIRECT_BELT", "online", true, "freshness", "CURRENT", "battery", 62,
                "isWeared", "1", "telemetryFreshness", "CURRENT", "telemetryReportedAt", "2026-10-27T01:02:03Z"));
        JSONObject current = detail();
        assertEquals("ONLINE", current.getString("communication")); assertEquals(62, current.getIntValue("battery"));
        assertEquals("CURRENT", current.getString("freshness")); assertEquals("CURRENT", current.getString("telemetryFreshness"));
        assertEquals("2026-10-27T01:02:03Z", current.getString("sourceTime"));
        assertFalse(current.containsKey("batteryFreshness")); assertFalse(current.containsKey("isWearedFreshness"));
        remote.putAll(object("online", false, "freshness", "STALE", "telemetryFreshness", "STALE"));
        JSONObject stale = detail();
        assertEquals("OFFLINE", stale.getString("communication")); assertEquals("STALE", stale.getString("telemetryFreshness"));
        assertFalse(stale.containsKey("batteryFreshness")); assertFalse(stale.containsKey("isWearedFreshness"));
    }
}
