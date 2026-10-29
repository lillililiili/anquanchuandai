package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.service.DirectHelmetAccess;

/** Live session state overlays the asset ledger; ledger edits cannot manufacture telemetry. */
final class DirectHelmetProjection {
    private DirectHelmetProjection() {}

    static void apply(JSONObject snapshot, DirectHelmetAccess access) {
        JSONArray devices = snapshot.getJSONArray("devices");
        if (devices == null) return;
        for (Object raw : devices) {
            JSONObject device = (JSONObject) raw;
            if (!"DIRECT_HELMET".equals(device.getString("source"))) continue;
            JSONObject status = access == null ? null : access.status(device.getString("id"));
            if (status == null) {
                status = new JSONObject();
                status.put("online", false);
                status.put("freshness", "UNKNOWN");
                status.put("locationFreshness", "UNKNOWN");
                for(String field:new String[]{"battery","isWeared","inUse","networkType","networkStrength","relativeAltitude"}) status.put(field+"Freshness","UNKNOWN");
                status.put("mediaAvailable",false);status.put("voiceAvailable",false);status.put("broadcastAvailable",false);
            }
            applyStatus(device, status);

        }
    }

    static void applyStatus(JSONObject device, JSONObject status) {
        // A process restart has no in-memory observation. Null placeholders must
        // not erase the persisted last observation or re-date it as current.
        java.util.Set<String> locationFields=new java.util.HashSet<>(java.util.Arrays.asList("longitude","latitude","locationReportedAt","coordinateSystem","locationSource","accuracyMeters","locationQuality","gps"));
        boolean hasLocationObservation=status.get("locationReportedAt")!=null;
        for (String key : new String[]{"online", "freshness", "battery", "isWeared",
                "longitude", "latitude", "locationReportedAt", "locationFreshness", "lastSeenAt",
                "inUse", "networkType", "networkStrength", "relativeAltitude", "coordinateSystem", "locationSource",
                "accuracyMeters", "sourceFirmware", "locationQuality", "gps", "firmware",
                "batteryReportedAt", "batteryFreshness", "isWearedReportedAt", "isWearedFreshness",
                "inUseReportedAt", "inUseFreshness", "networkTypeReportedAt", "networkTypeFreshness",
                "networkStrengthReportedAt", "networkStrengthFreshness", "relativeAltitudeReportedAt", "relativeAltitudeFreshness",
                "mediaAvailable", "voiceAvailable", "broadcastAvailable", "mediaProtocol", "mediaStatus", "mediaVerification"}) {
            if(locationFields.contains(key)&&!hasLocationObservation)continue;
            if(status.containsKey(key)) {
                Object value=status.get(key);
                if(value==null&&!locationFields.contains(key)&&!key.endsWith("Freshness")&&!"freshness".equals(key)&&!key.endsWith("Available"))continue;
                device.put(key,value);
            }
        }
        if(status.get("lastSeenAt")!=null){device.put("sourceTime",status.get("lastSeenAt"));device.put("updated",status.get("lastSeenAt"));}
        if("UNKNOWN".equals(device.getString("freshness"))&&device.get("sourceTime")!=null)device.put("freshness","STALE");
        if(!hasLocationObservation)device.put("locationFreshness",device.get("locationReportedAt")==null?"UNKNOWN":"STALE");
        for(String field:new String[]{"battery","isWeared","inUse","networkType","networkStrength","relativeAltitude"})
            if("UNKNOWN".equals(device.getString(field+"Freshness"))&&device.get(field+"ReportedAt")!=null)device.put(field+"Freshness","STALE");
        device.put("locationTimeBasis", "RECEIVED_AT");
        device.put("communicationProtocol", "SIP");
        // Telemetry support does not imply that SIP calling or text-to-speech is configured.
        device.put("capabilities", status.getJSONArray("capabilities") == null
                ? new JSONArray() : status.getJSONArray("capabilities"));
        device.put("video",device.getBooleanValue("mediaAvailable")?"available":"unavailable");
        boolean current = Boolean.TRUE.equals(device.getBoolean("online"))
                && "CURRENT".equals(device.getString("freshness"))
                && "CURRENT".equals(status.getString("isWearedFreshness"));
        String wear = device.getString("isWeared");
        device.put("worn", !current ? null : "2".equals(wear) ? Boolean.TRUE : "1".equals(wear) ? Boolean.FALSE : null);
        if (!device.getBooleanValue("active")) {
            device.put("online", false);
            device.put("freshness", "STALE");
            device.put("locationFreshness", "STALE");
            device.put("worn", null);
            for(String field:new String[]{"battery","isWeared","inUse","networkType","networkStrength","relativeAltitude"})
                device.put(field+"Freshness","STALE");
        }
    }
}
