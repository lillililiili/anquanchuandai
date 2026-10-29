package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import javax.websocket.Session;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectHelmetFreshnessTest {
    @Test void omittedFieldsAndSosCannotRefreshOldWearOrBattery() {
        MutableClock clock=new MutableClock();DirectHelmetSessions sessions=new DirectHelmetSessions(clock);
        Session s=mock(Session.class);when(s.isOpen()).thenReturn(true);sessions.register("helmet-test",s);
        sessions.heard(s,DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"bat_l\":75,\"is_weared\":2,\"net_type\":4}"));
        String wearAt=sessions.status("helmet-test",45).getString("isWearedReportedAt");
        clock.now=clock.now.plusSeconds(30);
        sessions.heard(s,DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"bat_l\":74}"));
        sessions.register("helmet-test",s);
        assertEquals(74,sessions.status("helmet-test",45).getIntValue("battery"));
        clock.now=clock.now.plusSeconds(20);
        sessions.heard(s,DirectHelmetMessage.parse("{\"act\":\"ca_sos\",\"type\":1}"));
        JSONObject status=sessions.status("helmet-test",45);
        assertEquals("CURRENT",status.getString("freshness"));
        assertEquals("CURRENT",status.getString("batteryFreshness"));
        assertEquals("STALE",status.getString("isWearedFreshness"));
        assertEquals("STALE",status.getString("networkTypeFreshness"));
        assertEquals(wearAt,status.getString("isWearedReportedAt"));
        assertEquals("UNKNOWN",status.getString("relativeAltitudeFreshness"));
    }
    @Test void coordinateSystemRequiresAnExplicitDocumentedProfileAndFirmwareMismatchRevokesIt() {
        DirectHelmetMessage message=DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"gps\":6,\"gps_level\":-1,\"c_accuracy\":120,\"x_point\":30,\"y_point\":110}");
        assertEquals("CELL",message.locationSource);assertEquals(120,message.accuracyMeters.intValue());
        DirectHelmetLocationProfiles profiles=new DirectHelmetLocationProfiles();
        JSONObject point=JSONObject.parseObject("{\"longitude\":110,\"latitude\":30}");
        profiles.apply("test",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
        DirectHelmetLocationProfiles.Profile p=new DirectHelmetLocationProfiles.Profile();p.setFirmware("M-test");p.setCoordinateSystem("GCJ02");
        profiles.getProfiles().put("test",p);profiles.apply("test",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
        p.setEvidence("approved source inspection");profiles.apply("test",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
        p.setSources(java.util.Arrays.asList("CELL"));point.put("locationSource","CELL");profiles.apply("test",point);assertEquals("GCJ02",point.getString("coordinateSystem"));
        point.put("firmware","changed-version");profiles.apply("test",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
        assertEquals(110,point.getIntValue("longitude"));
    }
    static class MutableClock extends Clock {
        Instant now=Instant.parse("2026-10-23T00:00:00Z");
        public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId z){return this;}public Instant instant(){return now;}
    }
}
