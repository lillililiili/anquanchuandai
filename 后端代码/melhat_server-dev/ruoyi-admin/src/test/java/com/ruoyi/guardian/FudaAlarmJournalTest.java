package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;

class FudaAlarmJournalTest {
    private static final String HELMET_KEY = "HELMET:H-LOGIN";
    private static final String BELT_KEY = "SAFETY_BELT:B-LOGIN";
    private JdbcTemplate database() {
        return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID()
                + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;LOCK_TIMEOUT=10000", "sa", ""));
    }
    private JSONObject helmet() { return object("id", "helmet-internal", "type", "H", "source", "DIRECT_HELMET", "deviceNumber", "H-LOGIN", "model", "RD-D1+", "firmware", "original-firmware"); }
    private JSONObject belt() { return object("id", "belt-internal", "type", "B", "source", "DIRECT_BELT", "deviceNumber", "B-LOGIN", "model", "RD-1102"); }
    private JSONObject empty() {
        JSONArray devices = new JSONArray(); devices.add(helmet()); devices.add(belt());
        return object("version", 1, "seq", 0, "stations", new JSONArray(), "people", new JSONArray(), "devices", devices, "events", new JSONArray());
    }
    private JSONObject event(String id, boolean belt, String at) {
        return object("id", id, "deviceId", belt ? "belt-internal" : "helmet-internal", "source", "device",
                "protocol", belt ? "direct-belt" : "direct-helmet", "rawAlarmType", "unknown-77",
                "sourceKey", belt ? "belt-internal:belt:alarm:unknown-77:" + at : "helmet-event:" + id,
                "date", "2026-10-27", "time", "10:20", "createdAt", at, "title", "设备告警", "type", "设备通信");
    }
    private long append(WearableBusinessStore store, JSONObject event) {
        WearableBusinessStore.Snapshot before = store.read("guardian"); before.state.getJSONArray("events").add(event);
        return store.save("guardian", before.revision, before.state, null);
    }
    private Set<String> both() { return new HashSet<>(Arrays.asList(HELMET_KEY, BELT_KEY)); }
    private TransactionTemplate transaction(JdbcTemplate jdbc) { return new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource())); }

    @Test void firstBusinessInsertAndJournalRollbackTogether() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        FudaAlarmJournal journal = new FudaAlarmJournal(jdbc);
        WearableBusinessStore.Snapshot first = store.load("guardian", null, this::empty);
        first.state.getJSONArray("events").add(event("rollback-event", false, "2026-10-27T02:00:00Z"));
        assertThrows(IllegalStateException.class, () -> store.save("guardian", first.revision, first.state,
                () -> { throw new IllegalStateException("dependent write failed"); }));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event", Integer.class));
        assertEquals(0, journal.highWatermark()); assertTrue(journal.scan(0, 10, both()).items.isEmpty());
        store.save("guardian", first.revision, first.state, null);
        assertEquals(1, journal.highWatermark());
        assertEquals("rollback-event", journal.scan(0, 10, both()).items.get(0).getString("eventId"));
    }

    @Test void dispositionChangesAndShrinkingSnapshotsNeverRewriteOrDeleteExportEvidence() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        FudaAlarmJournal journal = new FudaAlarmJournal(jdbc); store.load("guardian", null, this::empty);
        JSONObject event = event("immutable", false, "2026-10-27T02:00:00Z");
        event.put("password", "must-not-export"); event.put("rawPacket", object("token", "secret-packet"));
        event.put("snapshot", object("personName", "private-person", "deviceId", "helmet-internal"));
        append(store, event);
        JSONObject original = journal.scan(0, 10, both()).items.get(0);
        WearableBusinessStore.Snapshot current = store.read("guardian");
        JSONObject edited = current.state.getJSONArray("events").getJSONObject(0);
        edited.put("status", "已核验"); edited.put("rawAlarmType", "changed-by-review");
        edited.put("verification", object("description", "private-review"));
        current.state.getJSONArray("devices").getJSONObject(0).put("model", "later-model");
        long revision = store.save("guardian", current.revision, current.state, null);
        assertEquals(original, journal.scan(0, 10, both()).items.get(0));
        current.state.getJSONArray("events").clear(); store.save("guardian", revision, current.state, null);
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event", Integer.class));
        assertEquals(original, journal.scan(0, 10, both()).items.get(0));
        append(store, event); new WearableBusinessStore(jdbc);
        assertEquals(1, journal.highWatermark()); assertEquals(0, journal.retainedFloor());
        String exported = original.toJSONString();
        for (String secret : Arrays.asList("must-not-export", "secret-packet", "private-person", "private-review", "password", "rawPacket"))
            assertFalse(exported.contains(secret));
        assertEquals("unknown-77", original.getJSONObject("rawEvent").getString("rawAlarmType"));
        assertEquals("RD-D1+", original.getString("deviceModel"));
    }

    @Test void lateOlderAlarmArrivesAfterTheAlreadyReturnedCursor() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        FudaAlarmJournal journal = new FudaAlarmJournal(jdbc); store.load("guardian", null, this::empty);
        append(store, event("on-time", true, "2026-10-27T02:00:00Z"));
        long cursor = journal.scan(0, 1, both()).nextSequence;
        append(store, event("late", true, "2026-10-20T01:02:03Z"));
        FudaAlarmJournal.AlarmPage next = journal.scan(cursor, 1, both());
        assertEquals(1, next.items.size()); assertEquals("late", next.items.get(0).getString("eventId"));
        assertEquals("2026-10-20T01:02:03Z", next.items.get(0).getString("occurredAt"));
        assertEquals(2, next.nextSequence); assertFalse(next.hasMore);
    }

    @Test void authorizationIsAppliedBeforeLimitAndAdvancesOverOtherDevicesWithoutLosingLaterEvents() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        FudaAlarmJournal journal = new FudaAlarmJournal(jdbc); store.load("guardian", null, this::empty);
        append(store, event("hidden-first", true, "2026-10-27T01:00:00Z"));
        append(store, event("helmet-first", false, "2026-10-27T01:01:00Z"));
        append(store, event("hidden-middle", true, "2026-10-27T01:02:00Z"));
        append(store, event("helmet-second", false, "2026-10-27T01:03:00Z"));
        append(store, event("hidden-last", true, "2026-10-27T01:04:00Z"));
        Set<String> allowed = Collections.singleton(HELMET_KEY);
        FudaAlarmJournal.AlarmPage first = journal.scan(0, 1, allowed);
        assertEquals("helmet-first", first.items.get(0).getString("eventId")); assertTrue(first.hasMore); assertEquals(2, first.nextSequence);
        FudaAlarmJournal.AlarmPage second = journal.scan(first.nextSequence, 1, allowed);
        assertEquals("helmet-second", second.items.get(0).getString("eventId")); assertFalse(second.hasMore); assertEquals(5, second.nextSequence);
        append(store, event("helmet-later", false, "2026-10-27T01:05:00Z"));
        assertEquals("helmet-later", journal.scan(second.nextSequence, 500, allowed).items.get(0).getString("eventId"));
        assertEquals(6, journal.scan(0, 10, Collections.emptySet()).nextSequence);
        assertThrows(IllegalArgumentException.class, () -> journal.scan(7, 10, allowed));
        jdbc.update("UPDATE fuda_alarm_journal_state SET retained_floor=2 WHERE id=1");
        assertThrows(IllegalArgumentException.class, () -> journal.scan(1, 10, allowed));
    }

    @Test void demoSimulationManualUnknownSourceAndMissingProtocolNumbersAreNotExportable() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        FudaAlarmJournal journal = new FudaAlarmJournal(jdbc);
        JSONObject state = empty(); JSONArray events = state.getJSONArray("events");
        JSONObject demo = event("demo", false, "2026-10-27T01:00:00Z"); demo.put("demo", true); events.add(demo);
        JSONObject simulation = event("simulation", false, "2026-10-27T01:00:00Z"); simulation.put("dataOrigin", "SIMULATED_TEST"); events.add(simulation);
        JSONObject manual = event("manual", false, "2026-10-27T01:00:00Z"); manual.put("source", "manual_sos"); events.add(manual);
        JSONObject noProof = event("no-proof", false, "2026-10-27T01:00:00Z"); noProof.remove("protocol"); events.add(noProof);
        JSONObject unknownDevice = helmet(); unknownDevice.put("id", "unknown-device"); unknownDevice.remove("source"); state.getJSONArray("devices").add(unknownDevice);
        JSONObject unknownEvent = event("unknown", false, "2026-10-27T01:00:00Z"); unknownEvent.put("deviceId", "unknown-device"); events.add(unknownEvent);
        JSONObject noNumber = helmet(); noNumber.put("id", "missing-number"); noNumber.remove("deviceNumber"); state.getJSONArray("devices").add(noNumber);
        JSONObject missing = event("missing-number", false, "2026-10-27T01:00:00Z"); missing.put("deviceId", "missing-number"); events.add(missing);
        JSONObject mockDevice = belt(); mockDevice.put("id", "mock-device"); mockDevice.put("simulated", true); state.getJSONArray("devices").add(mockDevice);
        JSONObject mockEvent = event("mock-event", true, "2026-10-27T01:00:00Z"); mockEvent.put("deviceId", "mock-device"); events.add(mockEvent);
        events.add(event("real-unknown-code", true, "2026-10-27T01:00:00Z"));
        store.load("guardian", null, () -> state);
        assertEquals(1, journal.highWatermark());
        assertEquals("real-unknown-code", journal.scan(0, 10, both()).items.get(0).getString("eventId"));
        // A later disposition/provenance edit of an existing row cannot create a new export.
        WearableBusinessStore.Snapshot before = store.read("guardian"); before.state.getJSONArray("events").getJSONObject(0).put("demo", false);
        store.save("guardian", before.revision, before.state, null); assertEquals(1, journal.highWatermark());
    }

    @Test void startupBackfillsExistingRealEventsOnceWithoutInventingHistoricLocationOrFirmware() {
        JdbcTemplate jdbc = database(); legacySchema(jdbc);
        JSONObject device = helmet(); device.put("longitude", "112.1"); device.put("latitude", "35.1");
        device.put("locationReportedAt", "2026-10-27T02:00:00Z"); insertLegacy(jdbc, "devices", device);
        JSONObject historic = event("historic", false, "2026-10-25T01:00:00Z");
        historic.put("locationLng", "111.2"); historic.put("locationLat", "34.2"); historic.put("locationReportedAt", "2026-10-25T00:59:00Z");
        insertLegacy(jdbc, "events", historic);
        JSONObject demo = event("historic-demo", false, "2026-10-25T01:01:00Z"); demo.put("demo", true); insertLegacy(jdbc, "events", demo);
        new WearableBusinessStore(jdbc); FudaAlarmJournal journal = new FudaAlarmJournal(jdbc);
        JSONObject item = journal.scan(0, 10, both()).items.get(0);
        assertEquals("historic", item.getString("eventId")); assertEquals("2026-10-25T01:00:00Z", item.getString("occurredAt"));
        assertEquals("111.2", item.getJSONObject("rawEvent").getString("locationLng"));
        assertFalse(item.getJSONObject("device").containsKey("longitude"));
        assertFalse(item.getJSONObject("device").containsKey("firmware")); assertNull(item.get("deviceModel"));
        new WearableBusinessStore(jdbc); journal.backfill();
        assertEquals(1, journal.highWatermark()); assertEquals(item, journal.scan(0, 10, both()).items.get(0));
        assertNotNull(jdbc.queryForObject("SELECT backfill_completed_at FROM fuda_alarm_journal_state WHERE id=1", Long.class));
    }

    @Test void failedBackfillRollsBackItsCounterRowsAndMarkerAndCanBeRetried() {
        JdbcTemplate jdbc = database(); legacySchema(jdbc); insertLegacy(jdbc, "devices", helmet());
        insertLegacy(jdbc, "events", event("historic-1", false, "2026-10-25T01:00:00Z"));
        insertLegacy(jdbc, "events", event("historic-2", false, "2026-10-25T01:01:00Z"));
        AtomicInteger writes = new AtomicInteger();
        JdbcTemplate failing = new JdbcTemplate(jdbc.getDataSource()) {
            @Override public int update(String sql, Object... arguments) {
                if (sql.startsWith("INSERT INTO fuda_alarm_journal (") && writes.incrementAndGet() == 2)
                    throw new IllegalStateException("backfill write failure");
                return super.update(sql, arguments);
            }
        };
        assertThrows(IllegalStateException.class, () -> new WearableBusinessStore(failing));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM fuda_alarm_journal", Integer.class));
        assertEquals(0, new FudaAlarmJournal(jdbc).highWatermark());
        assertNull(jdbc.queryForObject("SELECT backfill_completed_at FROM fuda_alarm_journal_state WHERE id=1", Long.class));
        new WearableBusinessStore(jdbc); assertEquals(2, new FudaAlarmJournal(jdbc).highWatermark());
    }

    @Test void helmetHistoricalBackfillUsesItsFirstImmutableEnvelopeNotLaterDeviceOrReviewValues() {
        JdbcTemplate jdbc = database(); legacySchema(jdbc); new HelmetBusinessJournal(jdbc);
        JSONObject laterDevice = helmet(); laterDevice.put("firmware", "later-firmware"); laterDevice.put("model", "later-model");
        laterDevice.put("longitude", "120"); laterDevice.put("latitude", "40"); laterDevice.put("locationReportedAt", "2026-10-27T02:00:00Z");
        insertLegacy(jdbc, "devices", laterDevice);
        JSONObject old = event("helmet-archived", false, "2026-10-27T02:00:00Z"); old.put("rawAlarmType", "review-changed");
        insertLegacy(jdbc, "events", old);
        JSONObject first = helmetEnvelope("helmet-archived", "2026-10-25T01:00:00Z", "original-code");
        insertHelmetEnvelope(jdbc, first, 1);
        JSONObject later = helmetEnvelope("helmet-archived", "2026-10-26T01:00:00Z", "later-code");
        later.getJSONObject("device").put("firmware", "later-report-firmware"); insertHelmetEnvelope(jdbc, later, 2);
        new WearableBusinessStore(jdbc); FudaAlarmJournal journal = new FudaAlarmJournal(jdbc);
        JSONObject exported = journal.scan(0, 10, both()).items.get(0);
        assertEquals("2026-10-25T01:00:00Z", exported.getString("occurredAt"));
        assertEquals("2026-10-25T01:00:00Z", exported.getString("receivedAt"));
        assertEquals("original-code", exported.getJSONObject("rawEvent").getString("rawAlarmType"));
        assertEquals("original-firmware", exported.getJSONObject("device").getString("firmware"));
        assertEquals("RD-D1+", exported.getString("deviceModel"));
        assertEquals("110.25", exported.getJSONObject("rawEvent").getString("locationLng"));
        assertEquals("110.25", exported.getJSONObject("device").getString("longitude"));
        assertFalse(exported.toJSONString().contains("private-envelope")); assertFalse(exported.toJSONString().contains("later-firmware"));
        jdbc.update("UPDATE wearable_event SET body=? WHERE record_key=?", event("helmet-archived", false, "2026-10-28T00:00:00Z").toJSONString(), "helmet-archived");
        new WearableBusinessStore(jdbc); assertEquals(1, journal.highWatermark()); assertEquals(exported, journal.scan(0, 10, both()).items.get(0));
    }

    @Test void liveDelayedHelmetProjectionFindsAnEnvelopeTableCreatedAfterBusinessStoreStartup() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        store.load("guardian", null, this::empty); new HelmetBusinessJournal(jdbc);
        insertHelmetEnvelope(jdbc, helmetEnvelope("helmet-delayed", "2026-10-24T01:00:00Z", "raw-future-code"), 1);
        append(store, event("helmet-delayed", false, "2026-10-27T02:00:00Z"));
        JSONObject item = new FudaAlarmJournal(jdbc).scan(0, 10, both()).items.get(0);
        assertEquals("2026-10-24T01:00:00Z", item.getString("receivedAt"));
        assertEquals("raw-future-code", item.getJSONObject("rawEvent").getString("rawAlarmType"));
    }

    @Test void caseInsensitiveDatabaseCollationCannotExpandAuthorizationOrFoldEventIdentity() {
        JdbcTemplate jdbc = new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID()
                + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;IGNORECASE=TRUE", "sa", ""));
        WearableBusinessStore store = new WearableBusinessStore(jdbc); store.load("guardian", null, this::empty);
        append(store, event("upper-case-device", false, "2026-10-27T02:00:00Z"));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM fuda_alarm_journal WHERE device_key=?", Integer.class, "HELMET:h-login"));
        FudaAlarmJournal journal = new FudaAlarmJournal(jdbc);
        assertTrue(journal.scan(0, 10, Collections.singleton("HELMET:h-login")).items.isEmpty());
        assertEquals(1, journal.scan(0, 10, Collections.singleton(HELMET_KEY)).items.size());
        JSONObject state = empty();
        state.getJSONArray("events").add(event("Opaque-ID", false, "2026-10-27T02:01:00Z"));
        state.getJSONArray("events").add(event("opaque-id", false, "2026-10-27T02:01:00Z"));
        transaction(jdbc).execute(status -> { journal.appendNew(state, Collections.emptySet(), false); return null; });
        assertEquals(3, journal.highWatermark());
        List<JSONObject> items = journal.scan(1, 10, Collections.singleton(HELMET_KEY)).items;
        assertEquals("Opaque-ID", items.get(0).getString("eventId")); assertEquals("opaque-id", items.get(1).getString("eventId"));
        transaction(jdbc).execute(status -> { journal.appendNew(state, Collections.emptySet(), false); return null; });
        assertEquals(3, journal.highWatermark());
    }

    @Test void delayedReceiptRetainsOriginalDeviceContextAndReceptionTimeAndDiscardsPrivatePacket() {
        JdbcTemplate jdbc = database(); WearableBusinessStore store = new WearableBusinessStore(jdbc);
        store.load("guardian", null, this::empty); FudaAlarmJournal journal = new FudaAlarmJournal(jdbc);
        JSONObject original = belt(); original.put("firmware", "at-reception");
        JSONObject payload = object("raw", object("password", "never-export-raw"), "timestamp", "2026-10-25T01:00:00Z",
                "context", object("device", original, "personName", "private-user"),
                "status", object("longitude", "110.5", "latitude", "30.5", "locationReportedAt", "2026-10-25T01:00:00Z"));
        store.appendDeviceReport("receipt-delayed", "direct-belt", "belt-internal", payload);
        jdbc.update("UPDATE wearable_device_report SET received_at=? WHERE receipt_id=?", Instant.parse("2026-10-25T01:00:01Z").toEpochMilli(), "receipt-delayed");
        assertTrue(store.processReport("receipt-delayed", () -> {
            WearableBusinessStore.Snapshot current = store.read("guardian");
            JSONObject currentDevice = current.state.getJSONArray("devices").getJSONObject(1);
            currentDevice.put("firmware", "later-firmware"); currentDevice.put("longitude", "115"); currentDevice.put("latitude", "36");
            currentDevice.put("locationReportedAt", "2026-10-27T02:00:00Z");
            JSONObject alarm = event("delayed-receipt", true, "2026-10-25T01:00:00Z"); alarm.put("createdAt", "2026-10-27T02:00:00Z");
            current.state.getJSONArray("events").add(alarm); store.save("guardian", current.revision, current.state, null);
        }));
        JSONObject item = journal.scan(0, 10, both()).items.get(0);
        assertEquals("2026-10-25T01:00:01Z", item.getString("receivedAt")); assertEquals("2026-10-25T01:00:00Z", item.getString("occurredAt"));
        assertEquals("at-reception", item.getJSONObject("device").getString("firmware"));
        assertEquals("110.5", item.getJSONObject("device").getString("longitude"));
        assertFalse(item.toJSONString().contains("never-export-raw")); assertFalse(item.toJSONString().contains("private-user"));
        assertFalse(store.processReport("receipt-delayed", () -> fail("duplicate receipt replayed")));
        assertEquals(1, journal.highWatermark());
    }

    @Test void uncommittedAllocationCannotBeSkippedByAConcurrentPollOrLaterCommit() throws Exception {
        JdbcTemplate jdbc = database(); new WearableBusinessStore(jdbc);
        FudaAlarmJournal firstJournal = new FudaAlarmJournal(jdbc), secondJournal = new FudaAlarmJournal(jdbc);
        JSONObject first = empty(), second = empty();
        first.getJSONArray("events").add(event("commit-first", false, "2026-10-27T01:00:00Z"));
        second.getJSONArray("events").add(event("commit-second", true, "2026-10-26T01:00:00Z"));
        CountDownLatch allocatedFirst = new CountDownLatch(1), releaseFirst = new CountDownLatch(1),
                enteredSecond = new CountDownLatch(1), allocatedSecond = new CountDownLatch(1), releaseSecond = new CountDownLatch(1);
        ExecutorService workers = Executors.newFixedThreadPool(2);
        try {
            Future<?> one = workers.submit(() -> transaction(jdbc).execute(status -> {
                firstJournal.appendNew(first, Collections.emptySet(), false); allocatedFirst.countDown(); await(releaseFirst); return null;
            }));
            assertTrue(allocatedFirst.await(5, TimeUnit.SECONDS));
            Future<?> two = workers.submit(() -> transaction(jdbc).execute(status -> {
                enteredSecond.countDown(); secondJournal.appendNew(second, Collections.emptySet(), false);
                allocatedSecond.countDown(); await(releaseSecond); return null;
            }));
            assertTrue(enteredSecond.await(5, TimeUnit.SECONDS));
            assertFalse(allocatedSecond.await(200, TimeUnit.MILLISECONDS));
            assertEquals(0, firstJournal.highWatermark()); assertEquals(0, firstJournal.scan(0, 10, both()).nextSequence);
            releaseFirst.countDown(); one.get(5, TimeUnit.SECONDS); assertTrue(allocatedSecond.await(5, TimeUnit.SECONDS));
            FudaAlarmJournal.AlarmPage committedFirst = firstJournal.scan(0, 10, both());
            assertEquals(1, committedFirst.nextSequence); assertEquals(1, committedFirst.items.size());
            assertEquals("commit-first", committedFirst.items.get(0).getString("eventId"));
            releaseSecond.countDown(); two.get(5, TimeUnit.SECONDS);
            FudaAlarmJournal.AlarmPage committedSecond = firstJournal.scan(committedFirst.nextSequence, 10, both());
            assertEquals("commit-second", committedSecond.items.get(0).getString("eventId")); assertEquals(2, committedSecond.nextSequence);
        } finally { releaseFirst.countDown(); releaseSecond.countDown(); workers.shutdownNow(); }
    }

    @Test void concurrentReplayOfTheSameEventIsIdempotentAfterTheFirstCommit() throws Exception {
        JdbcTemplate jdbc = database(); new WearableBusinessStore(jdbc);
        FudaAlarmJournal one = new FudaAlarmJournal(jdbc), two = new FudaAlarmJournal(jdbc);
        JSONObject state = empty(); state.getJSONArray("events").add(event("concurrent-duplicate", false, "2026-10-27T01:00:00Z"));
        CountDownLatch written = new CountDownLatch(1), release = new CountDownLatch(1), secondStarted = new CountDownLatch(1);
        ExecutorService workers = Executors.newFixedThreadPool(2);
        try {
            Future<?> first = workers.submit(() -> transaction(jdbc).execute(status -> {
                one.appendNew(state, Collections.emptySet(), false); written.countDown(); await(release); return null;
            }));
            assertTrue(written.await(5, TimeUnit.SECONDS));
            Future<?> duplicate = workers.submit(() -> transaction(jdbc).execute(status -> {
                secondStarted.countDown(); two.appendNew(state, Collections.emptySet(), false); return null;
            }));
            assertTrue(secondStarted.await(5, TimeUnit.SECONDS)); release.countDown();
            first.get(5, TimeUnit.SECONDS); duplicate.get(5, TimeUnit.SECONDS);
            assertEquals(1, one.highWatermark()); assertEquals(1, one.scan(0, 10, both()).items.size());
        } finally { release.countDown(); workers.shutdownNow(); }
    }

    private static void await(CountDownLatch latch) {
        try { if (!latch.await(8, TimeUnit.SECONDS)) throw new IllegalStateException("concurrency test timed out"); }
        catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new IllegalStateException(error); }
    }
    private void legacySchema(JdbcTemplate jdbc) {
        new ResourceDatabasePopulator(new ClassPathResource("db/20261026_wearable_business.sql")).execute(jdbc.getDataSource());
        jdbc.update("INSERT INTO wearable_business_meta (namespace,revision,imported_at) VALUES ('guardian',1,1)");
    }
    private void insertLegacy(JdbcTemplate jdbc, String collection, JSONObject row) {
        String table = "events".equals(collection) ? "wearable_event" : "wearable_device_state";
        jdbc.update("INSERT INTO " + table + " (namespace,collection_key,record_key,sort_order,body) VALUES ('guardian',?,?,0,?)",
                collection, row.getString("id"), row.toJSONString());
    }
    private JSONObject helmetEnvelope(String eventId, String at, String code) {
        JSONObject captured = helmet(); captured.put("longitude", "110.25"); captured.put("latitude", "30.25");
        captured.put("locationReportedAt", at); captured.put("coordinateSystem", "GCJ02"); captured.put("locationQuality", "valid");
        captured.put("password", "private-envelope-password");
        return object("eventId", eventId, "deviceId", "helmet-internal", "device", captured, "receivedAt", at,
                "receivedMillis", Instant.parse(at).toEpochMilli(), "act", "ca_sos", "rawType", code, "sourceRecordType", "real_time_alarm",
                "longitude", "110.25", "latitude", "30.25", "coordinateSystem", "GCJ02", "locationQuality", "valid",
                "locationReportedAt", at, "personName", "private-envelope-person", "raw", object("token", "private-envelope-token"));
    }
    private void insertHelmetEnvelope(JdbcTemplate jdbc, JSONObject envelope, long recordId) {
        jdbc.update("INSERT INTO helmet_event_link (event_id,group_key,source_type,source_record_id,device_id,received_at,body) VALUES (?,?,?,?,?,?,?)",
                envelope.getString("eventId"), "test-group", "real_time_alarm", recordId, envelope.getString("deviceId"),
                envelope.getLongValue("receivedMillis"), envelope.toJSONString());
    }
}
