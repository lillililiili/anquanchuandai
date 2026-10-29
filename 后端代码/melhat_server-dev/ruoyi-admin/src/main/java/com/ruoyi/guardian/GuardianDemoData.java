package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.alibaba.fastjson2.JSONArray;
import org.springframework.core.io.ClassPathResource;
import org.springframework.util.StreamUtils;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Objects;
import static com.ruoyi.guardian.WearableModel.*;

/** Conservative provenance migration; the durable business records and their audit evidence stay intact. */
final class GuardianDemoData {
    private static final String ORIGIN = "GUARDIAN_SEED";
    private static final JSONObject SEED = load();
    private static final JSONObject ADMIN_SEED = load("admin-seed.json");
    private GuardianDemoData() {}

    static void mark(JSONObject state) {
        for (Object raw : rows(state, "devices")) {
            JSONObject row = (JSONObject) raw;
            JSONObject original = find(SEED, "devices", row.getString("id"));
            if (confirmed(row) || realEvidence(row) || row.getString("source") != null) continue;
            if (same(row, original, "id", "type", "station", "online", "battery", "video", "updated"))
                markDevice(row, "guardian-seed.json", row.getString("id"));
        }
        for (Object raw : rows(state, "vitals")) {
            JSONObject row = (JSONObject) raw;
            if (row.getBooleanValue("demo")) continue;
            for (Object value : rows(SEED, "vitals")) {
                if (row.equals(value)) {
                    row.put("demo", true); row.put("dataOrigin", ORIGIN); row.put("source", "DEMO_WATCH");
                    break;
                }
            }
        }
        for (String collection : new String[]{"media", "fences", "fenceRecords", "calls", "broadcasts"}) {
            for (Object raw : rows(state, collection)) {
                JSONObject row = (JSONObject) raw;
                if (confirmed(row) || realEvidence(row)) continue;
                JSONObject original = find(SEED, collection, row.getString("id"));
                if (original == null || !row.equals(original)) continue;
                row.put("seedProvenance", object("resource", "guardian-seed.json", "collection", collection, "recordId", row.getString("id"), "version", 1));
                row.put("source", "demo"); row.put("demo", true); row.put("dataOrigin", ORIGIN);
            }
        }
        for (String collection : new String[]{"events", "works"}) {
            for (Object raw : rows(state, collection)) {
                JSONObject row = (JSONObject) raw;
                if (confirmed(row) || realEvidence(row)) continue;
                JSONObject original = find(SEED, collection, row.getString("id"));
                if (original == null) continue;
                if ("events".equals(collection)) {
                    // Older versions assigned lowercase 'device' to every missing source, including these seeds.
                    String source = row.getString("source");
                    if (source != null && !"device".equals(source)) continue;
                    if (!same(row, original, "id", "personId", "deviceId", "workId", "title", "type", "date", "time", "station", "externalId")) continue;
                    if (!same(row.getJSONObject("snapshot"), original.getJSONObject("snapshot"), "personName", "deviceId", "workName")) continue;
                } else if (!same(row, original, "id", "name", "date", "start", "end", "station", "members", "leader", "supervisor", "area", "source")) continue;
                row.put("seedProvenance", object("resource", "guardian-seed.json", "collection", collection,
                        "recordId", row.getString("id"), "originalSourcePresent", row.containsKey("source"),
                        "originalSource", row.get("source"), "version", 1));
                row.put("source", "demo");
                row.put("demo", true);
                row.put("dataOrigin", ORIGIN);
            }
        }
    }

    static boolean confirmed(JSONObject row) {
        if (row == null || !row.getBooleanValue("demo")) return false;
        JSONObject proof = row.getJSONObject("seedProvenance");
        return proof != null && ((ORIGIN.equals(row.getString("dataOrigin")) && "guardian-seed.json".equals(proof.getString("resource")))
                || ("ADMIN_SEED".equals(row.getString("dataOrigin")) && "admin-seed.json".equals(proof.getString("resource"))))
                && Objects.equals(row.getString("id"), proof.getString("recordId")) && proof.getIntValue("version") == 1;
    }

    /** Stable seed identity, never an ID prefix or an unknown device source by itself. */
    static boolean seedAsset(JSONObject row) {
        if (row == null) return false;
        String source = row.getString("source");
        if (source != null && !source.isEmpty() && !"demo".equals(source) && !"DEMO_WATCH".equals(source)) return false;
        if (!confirmed(row) && realEvidence(row)) return false;
        JSONObject original = find(ADMIN_SEED, "devices", row.getString("id"));
        return same(row, original, "id", "type", "code", "sn", "modelId", "manufacturer");
    }

    static void markDevice(JSONObject row, String resource, String originalId) {
        row.put("seedProvenance", object("resource", resource, "collection", "devices", "recordId", row.getString("id"), "originalRecordId", originalId, "version", 1));
        row.put("dataOrigin", "admin-seed.json".equals(resource) ? "ADMIN_SEED" : ORIGIN);
        row.put("demo", true);
        row.put("source", watch(row) ? "DEMO_WATCH" : "demo");
    }

    static boolean watch(JSONObject row) { return row != null && ("W".equals(row.getString("type")) || "WATCH".equals(row.getString("type"))); }

    static boolean demoDevice(JSONObject row) {
        if (row == null) return false;
        String source = row.getString("source");
        if (source != null && !source.isEmpty() && !"demo".equals(source) && !"DEMO_WATCH".equals(source)) return false;
        boolean seeded = seedAsset(row) || confirmed(row) && "devices".equals(row.getJSONObject("seedProvenance").getString("collection"));
        if (!seeded) return false;
        JSONObject proof = row.getJSONObject("seedProvenance");
        String originalId = proof != null && proof.getString("originalRecordId") != null ? proof.getString("originalRecordId") : row.getString("id");
        // Keep one existing simulation in the test site, without generating or reassigning a watch.
        return !watch(row) || !"RL-W001".equals(originalId)
                || !("site-1".equals(row.getString("siteId")) || "S1".equals(row.getString("station")));
    }

    static boolean simulatedVital(JSONObject row) {
        return row != null && row.getBooleanValue("demo") && ORIGIN.equals(row.getString("dataOrigin")) && "DEMO_WATCH".equals(row.getString("source"));
    }

    /** Return a read projection; archived seed rows and their history stay in durable storage. */
    static JSONObject operationalLedger(JSONObject source, boolean demoMode) {
        if (source == null) return null;
        JSONObject out = copy(source);
        java.util.Set<String> hidden = new java.util.HashSet<>();
        JSONArray devices = new JSONArray();
        for (Object raw : rows(out, "devices")) {
            JSONObject row = (JSONObject) raw;
            if (seedAsset(row)) markDevice(row, "admin-seed.json", row.getString("id"));
            if (!demoMode && demoDevice(row)) hidden.add(row.getString("id")); else devices.add(row);
        }
        out.put("devices", devices);
        for (String key : new String[]{"assignments", "history"}) {
            JSONArray kept = new JSONArray();
            for (Object raw : rows(out, key)) if (!hidden.contains(((JSONObject) raw).getString("deviceId"))) kept.add(raw);
            out.put(key, kept);
        }
        return out;
    }

    private static boolean realEvidence(JSONObject row) {
        for (String key : new String[]{"protocol", "sourceKey", "sourceRecordId", "sourceRecordType", "sourceRecords", "dataOrigin"}) {
            Object value = row.get(key);
            if (value != null && !String.valueOf(value).trim().isEmpty()) return true;
        }
        return false;
    }

    private static boolean same(JSONObject row, JSONObject original, String... fields) {
        if (row == null || original == null) return false;
        for (String field : fields) if (!Objects.equals(row.get(field), original.get(field))) return false;
        return true;
    }

    private static JSONObject load() {
        return load("guardian-seed.json");
    }
    private static JSONObject load(String resource) {
        try (InputStream stream = new ClassPathResource(resource).getInputStream()) {
            return JSONObject.parseObject(StreamUtils.copyToString(stream, StandardCharsets.UTF_8));
        } catch (Exception failure) { throw new IllegalStateException("无法核对示例资料来源", failure); }
    }
}
