package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.split.SplitHelmetService;
import java.util.Arrays;

/** A registered asset gains only observations supplied by its own adapter. */
final class SplitHelmetProjection {
    static final String[] FIELDS = {"online","freshness","lastSeenAt","sourceTime","onlineReportedAt",
        "battery","batteryReportedAt","batteryFreshness","voltage","voltageReportedAt","voltageFreshness",
        "storageUsed","storageAvailable","storageTotal","tfEnable","storageReportedAt","storageFreshness",
        "storageUsedReportedAt","storageUsedFreshness","storageAvailableReportedAt","storageAvailableFreshness","storageTotalReportedAt","storageTotalFreshness","tfEnableReportedAt","tfEnableFreshness",
        "pressure","temperature","altitude","pressureReportedAt","pressureFreshness","temperatureReportedAt","temperatureFreshness","altitudeReportedAt","altitudeFreshness",
        "barometricAltitude","barometricAltitudeReportedAt","barometricAltitudeFreshness",
        "longitude","latitude","speed","gpsAltitude","locationReportedAt","locationFreshness","locationSource","locationQuality","locationTimeBasis","coordinateSystem","accuracyMeters",
        "deviceReportedAt","clockAnomaly","timeAnomaly","lastRemovalAt","lastRemovalAtReportedAt","mediaAvailable","voiceAvailable","broadcastAvailable","mediaStatus","capabilities"};
    private SplitHelmetProjection() {}
    static void apply(JSONObject state, SplitHelmetService service) {
        for(Object raw:WearableModel.rows(state,"devices")) {
            JSONObject d=(JSONObject)raw;
            if(!"SPLIT_HELMET".equals(d.getString("source")))continue;
            JSONObject status=service==null?null:service.status(d.getString("deviceNumber"));
            applyStatus(d,status,service!=null&&service.enabled());
        }
    }
    static void applyStatus(JSONObject device,JSONObject status,boolean enabled) {
        if(status!=null)for(String key:FIELDS)if(status.containsKey(key))device.put(key,status.get(key));
        if(status!=null) {
            String storageAt=null,storageFreshness="UNKNOWN";
            for(String key:Arrays.asList("storageUsed","storageAvailable","storageTotal","tfEnable")) {
                String at=status.getString(key+"ReportedAt"),freshness=status.getString(key+"Freshness");
                if(at!=null&&(storageAt==null||java.time.Instant.parse(at).isAfter(java.time.Instant.parse(storageAt))))storageAt=at;
                if("CURRENT".equals(freshness))storageFreshness="CURRENT";
                else if("STALE".equals(freshness)&&!"CURRENT".equals(storageFreshness))storageFreshness="STALE";
            }
            device.put("storageReportedAt",storageAt);device.put("storageFreshness",storageFreshness);
        }
        if(status==null||!enabled) {
            device.put("online",null);device.put("freshness","UNKNOWN");
            for(String key:Arrays.asList("battery","location","pressure","temperature","storage","voltage","altitude"))device.put(key+"Freshness",device.get(key+"ReportedAt")==null?"UNKNOWN":"STALE");
            device.put("mediaAvailable",false);device.put("voiceAvailable",false);device.put("broadcastAvailable",false);
            device.put("mediaStatus",enabled?"unavailable":"unconfigured");
        }
        device.put("source","SPLIT_HELMET");device.put("communicationProtocol","ZLM_WEBRTC");
        device.put("worn",null);device.put("isWeared",null);device.put("isWearedFreshness","UNKNOWN");
        if(!device.getBooleanValue("active")) {
            device.put("online",false);device.put("freshness","STALE");
            for(String key:Arrays.asList("battery","location","pressure","temperature","storage"))device.put(key+"Freshness","STALE");
            device.put("mediaAvailable",false);device.put("voiceAvailable",false);device.put("broadcastAvailable",false);
        }
        device.put("video",device.getBooleanValue("mediaAvailable")?"available":"unavailable");
        if(device.getJSONArray("capabilities")==null)device.put("capabilities",new JSONArray());
    }
}
