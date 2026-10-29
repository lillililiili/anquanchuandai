package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectBeltIngestTest {
    @TempDir Path directory;
    AdminLedgerStore ledger;
    GuardianStore store;
    GuardianHatArchive hats;
    DirectBeltTelemetryService telemetry;
    JSONObject admin, device, person, status;

    @BeforeEach void setup() throws Exception {
        admin = DirectBeltRegistrationTest.seed("admin-seed.json");
        migrate(admin);
        person = rows(admin, "people").getJSONObject(0);
        device = object("id", "belt-test", "type", "BELT", "source", "DIRECT_BELT",
                "deviceNumber", "BELT-LOGIN-100", "portalDeviceId", "BELT-LOGIN-100", "code", "BELT-ASSET-100",
                "sn", "SERIAL-TEST", "name", "测试安全带", "siteId", "site-1", "lifecycle", "IN_USE", "version", 1);
        rows(admin, "devices").add(device);
        admin.put("assignments", JSONArray.of(object("id", "belt-assignment", "deviceId", "belt-test",
                "personId", person.getString("id"), "active", true, "version", 1, "startedAt", "2026-10-20T11:00:00Z")));
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> copy(admin));
        hats = mock(GuardianHatArchive.class);
        store = new GuardianStore(hats);
        ReflectionTestUtils.setField(store, "file", directory.resolve("guardian.json"));
        store.replace(DirectBeltRegistrationTest.seed("guardian-seed.json"));
        ReflectionTestUtils.setField(store, "ledger", ledger);
        DirectBeltAccess access = mock(DirectBeltAccess.class);
        ObjectProvider<DirectBeltAccess> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(access);
        status = object("online", true, "freshness", "CURRENT", "lastSeenAt", "2026-10-20T12:00:00Z",
                "telemetryFreshness", "CURRENT", "telemetryReportedAt", "2026-10-20T12:00:00Z",
                "battery", 83, "isWeared", "1", "hangerAStatus", "7", "hangerBStatus", "8",
                "wearMappingConfirmed", false, "hookMappingConfirmed", false,
                "capabilities", JSONArray.of("battery", "raw-hook-status"));
        when(access.status("BELT-LOGIN-100")).thenAnswer(i -> copy(status));
        ReflectionTestUtils.setField(store, "directBeltAccess", provider);
        telemetry = new DirectBeltTelemetryService(ledger, store);
    }

    @Test void registrationRequiresExactBeltIdentityAndEnabledSiteAndCurrentSameSiteWearer() {
        assertEquals(person.getString("portalId"), telemetry.registered("BELT-LOGIN-100").getString("userId"));
        assertNull(telemetry.registered("BELT-ASSET-100"));
        assertNull(telemetry.registered("SERIAL-TEST"));
        device.put("source", "DIRECT_HELMET"); assertNull(telemetry.registered("BELT-LOGIN-100"));
        device.put("source", "DIRECT_BELT"); device.put("type", "HELMET"); assertNull(telemetry.registered("BELT-LOGIN-100"));
        device.put("type", "BELT"); device.put("lifecycle", "DISABLED"); assertNull(telemetry.registered("BELT-LOGIN-100"));
        device.put("lifecycle", "IN_USE"); person.put("siteId", "site-2"); assertNull(telemetry.registered("BELT-LOGIN-100"));
        person.put("siteId", "site-1"); find(admin, "sites", "site-1").put("enabled", false);
        assertNull(telemetry.registered("BELT-LOGIN-100"));
    }

    @Test void unconfirmedRawValuesNeverBecomeSafeAndOfflineClearsConfirmedState() {
        telemetry.report("BELT-LOGIN-100", status);
        JSONObject belt = find(store.snapshot(), "devices", "BELT-LOGIN-100");
        assertEquals(83, belt.getIntValue("battery"));
        assertEquals("7", belt.getString("hangerAStatus"));
        assertNull(belt.get("worn")); assertNull(belt.get("hookAEngaged"));
        status.put("wearMappingConfirmed", true); status.put("hookMappingConfirmed", true);
        status.put("worn", true); status.put("hookAEngaged", true); status.put("hookBEngaged", false);
        belt = find(store.snapshot(), "devices", "BELT-LOGIN-100");
        assertEquals(Boolean.TRUE, belt.getBoolean("worn"));
        assertEquals(Boolean.TRUE, belt.getBoolean("hookAEngaged"));
        assertEquals(Boolean.FALSE, belt.getBoolean("hookBEngaged"));
        status.put("telemetryFreshness", "STALE");
        belt = find(store.snapshot(), "devices", "BELT-LOGIN-100");
        assertTrue(belt.getBooleanValue("online"));
        assertNull(belt.get("worn")); assertNull(belt.get("hookAEngaged"));
        status.put("online", false); status.put("freshness", "STALE");
        belt = find(store.snapshot(), "devices", "BELT-LOGIN-100");
        assertNull(belt.get("worn")); assertNull(belt.get("hookAEngaged")); assertNull(belt.get("hookBEngaged"));
    }

    @Test void capturedLocationUpdatesOnlyTheSameCurrentWearerAndRetainsOriginalAttribution(){
        JSONObject captured=new GuardianIngest(store).captureBelt("BELT-LOGIN-100");
        status.put("longitude","112.574204");status.put("latitude","35.466123");status.put("locationFreshness","CURRENT");status.put("locationReportedAt","2026-10-20T12:00:00Z");
        status.put("coordinateSystem","WGS84");status.put("locationQuality","valid");
        telemetry.receiveCaptured("BELT-LOGIN-100",status,null,null,false,captured);
        JSONObject current=find(store.snapshot(),"people",person.getString("portalId"));
        assertEquals("2026-10-20T12:00:00Z",current.getString("locationReportedAt"));
        admin.put("assignments",new JSONArray());device.put("lifecycle","STOCK");
        status.put("locationReportedAt","2026-10-20T12:01:00Z");
        telemetry.receiveCaptured("BELT-LOGIN-100",status,null,null,false,captured);
        JSONObject after=store.snapshot();assertEquals(person.getString("portalId"),rows(after,"locations").getJSONObject(0).getString("personId"));
        assertNull(find(after,"people",person.getString("portalId")).get("locationReportedAt"));
        assertEquals("2026-10-20T12:00:00Z",find(after,"people",person.getString("portalId")).getJSONObject("lastKnownLocation").getString("locationReportedAt"));
    }
    @Test void validNewLocationIsDurableDeduplicatedAndAttributedFromCurrentLedger() {
        status.put("longitude", "116.4"); status.put("latitude", "39.9");
        status.put("locationFreshness", "CURRENT"); status.put("locationReportedAt", "2026-10-20T12:00:00Z");
        int before = rows(store.snapshot(), "locations").size();
        telemetry.report("BELT-LOGIN-100", status); telemetry.report("BELT-LOGIN-100", status);
        JSONObject state = store.snapshot();
        assertEquals(before + 1, rows(state, "locations").size());
        JSONObject fix = rows(state, "locations").getJSONObject(0);
        assertEquals(person.getString("portalId"), fix.getString("personId"));
        assertEquals("site-1", fix.getString("siteId"));
        assertEquals("116.4", fix.getString("lng")); assertFalse(fix.getBooleanValue("inside"));
        assertFalse(find(state, "people", person.getString("portalId")).getBooleanValue("locationValid"));
        admin.put("assignments", new JSONArray()); device.put("lifecycle", "STOCK");
        status.put("locationReportedAt", "2026-10-20T12:00:01Z");
        telemetry.report("BELT-LOGIN-100", status);
        fix = rows(store.snapshot(), "locations").getJSONObject(0);
        assertEquals("", fix.getString("personId"));
        status.put("longitude", "0"); status.put("latitude", "0");
        status.put("locationReportedAt", "2026-10-20T12:00:02Z");
        telemetry.report("BELT-LOGIN-100", status);
        assertEquals(before + 2, rows(store.snapshot(), "locations").size());
    }

    @Test void alarmAndSosUseBeltIdentityPreserveRawCodeAndAvoidDuplicates() {
        int before = rows(store.snapshot(), "events").size();
        telemetry.receive("BELT-LOGIN-100", status, "77", "2026-10-20T12:00:01Z", false);
        telemetry.receive("BELT-LOGIN-100", status, "77", "2026-10-20T12:00:01Z", false);
        JSONObject state = store.snapshot();
        assertEquals(before + 1, rows(state, "events").size());
        JSONObject event = rows(state, "events").getJSONObject(0);
        assertEquals("77", event.getString("rawAlarmType"));
        assertEquals("device", event.getString("source"));
        assertEquals("direct-belt", event.getString("protocol"));
        assertEquals(person.getString("portalId"), event.getString("personId"));
        assertEquals("site-1", event.getString("siteId"));
        assertEquals("SERIAL-TEST", event.getJSONObject("snapshot").getString("sn"));
        telemetry.receive("BELT-LOGIN-100", status, null, "2026-10-20T12:00:02Z", true);
        state = store.snapshot(); event = rows(state, "events").getJSONObject(0);
        assertEquals("安全带发起 SOS", event.getString("title"));
        assertNotNull(state.getJSONObject("assistance").getJSONObject(event.getString("id")));
        assertEquals(before + 2, rows(state, "events").size());
    }

    @Test void revokedRegistrationAndStorageFailuresAreNotAcknowledged() {
        store.snapshot();
        device.put("lifecycle", "DISABLED");
        assertThrows(IllegalArgumentException.class, () -> telemetry.report("BELT-LOGIN-100", status));
        assertThrows(IllegalArgumentException.class, () -> telemetry.alarm("BELT-LOGIN-100", "77", null));
        device.put("lifecycle", "IN_USE");
        JSONObject before = store.snapshot();
        doAnswer(i -> {
            JSONObject state = i.getArgument(0);
            if (rows(state, "events").size() > rows(before, "events").size()) throw new IllegalStateException("test persistence failure");
            return null;
        }).when(hats).sync(any());
        assertThrows(IllegalStateException.class, () -> telemetry.receive("BELT-LOGIN-100", status, "77", "2026-10-20T12:00:01Z", false));
        assertEquals(rows(before, "events").size(), rows(store.snapshot(), "events").size());
    }

    @Test void restartCannotRevivePersistedOnlineOrSafeFlags() {
        status.put("wearMappingConfirmed", true); status.put("worn", true);
        status.put("hookMappingConfirmed", true); status.put("hookAEngaged", true);
        store.snapshot();
        GuardianStore restarted = new GuardianStore(mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(restarted, "file", directory.resolve("guardian.json"));
        JSONObject belt = find(restarted.snapshot(), "devices", "BELT-LOGIN-100");
        assertFalse(belt.getBooleanValue("online"));
        assertEquals("UNKNOWN", belt.getString("freshness"));
        assertNull(belt.get("worn")); assertNull(belt.get("hookAEngaged")); assertEquals(83,belt.getIntValue("battery"));
        assertEquals("UNKNOWN",belt.getString("telemetryFreshness"));
    }

    @Test void locationSourcesDoNotInvalidateEachOtherAndOldFixDoesNotMovePersonBackwards() {
        status.put("coordinateSystem","GCJ02");status.put("locationQuality","valid");
        status.put("longitude", "112.574204"); status.put("latitude", "35.466123");
        status.put("locationFreshness", "CURRENT"); status.put("locationReportedAt", "2026-10-20T12:00:00Z");
        telemetry.report("BELT-LOGIN-100", status);
        JSONObject snapshot = store.snapshot();
        JSONObject wearer = find(snapshot, "people", person.getString("portalId"));
        assertTrue(wearer.getBooleanValue("locationValid"));
        assertEquals("BELT-LOGIN-100", wearer.getString("locationDeviceId"));
        rows(snapshot, "devices").add(object("id", "STALE-HELMET", "type", "H", "source", "DIRECT_HELMET", "active", true));
        rows(snapshot, "bindings").add(object("deviceId", "STALE-HELMET", "personId", wearer.getString("id"), "end", null));
        DirectHelmetProjection.apply(snapshot, null);
        assertTrue(wearer.getBooleanValue("locationValid"));
        Object longitude=wearer.get("longitude");
        assertNull(wearer.get("position"));
        status.put("locationReportedAt", "2026-10-20T11:59:59Z");
        status.put("longitude", "116.4"); status.put("latitude", "39.9");
        telemetry.report("BELT-LOGIN-100", status);
        wearer = find(store.snapshot(), "people", person.getString("portalId"));
        assertTrue(wearer.getBooleanValue("locationValid"));
        assertEquals(longitude, wearer.get("longitude"));
        assertNull(wearer.get("position"));
        assertEquals("2026-10-20T12:00:00Z", wearer.getString("locationReportedAt"));
        snapshot = store.snapshot(); wearer = find(snapshot, "people", person.getString("portalId"));
        wearer.put("locationDeviceId", "CURRENT-HELMET");
        DirectBeltProjection.apply(snapshot, null);
        assertTrue(wearer.getBooleanValue("locationValid"));
    }
}
