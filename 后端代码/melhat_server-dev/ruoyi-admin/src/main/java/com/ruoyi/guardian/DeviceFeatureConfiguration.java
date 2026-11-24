package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Maintained feature status and legacy protocol mappings are stored separately. */
final class DeviceFeatureConfiguration {
    static final Set<String> BELT_ALARMS = new LinkedHashSet<>(Arrays.asList("doubleRelease", "lowHook", "proximity", "temperature", "silent"));
    static final Set<String> BELT_OPTIONS = new LinkedHashSet<>(Arrays.asList("doubleRelease", "lowHook", "proximity", "temperature", "silent", "rtk", "indoorLocation"));
    private static final Set<String> FIELDS = new HashSet<>(Arrays.asList("feature", "support", "verification", "evidence", "positiveValue", "negativeValue", "alarmCodes"));
    private static final Set<String> STATUS_FIELDS = new HashSet<>(Arrays.asList("feature", "support", "connection", "availability"));

    static Set<String> keys(JSONObject device) {
        Set<String> keys = new LinkedHashSet<>();
        String source = device.getString("source");
        if (!Arrays.asList("DIRECT_HELMET", "DIRECT_BELT", "SPLIT_HELMET").contains(source)) return keys;
        Collections.addAll(keys, "battery", "wear", "location", "alarm", "sos");
        if ("DIRECT_BELT".equals(source)) { Collections.addAll(keys, "hooks", "height"); keys.addAll(BELT_OPTIONS); }
        else Collections.addAll(keys, "video", "videoCall", "photo", "recording", "voice", "broadcast");
        if ("SPLIT_HELMET".equals(source)) { keys.remove("wear"); Collections.addAll(keys, "pressure", "temperature", "storage"); }
        return keys;
    }

    static JSONObject entry(JSONObject device, String key) {
        JSONObject all = device.getJSONObject("featureConfiguration");
        JSONObject configured = all == null ? null : all.getJSONObject(key);
        // Manual list statuses do not replace observed sensor or command readiness.
        return configured != null && (configured.containsKey("support") || configured.containsKey("verification")) ? configured : null;
    }

    static JSONObject update(JSONObject device, JSONObject input, JSONObject actor) {
        if ("SCRAPPED".equals(device.getString("lifecycle"))) throw fail("报废设备的功能配置只读");
        if (input != null && (input.containsKey("connection") || input.containsKey("availability"))) return updateStatus(device, input, actor);
        if (input == null || !FIELDS.containsAll(input.keySet())) throw fail("仅能维护功能支持、确认依据、状态码及告警编号");
        String key = string(input, "feature", 40);
        if (!keys(device).contains(key)) throw fail("当前设备不提供该功能的配置");
        String support = string(input, "support", 20), verification = string(input, "verification", 20);
        if (!Arrays.asList("DEFAULT", "SUPPORTED", "UNSUPPORTED").contains(support)
                || !Arrays.asList("DEFAULT", "PENDING", "VERIFIED").contains(verification)) throw fail("功能支持或确认状态无效");
        String evidence = string(input, "evidence", 500);
        if (evidence.isEmpty()) throw fail("请填写本次配置的确认依据或修改原因");
        if ("UNSUPPORTED".equals(support) && "VERIFIED".equals(verification)) throw fail("不支持的功能不能确认为通过");
        String positive = string(input, "positiveValue", 16), negative = string(input, "negativeValue", 16);
        boolean mapping = "DIRECT_BELT".equals(device.getString("source")) && Arrays.asList("wear", "hooks").contains(key);
        if ((!positive.isEmpty() || !negative.isEmpty()) && (!mapping || !positive.matches("[0-9]{1,8}") || !negative.matches("[0-9]{1,8}") || positive.equals(negative)))
            throw fail("状态码须为两个不同的非负整数，且仅用于安全带佩戴或双钩");
        if (mapping && "VERIFIED".equals(verification) && positive.isEmpty()) throw fail("确认通过前，请填写实际验证的正反两种状态码");
        Object rawCodes = input.get("alarmCodes");
        if (rawCodes != null && !(rawCodes instanceof JSONArray)) throw fail("告警编号格式无效");
        JSONArray codes = rawCodes == null ? new JSONArray() : (JSONArray) rawCodes;
        if (codes.size() > 12 || !codes.isEmpty() && !("DIRECT_BELT".equals(device.getString("source")) && BELT_ALARMS.contains(key))) throw fail("该功能不接受告警编号映射");
        Set<String> unique = new LinkedHashSet<>();
        for (Object code : codes) {
            if (!(code instanceof String) || !((String)code).matches("[0-9]{1,8}") || !unique.add((String)code)) throw fail("告警编号须为不重复的非负整数字符串");
        }
        if ("DIRECT_BELT".equals(device.getString("source")) && BELT_ALARMS.contains(key) && "VERIFIED".equals(verification) && unique.isEmpty()) throw fail("请先填写与本机实际报文对应的告警编号");
        JSONObject all = device.getJSONObject("featureConfiguration") == null ? new JSONObject() : copy(device.getJSONObject("featureConfiguration"));
        for (String other : all.keySet()) {
            if (other.equals(key)) continue;
            JSONArray used = all.getJSONObject(other).getJSONArray("alarmCodes");
            if (used != null) for (Object code : used) if (unique.contains(code)) throw fail("同一个告警编号不能对应多项功能");
        }
        JSONObject configured = object("support", support, "verification", verification, "evidence", evidence,
                "positiveValue", positive, "negativeValue", negative, "alarmCodes", new JSONArray(unique),
                "updatedAt", java.time.Instant.now().toString(), "updatedBy", actor.getString("id"), "updatedByName", actor.getString("name"));
        JSONObject previous = all.getJSONObject(key);
        if (previous != null && previous.getJSONObject("status") != null) configured.put("status", copy(previous.getJSONObject("status")));
        all.put(key, configured);
        JSONObject result = copy(device);
        result.put("featureConfiguration", all);
        result.put("version", device.getIntValue("version") + 1);
        return result;
    }

    private static JSONObject updateStatus(JSONObject device, JSONObject input, JSONObject actor) {
        if (!STATUS_FIELDS.equals(input.keySet())) throw fail("请仅提交设备支持、连接状态和可用状态");
        String key = string(input, "feature", 40);
        if (!keys(device).contains(key)) throw fail("当前设备不提供该功能的配置");
        String support = string(input, "support", 20), connection = string(input, "connection", 20), availability = string(input, "availability", 20);
        if (!Arrays.asList("DEFAULT", "SUPPORTED", "UNSUPPORTED", "PENDING").contains(support)
                || !Arrays.asList("DEFAULT", "CONNECTED", "NOT_CONNECTED", "PENDING").contains(connection)
                || !Arrays.asList("DEFAULT", "AVAILABLE", "UNAVAILABLE", "PENDING").contains(availability)) throw fail("功能状态无效");
        if ("AVAILABLE".equals(availability) && !("SUPPORTED".equals(support) && "CONNECTED".equals(connection)))
            throw fail("设为当前可用时，请同时选择支持和已连接");
        JSONObject all = device.getJSONObject("featureConfiguration") == null ? new JSONObject() : copy(device.getJSONObject("featureConfiguration"));
        JSONObject configured = all.getJSONObject(key) == null ? new JSONObject() : copy(all.getJSONObject(key));
        configured.put("status", object("support", support, "connection", connection, "availability", availability));
        configured.put("updatedAt", java.time.Instant.now().toString());
        configured.put("updatedBy", actor.getString("id"));
        configured.put("updatedByName", actor.getString("name"));
        all.put(key, configured);
        JSONObject result = copy(device);
        result.put("featureConfiguration", all);
        result.put("version", device.getIntValue("version") + 1);
        return result;
    }

    static void applyMappings(JSONObject device) {
        if (!"DIRECT_BELT".equals(device.getString("source"))) return;
        boolean fresh = (device.getBooleanValue("online") || "ONLINE".equals(device.getString("communication"))) && "CURRENT".equals(device.getString("telemetryFreshness"));
        for (String key : Arrays.asList("wear", "hooks")) {
            JSONObject config = entry(device, key);
            if (config == null || text(config, "positiveValue").isEmpty() && "DEFAULT".equals(config.getString("verification")) && !"UNSUPPORTED".equals(config.getString("support"))) continue;
            boolean confirmed = !text(config, "positiveValue").isEmpty() && "VERIFIED".equals(config.getString("verification")) && !"UNSUPPORTED".equals(config.getString("support"));
            device.put("wear".equals(key) ? "wearMappingConfirmed" : "hookMappingConfirmed", confirmed);
            if ("wear".equals(key)) device.put("worn", confirmed && fresh ? mapped(device.getString("isWeared"), config) : null);
            else {
                device.put("hookAEngaged", confirmed && fresh ? mapped(device.getString("hangerAStatus"), config) : null);
                device.put("hookBEngaged", confirmed && fresh ? mapped(device.getString("hangerBStatus"), config) : null);
            }
        }
    }

    private static Boolean mapped(String raw, JSONObject config) {
        return raw == null ? null : raw.equals(config.getString("positiveValue")) ? Boolean.TRUE : raw.equals(config.getString("negativeValue")) ? Boolean.FALSE : null;
    }

    static String alarmFeature(JSONObject device, String code) {
        for (String key : BELT_ALARMS) {
            JSONObject config = entry(device, key);
            if (config != null && "SUPPORTED".equals(config.getString("support")) && "VERIFIED".equals(config.getString("verification"))
                    && config.getJSONArray("alarmCodes") != null && config.getJSONArray("alarmCodes").contains(code)) return key;
        }
        return null;
    }

    static String alarmTitle(String feature) {
        if ("doubleRelease".equals(feature)) return "安全带防双解告警";
        if ("lowHook".equals(feature)) return "安全带高低挂告警";
        if ("proximity".equals(feature)) return "安全带近电告警";
        if ("temperature".equals(feature)) return "安全带温度告警";
        if ("silent".equals(feature)) return "安全带静默告警";
        return "安全带告警";
    }

    private static String string(JSONObject input, String key, int maximum) {
        Object raw = input.get(key);
        if (raw == null) return "";
        if (!(raw instanceof String) || ((String)raw).trim().length() > maximum) throw fail("配置字段类型或长度无效：" + key);
        return ((String)raw).trim();
    }
    private static AdminQueryService.QueryFailed fail(String message) { return AdminQueryService.fail(400, "FEATURE_CONFIG_INVALID", message); }
}
