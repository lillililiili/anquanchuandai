package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.WearableBusinessStore;
import com.ruoyi.melhat.direct.DirectHelmetProperties;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.time.*;
import java.util.*;
import static com.ruoyi.fuda.FudaMapping.object;
import static org.junit.jupiter.api.Assertions.*;

class FudaPushCaptureTest {
    final Clock clock = Clock.fixed(Instant.parse("2026-11-02T12:00:00Z"), ZoneOffset.UTC);
    final JdbcTemplate jdbc = new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID()
            + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE", "sa", ""));
    final WearableBusinessStore store = new WearableBusinessStore(jdbc);
    final FudaPushProperties properties = new FudaPushProperties();
    final FudaProperties query = new FudaProperties();
    final FudaPushOutbox outbox = new FudaPushOutbox(jdbc);
    final FudaPushCapture capture = new FudaPushCapture(jdbc, outbox, properties, query,
            new DirectHelmetProperties(), new DirectBeltProperties(), clock);
    FudaPushCaptureTest() {
        jdbc.execute("CREATE TABLE wearable_device (id VARCHAR(128) PRIMARY KEY, body LONGTEXT NOT NULL)");
        register("h", "HELMET", "DIRECT_HELMET"); register("b", "BELT", "DIRECT_BELT");
        properties.setEnabled(true); properties.setAllowedLedgerDeviceIds(new LinkedHashSet<>(Arrays.asList("ledger-h", "ledger-b")));
        FudaProperties.LocationProfile profile = new FudaProperties.LocationProfile();
        profile.setVerified(true); profile.setCoordinateSystem("WGS84"); profile.setEvidence("isolated fixture");
        query.getLocationProfiles().put("ledger-h", profile); query.getLocationProfiles().put("ledger-b", profile);
        store.setFudaPushCapture(capture);
        store.load("guardian", null, () -> object("version", 1, "stations", new JSONArray(), "events", new JSONArray(),
                "devices", JSONArray.of(device("h", "H", "DIRECT_HELMET"), device("b", "B", "DIRECT_BELT"))));
    }
    void register(String id, String type, String source) {
        jdbc.update("INSERT INTO wearable_device VALUES (?,?)", "ledger-"+id, object("id", "ledger-"+id, "type", type,
                "source", source, "deviceNumber", id, "portalDeviceId", id, "lifecycle", "IN_STOCK").toJSONString());
    }
    JSONObject device(String id, String type, String source) { return object("id", id, "deviceNumber", id, "type", type, "source", source, "online", false, "active", true); }
    JSONObject raw() { return object("act", "ca_report_location", "device_id", "h", "bat_l", 80, "is_weared", 2, "x_point", 36.5, "y_point", 118.5, "gps", "1"); }
    void receive(String receipt) {
        store.appendDeviceReport(receipt, "direct-helmet", "h", object("raw", raw(), "context", object("receivedAt", clock.instant().toString(), "device", device("h", "H", "DIRECT_HELMET"))));
    }
    List<JSONObject> bodies() { return jdbc.query("SELECT body FROM fuda_push_outbox ORDER BY sequence", (rs,n) -> JSONObject.parseObject(rs.getString(1))); }
    @Test void reportTransactionRollsBackAllOutboundWorkAndReplayKeepsOneEventPerKind() {
        receive("receipt-1");
        assertThrows(IllegalStateException.class, () -> store.processReport("receipt-1", () -> { throw new IllegalStateException("failed"); }));
        assertTrue(bodies().isEmpty());
        assertTrue(store.processReport("receipt-1", () -> {})); assertFalse(store.processReport("receipt-1", () -> fail("replayed business")));
        assertEquals(2, bodies().size());
        JSONObject status = bodies().stream().filter(b -> "STATUS".equals(b.getString("eventType"))).findFirst().get().getJSONObject("data");
        assertEquals(80, status.getJSONObject("battery").getIntValue("percent"));
        assertEquals("UNKNOWN", status.getJSONObject("network").getString("type"));
        assertNull(status.getJSONObject("network").get("signalLevel"));
        JSONObject position = bodies().stream().filter(b -> "POSITION".equals(b.getString("eventType"))).findFirst().get().getJSONObject("data");
        assertEquals("WGS84", position.getJSONObject("position").getString("coordinateSystem"));
        assertNull(position.getJSONObject("position").get("altitude"));
        assertFalse(bodies().toString().contains("rawPacket"));
    }
    @Test void disabledUnauthorisedAndSimulatedReportsAreNotExported() {
        properties.setEnabled(false); receive("off"); store.processReport("off", () -> {}); assertTrue(bodies().isEmpty());
        properties.setEnabled(true); properties.getAllowedLedgerDeviceIds().clear(); receive("unauthorized"); store.processReport("unauthorized", () -> {}); assertTrue(bodies().isEmpty());
        properties.getAllowedLedgerDeviceIds().add("ledger-h");
        jdbc.update("UPDATE wearable_device SET body=? WHERE id='ledger-h'", object("id", "ledger-h", "type", "HELMET", "source", "DIRECT_HELMET", "deviceNumber", "h", "portalDeviceId", "h", "simulated", true).toJSONString());
        receive("simulated"); store.processReport("simulated", () -> {}); assertTrue(bodies().isEmpty());
    }
    @Test void newAlarmsShareBusinessTransactionAndDispositionDoesNotRepush() {
        WearableBusinessStore.Snapshot current = store.read("guardian");
        current.state.getJSONArray("events").add(object("id", "alarm-1", "deviceId", "b", "source", "device", "protocol", "direct-belt",
                "rawAlarmType", "unconfirmed-99", "sourceKey", "b:belt:alarm:99:2026-11-02T12:00:00Z", "createdAt", clock.instant().toString(), "title", "设备报警", "type", "设备通信"));
        assertThrows(IllegalStateException.class, () -> store.save("guardian", current.revision, current.state, () -> { throw new IllegalStateException(); }));
        assertTrue(bodies().isEmpty());
        long revision = store.save("guardian", current.revision, current.state, null); assertEquals(1, bodies().size());
        assertEquals("ALARM", bodies().get(0).getString("eventType"));
        assertEquals("alarm-1", bodies().get(0).getJSONObject("data").getString("eventId"));
        current.state.getJSONArray("events").getJSONObject(0).put("status", "已核验");
        store.save("guardian", revision, current.state, null); assertEquals(1, bodies().size());
    }
    @Test void onlineOfflineChangesAreDurableAndDoNotRepeatOnUnrelatedEdits() {
        WearableBusinessStore.Snapshot current = store.read("guardian");
        JSONObject h = current.state.getJSONArray("devices").getJSONObject(0); h.put("online", true); h.put("lastSeenAt", clock.instant().toString());
        long rev = store.save("guardian", current.revision, current.state, null); assertEquals("ONLINE", bodies().get(0).getString("trigger"));
        h.put("name", "renamed"); rev = store.save("guardian", rev, current.state, null); assertEquals(1, bodies().size());
        h.put("online", false); store.save("guardian", rev, current.state, null);
        assertEquals(2, bodies().size()); assertEquals("OFFLINE", bodies().get(1).getString("trigger"));
    }
    @Test void lateOuterRollbackRevertsOutboxAndReceiptMarkerTogether() {
        receive("outer");
        org.springframework.transaction.support.TransactionTemplate tx = new org.springframework.transaction.support.TransactionTemplate(
                new org.springframework.jdbc.datasource.DataSourceTransactionManager(jdbc.getDataSource()));
        assertThrows(IllegalStateException.class, () -> tx.execute(s -> {
            store.processReport("outer", () -> {}); assertEquals(2, bodies().size()); throw new IllegalStateException("outer failed");
        }));
        assertTrue(bodies().isEmpty()); assertEquals(1, store.pendingReports(0, 100).size());
        store.processReport("outer", () -> {}); assertEquals(2, bodies().size());
    }
    @Test void identicalValuesInDifferentReceiptsRemainSeparateObservationsAndReplayDoesNotRewriteThem() {
        receive("r1"); receive("r2"); store.processReport("r1", () -> {}); store.processReport("r2", () -> {});
        assertEquals(4, bodies().size()); assertEquals(4, bodies().stream().map(b -> b.getString("eventId")).distinct().count());
        String original=bodies().toString();
        WearableBusinessStore restarted=new WearableBusinessStore(jdbc); restarted.setFudaPushCapture(capture);
        assertFalse(restarted.processReport("r1", () -> fail("already processed"))); assertEquals(original,bodies().toString());
    }
    @Test void invalidOrCachedHelmetCoordinatesDoNotGeneratePositionEvents() {
        JSONObject frame=raw(); frame.put("x_point",0); frame.put("y_point",0);
        store.appendDeviceReport("no-fix","direct-helmet","h",object("raw",frame,"context",object("device",device("h","H","DIRECT_HELMET"))));
        store.processReport("no-fix",()->{}); assertEquals(1,bodies().size()); assertEquals("STATUS",bodies().get(0).getString("eventType"));
        frame=raw(); frame.put("gps","4");
        store.appendDeviceReport("cached","direct-helmet","h",object("raw",frame,"context",object("device",device("h","H","DIRECT_HELMET"))));
        store.processReport("cached",()->{}); assertEquals(2,bodies().size());
    }
    @Test void beltUsesCapturedStatusAndDoesNotInventWearOrHookMapping() {
        String at=clock.instant().minusSeconds(3600).toString();
        JSONObject status=object("online",true,"lastSeenAt",at,"telemetryReportedAt",at,"telemetryFreshness","CURRENT",
                "battery",65,"isWeared",2,"hangerAStatus",1,"hangerBStatus",2,
                "longitude",118.5,"latitude",36.5,"locationReportedAt",at,"locationFreshness","CURRENT","coordinateSystem","UNKNOWN","locationQuality","unknown");
        JSONObject frame=object("act","ca_report_location","imei","b","bat_l",65,"x_point",36.5,"y_point",118.5);
        store.appendDeviceReport("belt","direct-belt","b",object("raw",frame,"status",status,"context",object("device",device("b","B","DIRECT_BELT"))));
        store.processReport("belt",()->{}); assertEquals(2,bodies().size());
        JSONObject event=bodies().get(0),data=event.getJSONObject("data");
        assertEquals(Instant.parse(at),Instant.parse(event.getString("occurredAt")));
        assertEquals(65,data.getJSONObject("battery").getIntValue("percent"));
        assertEquals("UNKNOWN",data.getJSONObject("wear").getString("status"));
        assertEquals("UNKNOWN",data.getJSONObject("hookA").getString("status"));
    }
    @Test void recoveringOldBeltReportDoesNotInventAConnectionAtRecoveryTime() {
        String old=clock.instant().minusSeconds(3600).toString();
        JSONObject status=object("online",true,"lastSeenAt",old,"telemetryReportedAt",old,"telemetryFreshness","CURRENT","battery",55);
        store.appendDeviceReport("old-belt","direct-belt","b",object("raw",object("act","ca_report_location","imei","b","bat_l",55),
                "status",status,"context",object("device",device("b","B","DIRECT_BELT"))));
        // GuardianIngest's delayed replay applies captured online=true to the business projection.
        store.processReport("old-belt",()->{
            WearableBusinessStore.Snapshot current=store.read("guardian");
            current.state.getJSONArray("devices").getJSONObject(1).putAll(status);
            store.save("guardian",current.revision,current.state,null);
        });
        assertEquals(1,bodies().size(),"historical receipt cannot invent an ONLINE transition");
        assertEquals("REPORT",bodies().get(0).getString("trigger"));
        assertEquals(Instant.parse(old),Instant.parse(bodies().get(0).getString("occurredAt")));
        WearableBusinessStore.Snapshot current=store.read("guardian");
        current.state.getJSONArray("devices").getJSONObject(1).put("online",false);
        store.save("guardian",current.revision,current.state,null);
        assertEquals("OFFLINE",bodies().get(1).getString("trigger"));
    }
    @Test void receiptReconciliationStillExportsARealOfflineTransitionAndOtherDevices() {
        WearableBusinessStore.Snapshot before=store.read("guardian");
        before.state.getJSONArray("devices").getJSONObject(0).put("online",true);
        store.save("guardian",before.revision,before.state,null);
        receive("offline-recovery");
        store.processReport("offline-recovery",()->{
            WearableBusinessStore.Snapshot current=store.read("guardian");
            current.state.getJSONArray("devices").getJSONObject(0).put("online",false);
            current.state.getJSONArray("devices").getJSONObject(1).put("online",true);
            store.save("guardian",current.revision,current.state,null);
        });
        assertEquals(1,bodies().stream().filter(e->"OFFLINE".equals(e.getString("trigger"))&&"h".equals(e.getJSONObject("data").getString("deviceId"))).count());
        assertEquals(1,bodies().stream().filter(e->"ONLINE".equals(e.getString("trigger"))&&"b".equals(e.getJSONObject("data").getString("deviceId"))).count());
    }
}
