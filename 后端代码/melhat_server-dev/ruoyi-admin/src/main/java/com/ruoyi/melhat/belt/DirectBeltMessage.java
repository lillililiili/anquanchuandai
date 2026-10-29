package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import java.math.BigDecimal;
import java.time.Instant;

/** Manufacturer belt fields are top-level, including imei and capitalized height names. */
public final class DirectBeltMessage {
    public final String act, deviceId, alarmType, deviceReportedAt;
    public final JSONObject telemetry = new JSONObject();

    private DirectBeltMessage(JSONObject data) {
        act = text(data, "act", 64);
        if (act == null) throw new IllegalArgumentException("缺少 act");
        String id = identity(data, "device_id"), imei = identity(data, "imei");
        if (id != null && imei != null && !id.equals(imei)) throw new IllegalArgumentException("device_id 与 imei 不一致");
        deviceId = id == null ? imei : id;
        alarmType = text(data, "type", 64);
        deviceReportedAt = timestamp(text(data, "timestamp", 32));
        put("deviceReportedAt", deviceReportedAt);
        put("battery", number(data, "bat_l", 0, 100));
        put("isWeared", state(data, "is_weared"));
        put("hangerAStatus", state(data, "hanger_a_status", true));
        put("hangerBStatus", state(data, "hanger_b_status", true));
        put("ignoreHookAlarm", state(data, "IgnoreHookAlarm"));
        // Altitude and Relative_altitude are distinct in the supplied real-device logs.
        put("altitude", number(data, "Altitude", -100000, 100000));
        put("gpsAltitude", number(data, "altitude", -100000, 100000));
        BigDecimal relative = number(data, "Relative_altitude", -100000, 100000);
        if (relative == null) relative = number(data, "relative_altitude", -100000, 100000);
        put("relativeAltitude", relative);
        put("inUse", text(data, "in_use", 8));
        put("networkType", text(data, "net_type", 8));
        put("networkStrength", text(data, "net_strenth", 8));
        BigDecimal lat = number(data, "x_point", -90, 90), lon = number(data, "y_point", -180, 180);
        if ((lat == null) != (lon == null)) throw new IllegalArgumentException("经纬度必须同时提供");
        String gps=text(data,"gps",8);
        boolean cached="4".equals(gps)||"9".equals(gps),network="5".equals(gps)||"6".equals(gps);
        if (lat != null && !(lat.signum() == 0 && lon.signum() == 0) && !cached
                && (!"-1".equals(text(data,"gps_level",8))||network)) {
            put("locationSource","1".equals(gps)?"GNSS":"5".equals(gps)?"WIFI":"6".equals(gps)?"CELL":"UNKNOWN");
            put("coordinateSystem","UNKNOWN");put("locationQuality","unknown");
            put("accuracyMeters",number(data,"c_accuracy",0,1000000));
            put("locationTimeBasis","RECEIVED_AT");
            put("latitude", lat.toPlainString()); put("longitude", lon.toPlainString());
        }
    }

    public boolean hasLocation() { return telemetry.containsKey("latitude"); }
    public static DirectBeltMessage parse(String json) {
        if (json == null || json.length() > 65536) throw new IllegalArgumentException("报文过大或为空");
        JSONObject data;
        try { data = JSON.parseObject(json); }
        catch (RuntimeException error) { throw new IllegalArgumentException("JSON 格式无效"); }
        if (data == null) throw new IllegalArgumentException("JSON 对象为空");
        return new DirectBeltMessage(data);
    }
    private void put(String key, Object value) { if (value != null) telemetry.put(key, value); }
    private static String identity(JSONObject data, String key) {
        String value = text(data, key, 64);
        if (value != null && !value.matches("[A-Za-z0-9._-]+")) throw new IllegalArgumentException(key + " 格式无效");
        return value;
    }
    private static String state(JSONObject data, String key) {
        return state(data, key, false);
    }
    private static String state(JSONObject data, String key, boolean allowUnknownHook) {
        String value = text(data, key, 16);
        // The supplied protocol example includes -1 for A/B hooks; retain it as unknown.
        if (value != null && !(allowUnknownHook && "-1".equals(value)) && !value.matches("[0-9]{1,8}"))
            throw new IllegalArgumentException(key + " 格式无效");
        return value;
    }
    private static String text(JSONObject data, String key, int max) {
        Object raw = data.get(key);
        if (raw == null) return null;
        if (!(raw instanceof String) && !(raw instanceof Number)) throw new IllegalArgumentException(key + " 格式无效");
        String value = raw.toString().trim();
        if (value.isEmpty()) return null;
        if (value.length() > max) throw new IllegalArgumentException(key + " 过长");
        return value;
    }
    private static BigDecimal number(JSONObject data, String key, int min, int max) {
        String value = text(data, key, 40);
        if (value == null) return null;
        try {
            BigDecimal result = new BigDecimal(value);
            if (result.precision() > 24 || result.scale() > 20 || result.scale() < -6
                    || result.compareTo(BigDecimal.valueOf(min)) < 0 || result.compareTo(BigDecimal.valueOf(max)) > 0)
                throw new NumberFormatException();
            return result;
        } catch (NumberFormatException error) { throw new IllegalArgumentException(key + " 超出范围或格式无效"); }
    }
    private static String timestamp(String raw) {
        if (raw == null || "0".equals(raw)) return null;
        try {
            if (!raw.matches("[0-9]{10}|[0-9]{13}")) throw new IllegalArgumentException();
            long value = Long.parseLong(raw);
            return (raw.length() == 13 ? Instant.ofEpochMilli(value) : Instant.ofEpochSecond(value)).toString();
        } catch (RuntimeException error) { throw new IllegalArgumentException("timestamp 必须为秒或毫秒时间戳"); }
    }
}
