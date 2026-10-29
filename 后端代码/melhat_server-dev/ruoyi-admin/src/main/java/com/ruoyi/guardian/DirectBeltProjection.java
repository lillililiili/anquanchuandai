package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;

/** Raw manufacturer values are retained; safety meanings require confirmed firmware mappings. */
final class DirectBeltProjection {
    private DirectBeltProjection() {}

    static final String[] FIELDS = {"online", "freshness", "battery", "isWeared", "worn",
            "longitude", "latitude", "locationReportedAt", "locationFreshness", "lastSeenAt",
            "inUse", "networkType", "networkStrength", "relativeAltitude", "altitude",
            "hangerAStatus", "hangerBStatus", "ignoreHookAlarm", "deviceReportedAt",
            "hookAEngaged", "hookBEngaged", "wearMappingConfirmed", "hookMappingConfirmed",
            "gpsAltitude", "telemetryReportedAt", "telemetryFreshness", "coordinateSystem", "locationSource",
            "accuracyMeters", "locationQuality", "locationTimeBasis"};

    static void apply(JSONObject snapshot, DirectBeltAccess access) {
        for (Object raw : WearableModel.rows(snapshot, "devices")) {
            JSONObject device = (JSONObject) raw;
            if (!"DIRECT_BELT".equals(device.getString("source"))) continue;
            JSONObject status = access == null ? null : access.status(device.getString("id"));
            if (status == null) {
                status = new JSONObject();
                for (String field : FIELDS) status.put(field, null);
                status.put("online", false);
                status.put("freshness", "UNKNOWN");
                status.put("locationFreshness", "UNKNOWN");
                status.put("telemetryFreshness", "UNKNOWN");
            }
            applyStatus(device, status);

        }
    }

    static void applyStatus(JSONObject device, JSONObject status) {
        boolean hasLocation=status.get("locationReportedAt")!=null;
        boolean olderLocation=false;
        try {olderLocation=hasLocation&&device.get("locationReportedAt")!=null&&java.time.Instant.parse(status.getString("locationReportedAt")).isBefore(java.time.Instant.parse(device.getString("locationReportedAt")));}catch(RuntimeException ignored){}
        for (String key : FIELDS) if (status.containsKey(key)) {
            if(olderLocation&&java.util.Arrays.asList("longitude","latitude","locationReportedAt","coordinateSystem","locationSource","accuracyMeters","locationQuality","locationTimeBasis").contains(key))continue;
            if(!hasLocation&&java.util.Arrays.asList("longitude","latitude","locationReportedAt","coordinateSystem","locationSource","accuracyMeters","locationQuality","locationTimeBasis").contains(key))continue;
            // Preserve last-known readings only when there was no observation in this process.
            // An actual partial telemetry report deliberately clears omitted safety readings.
            if(status.get(key)==null&&!key.endsWith("Freshness")&&!"freshness".equals(key)
                    &&status.get("telemetryReportedAt")==null)continue;
            device.put(key,status.get(key));
        }
        if(!hasLocation)device.put("locationFreshness",device.get("locationReportedAt")==null?"UNKNOWN":"STALE");
        if(!device.containsKey("coordinateSystem"))device.put("coordinateSystem","UNKNOWN");
        if(!device.containsKey("locationQuality"))device.put("locationQuality","unknown");
        device.put("locationTimeBasis","RECEIVED_AT");
        if(status.get("lastSeenAt")!=null){device.put("sourceTime", status.get("lastSeenAt"));device.put("updated", status.get("lastSeenAt"));}
        device.put("communicationProtocol", "WEBSOCKET");
        device.put("capabilities", status.getJSONArray("capabilities") == null
                ? new JSONArray() : new JSONArray(status.getJSONArray("capabilities")));
        device.put("video", "unavailable");
        if (!device.getBooleanValue("active")) {
            device.put("online", false);
            device.put("freshness", "STALE");
            device.put("locationFreshness", "STALE");
            device.put("telemetryFreshness", "STALE");
        }
        boolean current = Boolean.TRUE.equals(device.getBoolean("online"))
                && "CURRENT".equals(device.getString("freshness"))
                && "CURRENT".equals(device.getString("telemetryFreshness"));
        device.put("worn", current && device.getBooleanValue("wearMappingConfirmed")
                ? status.getBoolean("worn") : null);
        device.put("hookAEngaged", current && device.getBooleanValue("hookMappingConfirmed")
                ? status.getBoolean("hookAEngaged") : null);
        device.put("hookBEngaged", current && device.getBooleanValue("hookMappingConfirmed")
                ? status.getBoolean("hookBEngaged") : null);
        device.put("hookState", "UNKNOWN");
    }
}
