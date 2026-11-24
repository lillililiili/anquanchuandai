package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.split.SplitTelemetry;
import org.junit.jupiter.api.Test;
import java.time.Instant;
import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;

class SplitHelmetTelemetryTest {
    final long now=Instant.parse("2026-11-15T12:00:00Z").toEpochMilli();
    JSONObject envelope(String kind,long offset,JSONObject payload){return object("deviceId","SN1","kind",kind,"payload",payload,"observedAt",Instant.ofEpochMilli(now+offset).toString(),"receivedMillis",now);}
    @Test void missingMeasurementsRemainAbsentAndZeroBatteryIsReal(){
        JSONObject s=new JSONObject();SplitTelemetry.merge(s,envelope("deviceStatus",0,object("helmetSn","SN1","total","128GB","tf_enable",false)));
        assertFalse(s.containsKey("battery"));assertFalse(s.containsKey("storageUsed"));assertEquals("128GB",s.getString("storageTotal"));assertEquals("false",s.getString("tfEnable"));
        SplitTelemetry.merge(s,envelope("deviceStatus",0,object("helmetSn","SN1","power",0)));assertEquals(0,s.getDoubleValue("battery"));
        SplitTelemetry.merge(s,envelope("deviceStatus",1000,object("helmetSn","SN1")));assertEquals(0,s.getDoubleValue("battery"));assertEquals("2026-11-15T12:00:00Z",s.getString("batteryReportedAt"));
    }
    @Test void lateFieldsDoNotReplaceNewerValuesOrTheirTimes(){
        JSONObject s=new JSONObject();SplitTelemetry.merge(s,envelope("deviceStatus",0,object("helmetSn","SN1","power",80,"used","12")));
        SplitTelemetry.merge(s,envelope("deviceStatus",-60000,object("helmetSn","SN1","power",10,"used","90","total","128")));
        assertEquals(80,s.getIntValue("battery"));assertEquals("12",s.getString("storageUsed"));assertEquals("128",s.getString("storageTotal"));
        assertEquals("2026-11-15T12:00:00Z",s.getString("storageUsedReportedAt"));assertEquals("2026-11-15T11:59:00Z",s.getString("storageTotalReportedAt"));
    }
    @Test void queryFailureMakesOnlineUnknownWithoutChangingFreshMeasurements(){
        JSONObject stored=object("onlineReportedAt","2026-11-15T12:00:00Z","vendorOnline",true,"onlineUnknown",true,"battery",61,"batteryReportedAt","2026-11-15T12:00:00Z");
        JSONObject view=SplitTelemetry.view(stored,300,now);assertNull(view.get("online"));assertEquals("UNKNOWN",view.getString("freshness"));assertEquals("CURRENT",view.getString("batteryFreshness"));assertEquals(61,view.getIntValue("battery"));
        assertNull(SplitTelemetry.view(object("lastSeenAt","2026-11-15T12:00:00Z"),300,now).get("online"));
    }
    @Test void eachFieldExpiresIndependently(){
        JSONObject stored=object("battery",90,"batteryReportedAt","2026-11-15T11:00:00Z","pressure","1000","pressureReportedAt","2026-11-15T12:00:00Z","storageTotal","128","storageTotalReportedAt","2026-11-15T11:00:00Z","tfEnable","1","tfEnableReportedAt","2026-11-15T12:00:00Z");
        JSONObject view=SplitTelemetry.view(stored,300,now);assertEquals("STALE",view.getString("batteryFreshness"));assertEquals("CURRENT",view.getString("pressureFreshness"));assertEquals("STALE",view.getString("storageTotalFreshness"));assertEquals("CURRENT",view.getString("tfEnableFreshness"));assertEquals("UNKNOWN",view.getString("storageUsedFreshness"));assertEquals(90,view.getIntValue("battery"));
    }
    @Test void invalidAndFutureDeviceClocksUseReceiptWithoutInventingMeasurements(){
        String at=Instant.ofEpochMilli(now).toString();for(Object time:new Object[]{null,"not-a-time","1990-01-01T00:00:00Z","2040-01-01T00:00:00Z",17947440000L})assertEquals(at,SplitTelemetry.normalizeTimestamp(time,now));
        assertEquals(at,SplitTelemetry.normalizeTimestamp(now,now));assertEquals(at,SplitTelemetry.normalizeTimestamp(now/1000,now));
        assertEquals("2026-11-15T11:00:00Z",SplitTelemetry.normalizeTimestamp("2026-11-15T11:00:00Z",now));
    }
    @Test void removalCannotClaimCurrentWearAndGnssRemainsWgs84(){
        JSONObject s=new JSONObject();SplitTelemetry.merge(s,envelope("sos",0,object("helmetSn","SN1","type","removal")));
        JSONObject view=SplitTelemetry.view(s,300,now);assertNull(view.get("worn"));assertEquals("UNKNOWN",view.getString("isWearedFreshness"));assertNotNull(view.get("lastRemovalAt"));
        SplitTelemetry.merge(s,envelope("gnss",0,object("helmetSn","SN1","longitude",116.4,"latitude",39.9)));
        assertEquals("WGS84",s.getString("coordinateSystem"));assertEquals("valid",s.getString("locationQuality"));assertFalse(s.containsKey("accuracyMeters"));
        SplitTelemetry.merge(s,envelope("gnss",-1000,object("helmetSn","SN1","longitude",115,"latitude",38)));
        assertEquals(116.4,s.getDoubleValue("longitude"));assertEquals("2026-11-15T12:00:00Z",s.getString("locationReportedAt"));
    }
}
