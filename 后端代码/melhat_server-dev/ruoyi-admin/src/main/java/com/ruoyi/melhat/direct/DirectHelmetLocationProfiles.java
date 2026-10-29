package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import java.util.LinkedHashMap;
import java.util.Map;

/** Explicitly commissioned profiles only. No inference from a vendor name or GPS type. */
@Component
@ConfigurationProperties(prefix = "melhat.direct-location")
public class DirectHelmetLocationProfiles {
    private Map<String, Profile> profiles = new LinkedHashMap<>();
    public Map<String, Profile> getProfiles() { return profiles; }
    public void setProfiles(Map<String, Profile> value) { profiles = value; }
    public void apply(String deviceId, JSONObject data) {
        data.put("coordinateSystem", "UNKNOWN");
        data.remove("sourceFirmware");
        Profile p = profiles.get(deviceId);
        if (p != null && p.firmware != null && !p.firmware.trim().isEmpty()
                && p.evidence != null && !p.evidence.trim().isEmpty()
                && ("GCJ02".equals(p.coordinateSystem) || "WGS84".equals(p.coordinateSystem))
                && p.sources.contains(data.getString("locationSource"))
                && (data.getString("firmware") == null || p.firmware.equals(data.getString("firmware")))) {
            data.put("coordinateSystem", p.coordinateSystem);
            data.put("sourceFirmware", p.firmware);
        }
        boolean point = data.get("longitude") != null && data.get("latitude") != null;
        data.put("locationQuality", point && !"UNKNOWN".equals(data.getString("coordinateSystem")) ? "valid" : "unknown");
    }
    public static class Profile {
        private String firmware, coordinateSystem, evidence;
        private java.util.List<String> sources=new java.util.ArrayList<>();
        public java.util.List<String> getSources(){return sources;}
        public void setSources(java.util.List<String> value){sources=value==null?new java.util.ArrayList<>():value;}
        public String getFirmware() { return firmware; }
        public void setFirmware(String v) { firmware = v; }
        public String getCoordinateSystem() { return coordinateSystem; }
        public void setCoordinateSystem(String v) { coordinateSystem = v; }
        public String getEvidence() { return evidence; }
        public void setEvidence(String v) { evidence = v; }
    }
}
