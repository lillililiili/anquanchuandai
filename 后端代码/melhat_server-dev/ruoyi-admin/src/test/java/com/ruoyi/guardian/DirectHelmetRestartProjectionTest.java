package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;

class DirectHelmetRestartProjectionTest {
    @Test void restartRetainsLastRealValuesAndTimesButNeverMakesThemCurrent(){
        String old="2026-10-22T00:00:00Z";
        JSONObject device=object("active",true,"sourceTime",old,"updated",old,"battery",70,"batteryReportedAt",old,"batteryFreshness","CURRENT",
                "isWeared","2","isWearedReportedAt",old,"isWearedFreshness","CURRENT","worn",true,
                "longitude",121.4,"latitude",31.2,"locationReportedAt",old,"coordinateSystem","GCJ02","locationQuality","valid","locationSource","GPS");
        JSONObject status=object("online",false,"freshness","UNKNOWN","lastSeenAt",null,"battery",null,"isWeared",null,"longitude",null,"latitude",null,
                "locationReportedAt",null,"locationFreshness","UNKNOWN","coordinateSystem","UNKNOWN","batteryFreshness","UNKNOWN","isWearedFreshness","UNKNOWN","mediaAvailable",false);
        DirectHelmetProjection.applyStatus(device,status);
        assertEquals(70,device.getIntValue("battery"));assertEquals("2",device.getString("isWeared"));assertEquals(121.4,device.getDoubleValue("longitude"));
        assertEquals(old,device.getString("locationReportedAt"));assertEquals(old,device.getString("sourceTime"));assertEquals("GCJ02",device.getString("coordinateSystem"));
        assertEquals("STALE",device.getString("freshness"));assertEquals("STALE",device.getString("locationFreshness"));assertEquals("STALE",device.getString("batteryFreshness"));assertNull(device.get("worn"));
        // A login alone refreshes communication, not the persisted sensors.
        status.put("online",true);status.put("freshness","CURRENT");status.put("lastSeenAt","2026-10-23T00:00:00Z");
        DirectHelmetProjection.applyStatus(device,status);
        assertTrue(device.getBooleanValue("online"));assertEquals("STALE",device.getString("locationFreshness"));assertEquals(old,device.getString("locationReportedAt"));assertNull(device.get("worn"));
        device.put("accuracyMeters",5);status.put("locationReportedAt","2026-10-23T00:00:01Z");status.put("latitude",31.3);status.put("longitude",121.5);status.put("accuracyMeters",null);
        DirectHelmetProjection.applyStatus(device,status);assertNull(device.get("accuracyMeters"),"new observation without precision must not inherit old precision");
    }
}
