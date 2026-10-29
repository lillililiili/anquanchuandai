package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.service.DirectHelmetAccess;
import com.ruoyi.helmet.service.ITtsTextSynthesisBroadcastService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectHelmetIngestTest {
    @TempDir Path directory;
    GuardianStore store;
    GuardianIngest ingest;
    DirectHelmetAccess direct;
    JSONObject status;

    @BeforeEach void setup() throws Exception {
        store = new GuardianStore(mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(store, "file", directory.resolve("guardian.json"));
        JSONObject seed = JSONObject.parseObject(StreamUtils.copyToString(
                new ClassPathResource("guardian-seed.json").getInputStream(), StandardCharsets.UTF_8));
        JSONObject helmet = find(seed, "devices", "RL-H001");
        helmet.put("source", "DIRECT_HELMET");
        helmet.put("sn", "serial-test");
        helmet.put("deviceNumber", "RL-H001");
        store.replace(seed);
        direct = mock(DirectHelmetAccess.class);
        ObjectProvider<DirectHelmetAccess> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(direct);
        status = object("online", true, "freshness", "CURRENT", "lastSeenAt", "2026-10-20T12:00:00Z",
                "battery", 85, "isWeared", "2", "isWearedFreshness", "CURRENT", "capabilities", JSONArray.parseArray("[\"battery\",\"wear\",\"sos\"]"));
        when(direct.status("RL-H001")).thenAnswer(i -> copy(status));
        ReflectionTestUtils.setField(store, "directAccess", provider);
        ingest = new GuardianIngest(store);
    }

    @Test void realWearAndBatterySurviveWithoutGpsAndBecomeUnknownWhenOffline() {
        ingest.directTelemetry("RL-H001", status);
        JSONObject helmet = find(store.snapshot(), "devices", "RL-H001");
        assertEquals(85, helmet.getIntValue("battery"));
        assertEquals(Boolean.TRUE, helmet.getBoolean("worn"));
        assertNull(helmet.get("locationReportedAt"));
        assertFalse(helmet.getJSONArray("capabilities").contains("intercom"));
        status.put("isWeared", "1");
        assertEquals(Boolean.FALSE, find(store.snapshot(), "devices", "RL-H001").getBoolean("worn"));
        status.put("online", false); status.put("freshness", "STALE");
        helmet = find(store.snapshot(), "devices", "RL-H001");
        assertFalse(helmet.getBooleanValue("online"));
        assertNull(helmet.get("worn"));
        assertEquals("2026-10-20T12:00:00Z", helmet.getString("sourceTime"));
    }

    @Test void unassignedHelmetRetainsRealCoordinatesAndRejectsInvalidFixes() {
        store.update(state -> {
            rows(state, "bindings").removeIf(row -> "RL-H001".equals(((JSONObject) row).getString("deviceId")));
            return true;
        });
        int before = rows(store.snapshot(), "locations").size();
        ingest.location("RL-H001", "116.4", "39.9", "2026-10-20T12:00:01Z");
        JSONObject fix = rows(store.snapshot(), "locations").getJSONObject(0);
        assertEquals(before + 1, rows(store.snapshot(), "locations").size());
        assertEquals("", fix.getString("personId"));
        assertEquals("116.4", fix.getString("lng"));
        assertEquals("39.9", fix.getString("lat"));
        assertFalse(fix.getBooleanValue("inside"));
        ingest.location("RL-H001", "NaN", "35", null);
        ingest.location("RL-H001", "0", "0", null);
        ingest.location("RL-H001", "180.1", "35", null);
        assertEquals(before + 1, rows(store.snapshot(), "locations").size());
    }

    @Test void vendorAlarmCodeIsPreservedAndSosGetsIndependentAssistance() {
        int before = rows(store.snapshot(), "events").size();
        ingest.directAlarm("RL-H001", "77", "2026-10-20T12:00:01Z");
        ingest.directAlarm("RL-H001", "77", "2026-10-20T12:00:01Z");
        JSONObject state = store.snapshot();
        assertEquals(before + 1, rows(state, "events").size());
        assertEquals("77", rows(state, "events").getJSONObject(0).getString("rawAlarmType"));
        ingest.sos("RL-H001", null, null, "2026-10-20T12:00:02Z");
        state = store.snapshot();
        JSONObject event = rows(state, "events").getJSONObject(0);
        assertEquals("device", event.getString("source"));
        assertNotNull(state.getJSONObject("assistance").getJSONObject(event.getString("id")));
    }

    @Test void persistedOnlineFlagCannotSurviveMissingRuntimeSession() {
        store.snapshot();
        GuardianStore restarted = new GuardianStore(mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(restarted, "file", directory.resolve("guardian.json"));
        JSONObject helmet = find(restarted.snapshot(), "devices", "RL-H001");
        assertFalse(helmet.getBooleanValue("online"));
        assertEquals("STALE", helmet.getString("freshness"));
        assertNull(helmet.get("worn"));
    }

    @Test void unchangedDevicePollDoesNotAdvanceTheSharedSnapshotVersion() {
        int version = store.snapshot().getIntValue("seq");
        assertEquals(version, store.snapshot().getIntValue("seq"));
        assertEquals(version, store.snapshot().getIntValue("seq"));
    }

    @Test void directGeographicLocationRetainsOutsideCoordinatesAndNeverInventsDemoMapPoints() {
        JSONObject point=ingest.captureDirect("RL-H001");
        point.putAll(object("id","HL-test-outside","deviceId","RL-H001","longitude","116.4","latitude","39.9",
                "coordinateSystem","UNKNOWN","locationSource","CELL","locationQuality","unknown","accuracyMeters",300,
                "receivedAt","2026-10-20T12:00:01Z","reportedAt","2026-10-20T12:00:01Z","source","direct-helmet"));
        ingest.directLocation(point);ingest.directLocation(point);
        JSONObject fix=rows(store.snapshot(),"locations").getJSONObject(0);
        assertEquals("116.4",fix.getString("longitude"));assertEquals("UNKNOWN",fix.getString("coordinateSystem"));
        assertFalse(fix.containsKey("x"));assertFalse(fix.containsKey("y"));
        assertEquals(1,rows(store.snapshot(),"locations").stream().filter(p->"HL-test-outside".equals(((JSONObject)p).getString("id"))).count());
    }

    @Test void recoveredEventKeepsOriginalOwnerAndLocationDespiteReassignmentAndProjectsOnlyOnce() {
        JSONObject envelope=ingest.captureDirect("RL-H001");String originalOwner=envelope.getString("personId");
        envelope.putAll(object("eventId","HE-recovered","deviceId","RL-H001","act","ca_sip_sos","sourceRecordType","sos_alarm_record",
                "sourceRecordId",41,"receivedAt","2026-10-20T12:00:01Z","longitude","116.4","latitude","39.9","coordinateSystem","UNKNOWN","locationQuality","unknown"));
        store.update(state->{rows(state,"bindings").removeIf(b->"RL-H001".equals(((JSONObject)b).getString("deviceId")));return true;});
        ingest.projectDirectEvent(envelope);ingest.projectDirectEvent(envelope);
        JSONObject event=find(store.snapshot(),"events","HE-recovered");
        assertEquals(originalOwner,event.getString("personId"));assertEquals(41,event.getIntValue("sourceRecordId"));
        assertEquals("116.4",event.getString("locationLng"));assertEquals("unknown",event.getString("locationQuality"));
        assertEquals(1,rows(store.snapshot(),"events").stream().filter(e->"HE-recovered".equals(((JSONObject)e).getString("id"))).count());
        assertNotNull(store.snapshot().getJSONObject("assistance").getJSONObject("HE-recovered"));
    }

    @Test void geographicFenceAcceptsRealDegreeScaleAndRejectsUnknownOrInvalidCoordinateSystems() {
        JSONObject snapshot=store.snapshot(), fence=rows(snapshot,"fences").getJSONObject(0);
        fence.put("coordinateSystem","GCJ02");fence.put("points",JSONArray.parseArray("[[116.40,39.90],[116.41,39.90],[116.41,39.91],[116.40,39.91]]"));
        assertDoesNotThrow(()->GuardianValidator.check(snapshot));
        fence.put("coordinateSystem","UNKNOWN");assertThrows(IllegalArgumentException.class,()->GuardianValidator.check(snapshot));
        fence.put("coordinateSystem","GCJ02");fence.put("points",JSONArray.parseArray("[[181,39],[182,39],[182,40]]"));
        assertThrows(IllegalArgumentException.class,()->GuardianValidator.check(snapshot));
    }

    @Test void repeatedSourceRetriesIncrementOnlyOnceAndKeepTheInitialEvidenceAndOwner() {
        JSONObject first=ingest.captureDirect("RL-H001");
        first.putAll(object("eventId","HE-repeat","deviceId","RL-H001","act","ca_sos","rawType","77",
                "sourceRecordType","real_time_alarm","sourceRecordId",1,"receivedAt","2026-10-23T00:00:01Z",
                "longitude","116.4","latitude","39.9","coordinateSystem","UNKNOWN","locationQuality","unknown"));
        JSONObject repeat=copy(first);repeat.put("sourceRecordId",2);repeat.put("receivedAt","2026-10-23T00:00:02Z");repeat.put("longitude","116.5");
        ingest.projectDirectEvent(first);ingest.projectDirectEvent(repeat);ingest.projectDirectEvent(repeat);
        GuardianStore restarted=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(restarted,"file",directory.resolve("guardian.json"));
        new GuardianIngest(restarted).projectDirectEvent(first);
        JSONObject event=find(restarted.snapshot(),"events","HE-repeat");
        assertEquals(2,event.getIntValue("reportCount"));assertEquals(2,event.getIntValue("version"));
        assertEquals(2,event.getJSONArray("sourceRecords").size());assertEquals(2,event.getJSONArray("timeline").size());
        assertEquals("116.4",event.getString("locationLng"));assertEquals(first.getString("personId"),event.getString("personId"));
        assertEquals("2026-10-23T00:00:02Z",event.getString("lastReportedAt"));
    }

    @Test void capturedAssignmentIdentityChangesEvenWhenTheSamePersonBorrowsAgain() {
        JSONObject before=ingest.captureDirect("RL-H001");
        store.update(state->{
            for(Object raw:rows(state,"bindings")) {
                JSONObject b=(JSONObject)raw;
                if("RL-H001".equals(b.getString("deviceId")) && b.get("end")==null) b.put("end","2026-10-23T00:01:00Z");
            }
            return true;
        });
        JSONObject returned=ingest.captureDirect("RL-H001");
        assertEquals("",returned.getString("personId"));assertNotNull(returned.getString("bindingEnd"));
        store.update(state->{rows(state,"bindings").add(object("id","BIND-again","deviceId","RL-H001","personId",before.getString("personId"),"start","2026-10-23T00:02:00Z","end",null));return true;});
        JSONObject again=ingest.captureDirect("RL-H001");
        assertEquals(before.getString("personId"),again.getString("personId"));
        assertNotEquals(before.getString("bindingId"),again.getString("bindingId"));
    }

    @Test void laterDeliveryRecoversTheInitialReportBeforeAppendingItsOwnEvidence() {
        JSONObject first=ingest.captureDirect("RL-H001");
        first.putAll(object("eventId","HE-reordered","deviceId","RL-H001","act","ca_sos","rawType","77",
                "sourceRecordType","real_time_alarm","sourceRecordId",1,"receivedAt","2026-10-23T00:00:01Z","longitude","116.4"));
        JSONObject second=copy(first);second.put("sourceRecordId",2);second.put("receivedAt","2026-10-23T00:00:02Z");second.put("longitude","116.5");second.put("initialReport",copy(first));
        ingest.projectDirectEvent(second);ingest.projectDirectEvent(first);ingest.projectDirectEvent(second);
        JSONObject event=find(store.snapshot(),"events","HE-reordered");
        assertEquals("2026-10-23T00:00:01Z",event.getString("createdAt"));
        assertEquals("116.4",event.getString("locationLng"));assertEquals(2,event.getIntValue("reportCount"));
        assertEquals(1,event.getLongValue("sourceRecordId"));
    }

    @Test void directHelmetNeverFallsThroughToCloudAgoraOrTts() {
        HeadbandService cloud = mock(HeadbandService.class);
        GuardianVoiceService voice = new GuardianVoiceService(cloud, mock(ITtsTextSynthesisBroadcastService.class));
        ObjectProvider<DirectHelmetAccess> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(direct);
        when(direct.supports("RL-H001")).thenReturn(true);
        ReflectionTestUtils.setField(voice, "directAccess", provider);
        JSONArray hats = new JSONArray(); hats.add(object("hatNumber", "RL-H001"));
        assertThrows(GuardianRejected.class, () -> voice.call(hats,"test-operator",false));
        assertThrows(GuardianRejected.class, () -> voice.broadcast(hats, "测试"));
        verifyNoInteractions(cloud);
    }
}
