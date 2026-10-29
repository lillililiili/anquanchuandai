package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import java.math.BigDecimal;

/** Values are decoded from the manufacturer's envelope, never from a user/account identity. */
public final class DirectHelmetMessage {
    public final String act;
    public final String deviceId;
    public final String alarmType;
    public final BigDecimal battery;
    public final Integer isWeared;
    public final String longitude;
    public final String latitude;
    public final String speed;
    public final String relativeAltitude;
    public final String inUse;
    public final String networkType;
    public final String networkStrength;
    public final String gps;
    public final String locationSource;
    public final BigDecimal accuracyMeters;
    public final String firmware;

    private DirectHelmetMessage(JSONObject data) {
        act = text(data, "act", 64);
        if (act == null) throw new IllegalArgumentException("缺少 act");
        deviceId = text(data, "device_id", 64);
        if (deviceId != null && !deviceId.matches("[A-Za-z0-9._-]+"))
            throw new IllegalArgumentException("device_id 格式无效");
        alarmType = text(data, "type", 64);
        battery = number(data, "bat_l", BigDecimal.ZERO, new BigDecimal("100"));
        BigDecimal wear = number(data, "is_weared", BigDecimal.ZERO, new BigDecimal("2"));
        if (wear != null && wear.stripTrailingZeros().scale() > 0)
            throw new IllegalArgumentException("is_weared 格式无效");
        isWeared = wear == null ? null : wear.intValueExact();
        BigDecimal lat = number(data, "x_point", new BigDecimal("-90"), new BigDecimal("90"));
        BigDecimal lon = number(data, "y_point", new BigDecimal("-180"), new BigDecimal("180"));
        if ((lat == null) != (lon == null)) throw new IllegalArgumentException("经纬度必须同时提供");
        String locationType = text(data, "gps", 8);
        gps = locationType;
        locationSource = "1".equals(gps) ? "GNSS" : "5".equals(gps) ? "WIFI"
                : "6".equals(gps) ? "CELL" : "4".equals(gps) || "9".equals(gps) ? "CACHED" : "UNKNOWN";
        accuracyMeters = number(data, "c_accuracy", BigDecimal.ZERO, new BigDecimal("1000000"));
        firmware = text(data, "app_version", 64);
        boolean networkFix = "5".equals(locationType) || "6".equals(locationType);
        boolean cachedFix = "4".equals(locationType) || "9".equals(locationType);
        // Firmware reports 0,0 before a fix; that is a heartbeat, not a location fix.
        // AMap's satellite status is unknown (-1) for valid Wi-Fi/cell fixes.
        // Cached locations must not refresh live location time; legacy reports may omit gps.
        boolean fix = lat != null && !(lat.signum() == 0 && lon.signum() == 0) && !cachedFix
                && (!"-1".equals(text(data, "gps_level", 8)) || networkFix);
        latitude = fix ? lat.toPlainString() : null;
        longitude = fix ? lon.toPlainString() : null;
        speed = text(data, "c_speed", 32);
        // M6811 firmware sends Relative_altitude; the existing exact key stays authoritative.
        relativeAltitude = text(data, data.containsKey("relative_altitude")
                ? "relative_altitude" : "Relative_altitude", 32);
        inUse = text(data, "in_use", 8);
        networkType = text(data, "net_type", 8);
        networkStrength = text(data, "net_strenth", 8);
    }

    public static DirectHelmetMessage parse(String json) {
        if (json == null || json.length() > 65536) throw new IllegalArgumentException("报文过大或为空");
        final JSONObject data;
        try { data = JSON.parseObject(json); }
        catch (RuntimeException error) { throw new IllegalArgumentException("JSON 格式无效"); }
        if (data == null) throw new IllegalArgumentException("JSON 对象为空");
        return new DirectHelmetMessage(data);
    }

    private static String text(JSONObject data, String key, int maximum) {
        Object raw = data.get(key);
        if (raw == null) return null;
        if (!(raw instanceof String) && !(raw instanceof Number))
            throw new IllegalArgumentException(key + " 格式无效");
        String value = raw.toString().trim();
        if (value.isEmpty()) return null;
        if (value.length() > maximum) throw new IllegalArgumentException(key + " 过长");
        return value;
    }

    private static BigDecimal number(JSONObject data, String key, BigDecimal min, BigDecimal max) {
        String value = text(data, key, 40);
        if (value == null) return null;
        try {
            BigDecimal result = new BigDecimal(value);
            if (result.precision() > 24 || result.scale() > 20 || result.scale() < -6)
                throw new NumberFormatException();
            if (result.compareTo(min) < 0 || result.compareTo(max) > 0) throw new NumberFormatException();
            return result;
        } catch (NumberFormatException error) {
            throw new IllegalArgumentException(key + " 超出范围或格式无效");
        }
    }

    public boolean hasLocation() { return latitude != null && longitude != null; }
}
