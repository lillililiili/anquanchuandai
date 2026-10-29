package com.ruoyi.fuda;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import org.junit.jupiter.api.Test;
import static com.ruoyi.fuda.FudaMapping.*;
import static org.junit.jupiter.api.Assertions.*;

class FudaMappingTest {
    @Test void currentHelmetAndOfflineMeasurementsRemainDistinct(){
        JSONObject d=object("online",true,"battery",75,"batteryReportedAt","2026-10-27T07:59:50Z","batteryFreshness","CURRENT",
                "isWeared","2","isWearedReportedAt","2026-10-27T07:59:50Z","isWearedFreshness","CURRENT","networkStrength",4);
        JSONObject current=statusItem(common("test","HELMET","real-1",null),d,45,new DirectBeltProperties(),FudaAuthTest.CLOCK);
        assertEquals("VALID",current.getJSONObject("battery").getString("validity"));assertEquals("WORN",current.getJSONObject("wear").getString("status"));
        assertNull(current.getJSONObject("network").get("signalLevel"));assertEquals("UNKNOWN",current.getJSONObject("network").getString("validity"));
        assertEquals("UNSUPPORTED",current.getJSONObject("hookA").getString("status"));
        d.put("online",false);JSONObject stale=statusItem(common("test","HELMET","real-1",null),d,45,new DirectBeltProperties(),FudaAuthTest.CLOCK);
        assertEquals("STALE",stale.getJSONObject("battery").getString("validity"));assertEquals(75.0,stale.getJSONObject("battery").getDouble("percent"));
    }
    @Test void noBeltWearOrAltitudeInferenceAndOnlyConfirmedHookMapping(){
        DirectBeltProperties belt=new DirectBeltProperties();belt.setHookedValue("1");belt.setUnhookedValue("0");belt.setWornValue("1");belt.setUnwornValue("0");
        JSONObject d=object("online",true,"isWeared","1","worn",true,"hookMappingConfirmed",true,"hangerAStatus","1","hangerBStatus","0",
                "telemetryReportedAt","2026-10-27T07:59:50Z","telemetryFreshness","CURRENT","altitude",88);
        JSONObject status=statusItem(common("test","SAFETY_BELT","real-2",null),d,45,belt,FudaAuthTest.CLOCK);
        assertEquals("UNKNOWN",status.getJSONObject("wear").getString("status"));assertEquals("ATTACHED",status.getJSONObject("hookA").getString("status"));assertEquals("DETACHED",status.getJSONObject("hookB").getString("status"));
        d.put("hookMappingConfirmed",false);assertEquals("UNKNOWN",statusItem(common("test","SAFETY_BELT","real-2",null),d,45,belt,FudaAuthTest.CLOCK).getJSONObject("hookA").getString("status"));
    }
    @Test void coordinateAndTimestampProvenanceAreRequired(){
        JSONObject d=object("online",true,"longitude",119.2,"latitude",26.1,"coordinateSystem","UNKNOWN","locationQuality","valid","locationSource","gps","locationReportedAt","2026-10-27T07:59:50Z","locationFreshness","CURRENT","altitude",55);
        assertNull(position(d));d.put("coordinateSystem","GCJ02");JSONObject p=position(d);assertNotNull(p);assertNull(p.get("altitude"));assertNull(p.get("speed"));assertEquals("PLATFORM",p.getString("timeSource"));
        d.put("locationReportedAt","2026-10-27T07:50:00Z");assertEquals("STALE",positionItem(common("test","HELMET","real-1",null),d,45,FudaAuthTest.CLOCK).getString("validity"));
        d.put("longitude",0);d.put("latitude",0);assertNull(position(d));
    }
    @Test void locationProfileRequiresExplicitEvidenceAndRejectsConflicts(){
        JSONObject d=object("longitude",119.2,"latitude",26.1,"locationReportedAt","2026-10-27T07:59:50Z");
        FudaProperties.LocationProfile profile=new FudaProperties.LocationProfile();profile.setCoordinateSystem("WGS84");
        applyLocationProfile(d,profile);assertNull(position(d));profile.setVerified(true);applyLocationProfile(d,profile);assertNull(position(d));
        profile.setEvidence("synthetic commissioned fixture");profile.setPositionMethod("GNSS");applyLocationProfile(d,profile);assertEquals("WGS84",position(d).getString("coordinateSystem"));
        d.put("coordinateSystem","GCJ02");applyLocationProfile(d,profile);assertEquals("GCJ02",position(d).getString("coordinateSystem"));
        d.put("coordinateSystem","UNKNOWN");d.put("locationQuality","invalid");applyLocationProfile(d,profile);assertNull(position(d));
    }
    @Test void unknownAlarmRemainsRawAndLaterLocationIsNotAttached(){
        JSONObject row=object("deviceType","SAFETY_BELT","deviceId","real-2","eventId","event-1","occurredAt","2026-10-27T07:55:00Z","receivedAt","2026-10-27T08:00:00Z",
                "rawEvent",object("rawAlarmType","6","type","设备通信"),"device",object("longitude",119.2,"latitude",26.1,"coordinateSystem","WGS84","locationReportedAt","2026-10-27T08:00:00Z"));
        JSONObject result=alarm("test",row);assertEquals("UNKNOWN",result.getString("alarmType"));assertEquals("6",result.getString("rawAlarmType"));assertEquals("NONE",result.getString("positionSource"));
        row.getJSONObject("rawEvent").put("type","人员求助");assertEquals("SOS",alarm("test",row).getString("alarmType"));
    }
}
