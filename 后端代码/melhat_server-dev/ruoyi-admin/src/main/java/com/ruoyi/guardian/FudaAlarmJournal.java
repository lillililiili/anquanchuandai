package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.context.annotation.DependsOn;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Immutable device-alarm evidence; business review operations are never export events. */
@Repository
@DependsOn("wearableBusinessStore")
public class FudaAlarmJournal {
    public static final class AlarmPage {
        public final List<JSONObject> items;
        public final long nextSequence;
        public final boolean hasMore;
        public AlarmPage(List<JSONObject> items, long nextSequence, boolean hasMore) {
            this.items = items; this.nextSequence = nextSequence; this.hasMore = hasMore;
        }
    }

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");
    private static final Pattern SOURCE_TIME = Pattern.compile("(\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:\\d{2})?)$");
    // Strict allowlists: never copy raw packets, personal attribution, passwords, or review content.
    private static final String[] EVENT_FIELDS = {"id", "source", "protocol", "rawAlarmType", "sourceKey",
            "sourceRecordType", "title", "type", "date", "time", "createdAt", "occurredAt", "receivedAt",
            "locationLng", "locationLat", "longitude", "latitude", "coordinateSystem", "locationQuality",
            "locationSource", "accuracyMeters", "locationReportedAt", "altitude", "gpsAltitude", "speed", "direction"};
    private static final String[] DEVICE_FIELDS = {"id", "source", "type", "deviceNumber", "portalDeviceId",
            "code", "sn", "deviceModel", "model", "modelName", "modelId", "firmware", "sourceFirmware"};
    private static final String[] LOCATION_FIELDS = {"longitude", "latitude", "coordinateSystem", "locationQuality",
            "locationSource", "accuracyMeters", "locationReportedAt", "altitude", "gpsAltitude", "speed", "direction"};
    private final JdbcTemplate jdbc;
    private final TransactionTemplate independent;
    private final ThreadLocal<JSONObject> receiptEvidence = new ThreadLocal<>();

    /** Schema initialization belongs to WearableBusinessStore startup, not to API reads. */
    public FudaAlarmJournal(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        this.independent = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        this.independent.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public void initialize() {
        new ResourceDatabasePopulator(new ClassPathResource("db/20261027_fuda_alarm_journal.sql"))
                .execute(jdbc.getDataSource());
        backfill();
    }

    /** One independent startup transaction; retries and restarts cannot duplicate an event. */
    public void backfill() {
        if (TransactionSynchronizationManager.isActualTransactionActive())
            throw new IllegalStateException("历史报警初始化必须在业务事务之外执行");
        independent.execute(status -> {
            // Same lock order as a business save: namespace, then the journal counter.
            List<String> initialized = jdbc.query("SELECT namespace FROM wearable_business_meta WHERE namespace='guardian' FOR UPDATE",
                    (rs, n) -> rs.getString(1));
            if (initialized.isEmpty()) return null;
            JSONObject counter = counterForUpdate();
            if (counter.get("backfillCompletedAt") != null) return null;
            JSONObject state = new JSONObject();
            state.put("devices", new JSONArray(jdbc.query("SELECT body FROM wearable_device_state WHERE namespace='guardian' AND collection_key='devices' ORDER BY record_key",
                    (rs, n) -> JSONObject.parseObject(rs.getString(1)))));
            state.put("events", new JSONArray(jdbc.query("SELECT body FROM wearable_event WHERE namespace='guardian' AND collection_key='events' ORDER BY observed_at,record_key",
                    (rs, n) -> JSONObject.parseObject(rs.getString(1)))));
            appendCandidates(state, Collections.emptySet(), true, counter);
            jdbc.update("UPDATE fuda_alarm_journal_state SET backfill_completed_at=? WHERE id=1", System.currentTimeMillis());
            return null;
        });
    }

    /** Package-private: called only within the transaction that first persists these business events. */
    void appendNew(JSONObject state, Set<String> previousEventIds, boolean historicalImport) {
        if (!TransactionSynchronizationManager.isActualTransactionActive())
            throw new IllegalStateException("报警导出日志必须与业务事件处于同一事务");
        JSONArray events = state.getJSONArray("events");
        if (events == null || events.stream().noneMatch(raw -> raw instanceof JSONObject
                && !previousEventIds.contains(((JSONObject) raw).getString("id")))) return;
        appendCandidates(state, previousEventIds, historicalImport, counterForUpdate());
    }

    /** Keep only reception-time attribution while the existing durable receipt is being applied. */
    void duringReceipt(JSONObject receipt, Runnable handler) {
        JSONObject previous = receiptEvidence.get();
        try {
            JSONObject payload = receipt.getJSONObject("payload");
            JSONObject evidence = new JSONObject();
            evidence.put("protocol", receipt.get("protocol")); evidence.put("deviceId", receipt.get("deviceId"));
            evidence.put("receivedAt", Instant.ofEpochMilli(receipt.getLongValue("receivedMillis")).toString());
            if (payload != null) {
                JSONObject context = payload.getJSONObject("context");
                evidence.put("device", context == null ? null : context.getJSONObject("device"));
                evidence.put("status", payload.getJSONObject("status"));
                evidence.put("occurredAt", payload.get("timestamp"));
            }
            receiptEvidence.set(evidence);
            handler.run();
        } finally {
            if (previous == null) receiptEvidence.remove(); else receiptEvidence.set(previous);
        }
    }

    private void appendCandidates(JSONObject state, Set<String> previousEventIds, boolean historical, JSONObject counter) {
        Map<String, JSONObject> devices = new HashMap<>();
        JSONArray listed = state.getJSONArray("devices");
        if (listed != null) for (Object raw : listed) if (raw instanceof JSONObject) {
            JSONObject device = (JSONObject) raw;
            devices.put(device.getString("id"), device);
        }
        long sequence = counter.getLongValue("sequence");
        JSONArray events = state.getJSONArray("events");
        if (events != null) for (Object raw : events) {
            if (!(raw instanceof JSONObject)) continue;
            JSONObject event = (JSONObject) raw;
            String eventId = event.getString("id");
            if (previousEventIds.contains(eventId)) continue;
            JSONObject receipt = historical ? null : receiptEvidence.get();
            JSONObject item = snapshot(event, devices.get(event.getString("deviceId")), historical, receipt, initialHelmetEvidence(event));
            if (item == null) continue;
            String eventHash = identityHash(eventId);
            // A current read also works when an outer MySQL transaction established an older
            // REPEATABLE_READ snapshot before waiting for the counter lock.
            List<String> existing = jdbc.query("SELECT event_id FROM fuda_alarm_journal WHERE event_hash=? FOR UPDATE",
                    (rs, n) -> rs.getString(1), eventHash);
            if (!existing.isEmpty()) {
                if (!eventId.equals(existing.get(0))) throw new IllegalStateException("报警标识摘要冲突");
                continue;
            }
            // The row lock is held until the enclosing business transaction commits. A later
            // writer cannot allocate a higher visible sequence ahead of this transaction.
            item.put("exportSequence", ++sequence);
            String deviceKey = item.getString("deviceType") + ":" + item.getString("deviceId");
            jdbc.update("INSERT INTO fuda_alarm_journal (export_sequence,event_id,event_hash,device_key,scope_hash,internal_device_id,recorded_at,body) VALUES (?,?,?,?,?,?,?,?)",
                    sequence, eventId, eventHash, deviceKey, identityHash(deviceKey),
                    item.getString("internalDeviceId"), System.currentTimeMillis(), item.toJSONString());
        }
        if (sequence != counter.getLongValue("sequence"))
            jdbc.update("UPDATE fuda_alarm_journal_state SET committed_sequence=? WHERE id=1", sequence);
    }

    /** The original helmet envelope outlives delayed business projection and later review. */
    private JSONObject initialHelmetEvidence(JSONObject event) {
        if (!"direct-helmet".equals(event.getString("protocol"))) return null;
        Boolean exists = jdbc.execute((ConnectionCallback<Boolean>) connection -> {
            try (java.sql.ResultSet tables = connection.getMetaData().getTables(connection.getCatalog(), null, "helmet_event_link", null)) {
                return tables.next();
            }
        });
        if (!Boolean.TRUE.equals(exists)) return null;
        // The older source table can use a case-insensitive collation. Match the exact opaque
        // identity again before choosing its first envelope; do not take another event's row.
        List<JSONObject> rows = jdbc.query("SELECT event_id,body FROM helmet_event_link WHERE event_id=? ORDER BY received_at,source_type,source_record_id",
                (rs, n) -> event.getString("id").equals(rs.getString(1)) ? JSONObject.parseObject(rs.getString(2)) : null, event.getString("id"));
        rows.removeIf(Objects::isNull);
        if (rows.isEmpty()) return null;
        JSONObject first = rows.get(0);
        if (first.getJSONObject("initialReport") != null) first = first.getJSONObject("initialReport");
        return Objects.equals(first.getString("eventId"), event.getString("id"))
                && Objects.equals(first.getString("deviceId"), event.getString("deviceId")) ? first : null;
    }

    private JSONObject counterForUpdate() {
        return jdbc.queryForObject("SELECT committed_sequence,retained_floor,backfill_completed_at FROM fuda_alarm_journal_state WHERE id=1 FOR UPDATE",
                (rs, n) -> {
                    JSONObject row = new JSONObject(); row.put("sequence", rs.getLong(1)); row.put("retainedFloor", rs.getLong(2));
                    long completed = rs.getLong(3); row.put("backfillCompletedAt", rs.wasNull() ? null : completed); return row;
                });
    }

    public long retainedFloor() {
        return jdbc.queryForObject("SELECT retained_floor FROM fuda_alarm_journal_state WHERE id=1", Long.class);
    }

    /** Reads only the committed counter. An uncommitted allocation is never a polling watermark. */
    public long highWatermark() {
        return jdbc.queryForObject("SELECT committed_sequence FROM fuda_alarm_journal_state WHERE id=1", Long.class);
    }

    /** Scope is applied before pagination. Empty authorized ranges still advance to the stable watermark. */
    public AlarmPage scan(long after, int limit, Set<String> authorizedKeys) {
        if (after < 0 || limit < 1 || limit > 1000 || authorizedKeys == null)
            throw new IllegalArgumentException("报警日志分页参数无效");
        long floor = retainedFloor(), watermark = highWatermark();
        if (after < floor || after > watermark) throw new IllegalArgumentException("报警游标已失效或超出已提交水位");
        if (authorizedKeys.isEmpty()) return new AlarmPage(Collections.emptyList(), watermark, false);
        List<Object> arguments = new ArrayList<>(); arguments.add(after); arguments.add(watermark);
        List<String> keys = new ArrayList<>(); for (String key : authorizedKeys) keys.add(identityHash(key));
        Collections.sort(keys); arguments.addAll(keys); arguments.add(limit + 1);
        String placeholders = String.join(",", Collections.nCopies(keys.size(), "?"));
        List<JSONObject> selected = jdbc.query("SELECT body FROM fuda_alarm_journal WHERE export_sequence>? AND export_sequence<=? AND scope_hash IN ("
                        + placeholders + ") ORDER BY export_sequence LIMIT ?",
                (rs, n) -> JSONObject.parseObject(rs.getString(1)), arguments.toArray());
        boolean more = selected.size() > limit;
        if (more) selected.remove(selected.size() - 1);
        long next = more ? selected.get(selected.size() - 1).getLongValue("exportSequence") : watermark;
        return new AlarmPage(selected, next, more);
    }

    private static JSONObject snapshot(JSONObject event, JSONObject registered, boolean historical, JSONObject receipt, JSONObject helmetEnvelope) {
        boolean matchingReceipt = event != null && receipt != null
                && Objects.equals(event.getString("deviceId"), receipt.getString("deviceId"))
                && Objects.equals(event.getString("protocol"), receipt.getString("protocol"));
        // Belt receipt replay can happen much later than arrival; its captured device, rather
        // than the current ledger projection, proves the original identity and known position.
        boolean capturedBeltReceipt = matchingReceipt && "direct-belt".equals(receipt.getString("protocol"));
        if (capturedBeltReceipt && receipt.getJSONObject("device") != null) {
            registered = JSONObject.parseObject(receipt.getJSONObject("device").toJSONString());
            registered.putAll(whitelist(receipt.getJSONObject("status"), LOCATION_FIELDS));
        }
        boolean capturedHelmet = helmetEnvelope != null && helmetEnvelope.getJSONObject("device") != null;
        if (capturedHelmet) registered = helmetEnvelope.getJSONObject("device");
        if (event == null || registered == null || simulated(event) || simulated(registered)
                || !"device".equals(event.getString("source"))) return null;
        String source = registered.getString("source"), type = registered.getString("type");
        boolean helmet = "DIRECT_HELMET".equals(source) && ("H".equals(type) || "HELMET".equals(type));
        boolean belt = "DIRECT_BELT".equals(source) && ("B".equals(type) || "BELT".equals(type));
        if (!helmet && !belt) return null;
        String id = clean(event.getString("id")), internalId = clean(event.getString("deviceId"));
        if (id == null || id.length() > 128 || internalId == null || internalId.length() > 128) return null;
        JSONObject captured = event.getJSONObject("snapshot");
        if (simulated(captured)) return null;
        String capturedNumber = captured == null || capturedHelmet ? null : clean(captured.getString("deviceNumber"));
        String number = capturedNumber != null ? capturedNumber : first(registered, "deviceNumber", "portalDeviceId");
        if (number == null || !number.matches("[A-Za-z0-9._-]{1,64}")) return null;
        String protocol = event.getString("protocol"), sourceKey = event.getString("sourceKey");
        String expected = helmet ? "direct-helmet" : "direct-belt";
        // Old direct-helmet records may predate protocol, but require their real device-origin key.
        boolean legacyKey = helmet && sourceKey != null && (sourceKey.startsWith(internalId + ":alarm:")
                || sourceKey.startsWith(internalId + ":sos:"));
        if (!expected.equals(protocol) && !(protocol == null && legacyKey)) return null;
        JSONObject safeEvent = whitelist(event, EVENT_FIELDS);
        if (helmetEnvelope != null) {
            safeEvent.put("rawAlarmType", helmetEnvelope.get("rawType"));
            safeEvent.put("sourceRecordType", helmetEnvelope.get("sourceRecordType"));
            safeEvent.put("type", "ca_sip_sos".equals(helmetEnvelope.getString("act")) ? "人员求助" : "设备通信");
            safeEvent.put("locationLng", helmetEnvelope.get("longitude")); safeEvent.put("locationLat", helmetEnvelope.get("latitude"));
            for (String field : new String[]{"coordinateSystem", "locationQuality", "locationSource", "accuracyMeters", "locationReportedAt"})
                if (scalar(helmetEnvelope.get(field))) safeEvent.put(field, helmetEnvelope.get(field));
        }
        JSONObject safeDevice = whitelist(registered, DEVICE_FIELDS);
        if (capturedHelmet && clean(helmetEnvelope.getString("firmware")) != null)
            safeDevice.put("firmware", helmetEnvelope.getString("firmware"));
        // A historical device's current firmware/model/location is not evidence of its past state.
        if (historical && !capturedHelmet) for (String field : new String[]{"deviceModel", "model", "modelName", "modelId", "firmware", "sourceFirmware"}) safeDevice.remove(field);
        if (captured != null && !capturedHelmet) for (String field : DEVICE_FIELDS) if (!"id".equals(field) && captured.containsKey(field)) {
            Object value = captured.get(field); if (scalar(value)) safeDevice.put(field, value);
        }
        safeDevice.put("deviceNumber", number);
        String received = normalized(first(event, "receivedAt", "createdAt"));
        if (capturedBeltReceipt) received = normalized(receipt.getString("receivedAt"));
        if (helmetEnvelope != null) received = normalized(helmetEnvelope.getString("receivedAt"));
        String occurred = normalized(first(event, "occurredAt", "timestamp", "deviceReportedAt"));
        if (helmetEnvelope != null) occurred = received;
        if (occurred == null && capturedBeltReceipt) occurred = normalized(receipt.getString("occurredAt"));
        if (occurred == null && sourceKey != null) {
            Matcher match = SOURCE_TIME.matcher(sourceKey); if (match.find()) occurred = normalized(match.group(1));
        }
        // Direct helmets have no device event clock. Do not invent one from the current time.
        if (occurred == null && helmet) occurred = received;
        if (occurred == null) occurred = normalized(joinedEventTime(event));
        String reported = normalized(registered.getString("locationReportedAt"));
        // An alarm snapshot may use an already known fix, with its original fix time. It must
        // never gain a later position during backfill or delayed delivery.
        if ((!historical || capturedHelmet) && reported != null && received != null && !Instant.parse(reported).isAfter(Instant.parse(received)))
            safeDevice.putAll(whitelist(registered, LOCATION_FIELDS));
        JSONObject item = new JSONObject();
        item.put("eventId", id); item.put("deviceType", helmet ? "HELMET" : "SAFETY_BELT");
        item.put("deviceId", number); item.put("internalDeviceId", internalId);
        item.put("deviceModel", first(safeDevice, "deviceModel", "model", "modelName"));
        item.put("occurredAt", occurred); item.put("receivedAt", received);
        item.put("rawEvent", safeEvent); item.put("device", safeDevice);
        return item;
    }

    private static String joinedEventTime(JSONObject event) {
        String date = clean(event.getString("date")), time = clean(event.getString("time"));
        return date == null || time == null ? null : date + " " + time;
    }

    private static String normalized(String text) {
        if (text == null) return null;
        try { return Instant.parse(text).toString(); } catch (RuntimeException ignored) { }
        try { return java.time.OffsetDateTime.parse(text).toInstant().toString(); } catch (RuntimeException ignored) { }
        try {
            String value = text.replace('T', ' ');
            DateTimeFormatter formatter = DateTimeFormatter.ofPattern(value.length() == 16 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd HH:mm:ss[.SSS]");
            return LocalDateTime.parse(value, formatter).atZone(BUSINESS_ZONE).toInstant().toString();
        } catch (RuntimeException ignored) { return null; }
    }

    private static JSONObject whitelist(JSONObject source, String[] fields) {
        JSONObject safe = new JSONObject();
        if (source != null) for (String field : fields) if (source.containsKey(field) && scalar(source.get(field))) safe.put(field, source.get(field));
        return safe;
    }
    private static boolean scalar(Object value) { return value == null || value instanceof String || value instanceof Number || value instanceof Boolean; }
    private static String first(JSONObject source, String... fields) {
        if (source != null) for (String field : fields) { String value = clean(source.getString(field)); if (value != null) return value; }
        return null;
    }
    private static String clean(String text) { return text == null || text.trim().isEmpty() ? null : text.trim(); }
    /** Hash exact opaque identities so a case-insensitive SQL collation cannot fold them. */
    private static String identityHash(String key) {
        if (key == null) throw new IllegalArgumentException("缺少报警或授权设备标识");
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(key.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder(64);
            for (byte value : bytes) result.append(String.format(Locale.ROOT, "%02x", value & 255));
            return result.toString();
        } catch (java.security.NoSuchAlgorithmException error) { throw new IllegalStateException(error); }
    }
    private static boolean simulated(JSONObject row) {
        if (row == null) return false;
        for (String flag : new String[]{"demo", "isDemo", "simulated", "isSimulated", "simulation", "mock"})
            if (Boolean.TRUE.equals(row.get(flag)) || "true".equalsIgnoreCase(String.valueOf(row.get(flag)))) return true;
        if (row.get("seedProvenance") != null) return true;
        for (String field : new String[]{"source", "dataOrigin", "protocol"}) {
            String value = row.getString(field); if (value == null) continue;
            value = value.toUpperCase(Locale.ROOT);
            if (value.contains("DEMO") || value.contains("MOCK") || value.contains("SIMULAT") || value.contains("SEED")) return true;
        }
        return false;
    }
}
