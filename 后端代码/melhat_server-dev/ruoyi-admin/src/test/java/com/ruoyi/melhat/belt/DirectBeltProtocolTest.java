package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.DirectBeltTelemetryService;
import org.junit.jupiter.api.Test;
import javax.websocket.Session;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DirectBeltProtocolTest {
    // Shape/values from supplied belt logs; identifiers and coordinates are synthetic.
    private static final String REPORT = "{\"act\":\"ca_report_location\",\"imei\":\"belt-test\",\"user_id\":\"999\","
            + "\"timestamp\":\"1791510968\",\"x_point\":\"35.46\",\"y_point\":\"112.57\","
            + "\"longitude\":\"0\",\"latitude\":\"0\",\"bat_l\":\"86\",\"is_weared\":\"0\","
            + "\"hanger_a_status\":\"0\",\"hanger_b_status\":\"0\",\"IgnoreHookAlarm\":\"1\","
            + "\"altitude\":\"0.000000\",\"Altitude\":\"53.59589348\",\"Relative_altitude\":\"0.00\"}";

    @Test void realBeltEnvelopePreservesCaseSensitiveHeightAndRawUnknownStates() {
        DirectBeltMessage message = DirectBeltMessage.parse(REPORT);
        assertEquals("belt-test", message.deviceId);
        assertEquals("35.46", message.telemetry.getString("latitude"));
        assertEquals("112.57", message.telemetry.getString("longitude"));
        assertEquals("53.59589348", message.telemetry.getString("altitude"));
        assertEquals("0.00", message.telemetry.getString("relativeAltitude"));
        assertEquals("0.000000", message.telemetry.getString("gpsAltitude"));
        assertEquals("0", message.telemetry.getString("hangerAStatus"));
        assertEquals(Instant.ofEpochSecond(1791510968L).toString(), message.deviceReportedAt);
        assertFalse(message.telemetry.containsKey("user_id"));
    }
    @Test void cachedFixAndAlarmCoordinatesCannotRenewOrReplaceLocation() {
        Fixture f=new Fixture();Session session=f.session();f.login(session);
        assertTrue(f.gateway.receive(session,REPORT).getBooleanValue("status"));
        JSONObject before=f.gateway.status("belt-test");
        f.clock.now=f.clock.now.plusSeconds(10);
        String cached=REPORT.replace("\"act\":\"ca_report_location\"","\"act\":\"ca_report_location\",\"gps\":4");
        assertFalse(DirectBeltMessage.parse(cached).hasLocation());
        f.gateway.receive(session,cached);
        f.clock.now=f.clock.now.plusSeconds(10);
        String alarm=REPORT.replace("ca_report_location","ca_sos").replace("35.46","39.9");
        f.gateway.receive(session,alarm);
        JSONObject after=f.gateway.status("belt-test");
        assertEquals(before.get("latitude"),after.get("latitude"));assertEquals(before.get("locationReportedAt"),after.get("locationReportedAt"));
        assertEquals("RECEIVED_AT",after.getString("locationTimeBasis"));
    }
    @Test void rejectsConflictingIdentitiesMalformedNumbersAndUnusableLocation() {
        assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse("{\"act\":\"ca_report_location\",\"imei\":\"a\",\"device_id\":\"b\"}"));
        assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse("{\"act\":\"ca_report_location\",\"bat_l\":101}"));
        assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse("{\"act\":\"ca_report_location\",\"x_point\":35}"));
        assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse("{\"act\":\"ca_report_location\",\"Relative_altitude\":\"NaN\"}"));
        assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse("{\"act\":\"ca_sos\",\"timestamp\":\"garbage\"}"));
        assertFalse(DirectBeltMessage.parse("{\"act\":\"ca_report_location\",\"x_point\":0,\"y_point\":0}").hasLocation());
    }
    @Test void unknownHookSentinelPreservesValidTelemetryAndClearsPreviousHookJudgement() {
        Fixture f = new Fixture(); Session session = f.session(); f.login(session);
        f.properties.setHookedValue("0"); f.properties.setUnhookedValue("1");
        assertTrue(f.gateway.receive(session, REPORT).getBooleanValue("status"));
        assertEquals(Boolean.TRUE, f.gateway.status("belt-test").getBoolean("hookAEngaged"));
        clearInvocations(f.telemetry);

        JSONObject report = JSONObject.parseObject(REPORT);
        report.put("hanger_a_status", "-1"); report.put("hanger_b_status", -1);
        report.put("bat_l", "85"); report.put("x_point", "35.47"); report.put("y_point", "112.58");
        assertTrue(f.gateway.receive(session, report.toJSONString()).getBooleanValue("status"));
        JSONObject status = f.gateway.status("belt-test");
        assertEquals("-1", status.getString("hangerAStatus"));
        assertEquals("-1", status.getString("hangerBStatus"));
        assertNull(status.get("hookAEngaged")); assertNull(status.get("hookBEngaged"));
        assertTrue(status.getBooleanValue("hookMappingConfirmed"));
        assertEquals(85, status.getIntValue("battery"));
        assertEquals("35.47", status.getString("latitude"));
        assertEquals("112.58", status.getString("longitude"));
        assertEquals("CURRENT", status.getString("locationFreshness"));
        verify(f.telemetry).receive(eq("belt-test"), argThat(saved ->
                "-1".equals(saved.getString("hangerAStatus")) && "-1".equals(saved.getString("hangerBStatus"))
                && saved.get("hookAEngaged") == null && saved.get("hookBEngaged") == null
                && saved.getIntValue("battery") == 85 && "35.47".equals(saved.getString("latitude"))
                && "112.58".equals(saved.getString("longitude"))), isNull(),
                eq(Instant.ofEpochSecond(1791510968L).toString()), eq(false));
    }
    @Test void onlyExactHookUnknownSentinelIsAcceptedAndCannotBeConfiguredAsSafeOrUnsafe() {
        for (String key : new String[]{"hanger_a_status", "hanger_b_status"}) {
            for (Object invalid : new Object[]{"-2", "-01", "-1.0", "--1", -2}) {
                JSONObject report = JSONObject.parseObject(REPORT); report.put(key, invalid);
                assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse(report.toJSONString()), key + "=" + invalid);
            }
        }
        for (String key : new String[]{"is_weared", "IgnoreHookAlarm"}) {
            JSONObject report = JSONObject.parseObject(REPORT); report.put(key, "-1");
            assertThrows(IllegalArgumentException.class, () -> DirectBeltMessage.parse(report.toJSONString()), key);
        }
        DirectBeltProperties properties = new DirectBeltProperties();
        properties.setHookedValue("-1"); properties.setUnhookedValue("1");
        assertFalse(properties.hookMappingConfirmed()); assertNull(properties.hooked("-1"));
        properties.setHookedValue("0"); properties.setUnhookedValue("-1");
        assertFalse(properties.hookMappingConfirmed()); assertNull(properties.hooked("-1"));
    }
    @Test void registrationOwnershipAndPersistenceControlAcknowledgement() {
        Fixture f = new Fixture(); Session session = f.session();
        assertFalse(f.gateway.receive(session, REPORT).getBooleanValue("status"));
        assertFalse(f.gateway.receive(session, "{\"act\":\"ca_login\",\"device_id\":\"unknown\"}").getBooleanValue("status"));
        JSONObject login = f.login(session);
        assertEquals("12", login.getJSONObject("data").getString("user_id"));
        assertFalse(f.gateway.receive(session, REPORT.replace("belt-test", "other-belt")).getBooleanValue("status"));
        doThrow(new IllegalStateException("database unavailable")).when(f.telemetry).receive(anyString(), any(), any(), any(), anyBoolean());
        assertFalse(f.gateway.receive(session, REPORT).getBooleanValue("status"));
        assertNull(f.gateway.status("belt-test").get("battery"));
        doNothing().when(f.telemetry).receive(anyString(), any(), any(), any(), anyBoolean());
        assertTrue(f.gateway.receive(session, REPORT).getBooleanValue("status"));
        assertEquals(86, f.gateway.status("belt-test").getIntValue("battery"));
        assertNull(f.gateway.status("belt-test").get("worn"));
        assertNull(f.gateway.status("belt-test").get("hookAEngaged"));
        verify(f.telemetry, times(2)).receive(eq("belt-test"), any(), isNull(), eq(Instant.ofEpochSecond(1791510968L).toString()), eq(false));
    }
    @Test void replacedSessionCannotReportOrDisconnectCurrentSessionAndTimeoutInvalidatesSafetyState() {
        Fixture f = new Fixture(); f.properties.setWornValue("0"); f.properties.setUnwornValue("1");
        f.properties.setHookedValue("0"); f.properties.setUnhookedValue("1");
        Session first = f.session(), second = f.session(); f.login(first); f.login(second);
        assertFalse(f.gateway.receive(first, REPORT).getBooleanValue("status"));
        f.gateway.disconnected(first);
        assertTrue(f.gateway.status("belt-test").getBooleanValue("online"));
        assertTrue(f.gateway.receive(second, REPORT).getBooleanValue("status"));
        assertTrue(f.gateway.status("belt-test").getBooleanValue("worn"));
        assertTrue(f.gateway.status("belt-test").getBooleanValue("hookAEngaged"));
        f.clock.now = f.clock.now.plusSeconds(46);
        JSONObject status = f.gateway.status("belt-test");
        assertFalse(status.getBooleanValue("online")); assertNull(status.get("worn")); assertNull(status.get("hookAEngaged"));
        assertEquals("STALE", status.getString("locationFreshness"));
        assertFalse(f.gateway.receive(second, REPORT).getBooleanValue("status"));
    }
    @Test void alarmPreservesUnknownCodeAndManualSosDoesNotClaimMediaSuccess() {
        Fixture f = new Fixture(); Session session = f.session(); f.login(session);
        assertTrue(f.gateway.receive(session, "{\"act\":\"ca_sos\",\"device_id\":\"belt-test\",\"type\":\"6\",\"timestamp\":\"1791511557\"}").getBooleanValue("status"));
        verify(f.telemetry).receive(eq("belt-test"), any(), eq("6"), eq(Instant.ofEpochSecond(1791511557L).toString()), eq(false));
        JSONObject sos = f.gateway.receive(session, "{\"act\":\"ca_sip_sos\",\"device_id\":\"belt-test\"}");
        assertTrue(sos.getBooleanValue("status")); assertEquals("unavailable", sos.getString("media_status"));
        when(f.telemetry.registered("belt-test")).thenReturn(null);
        assertFalse(f.gateway.receive(session, REPORT).getBooleanValue("status"));
    }
    @Test void disabledAndRestartedGatewayNeverInventsOnlineState() {
        Fixture f = new Fixture(); Session session = f.session(); f.properties.setEnabled(false);
        assertFalse(f.gateway.receive(session, REPORT).getBooleanValue("status"));
        assertFalse(f.gateway.status("belt-test").getBooleanValue("online"));
        assertEquals("UNKNOWN", f.gateway.status("belt-test").getString("freshness"));
    }
    @Test void partialHeartbeatsDoNotRenewOmittedSafetyMeasurements() {
        Fixture f = new Fixture(); Session session = f.session(); f.login(session);
        f.properties.setWornValue("0"); f.properties.setUnwornValue("1");
        f.properties.setHookedValue("0"); f.properties.setUnhookedValue("1");
        assertTrue(f.gateway.receive(session, REPORT).getBooleanValue("status"));
        assertTrue(f.gateway.status("belt-test").getBooleanValue("worn"));
        assertTrue(f.gateway.receive(session, "{\"act\":\"ca_report_location\",\"imei\":\"belt-test\",\"bat_l\":85}").getBooleanValue("status"));
        JSONObject status = f.gateway.status("belt-test");
        assertEquals(85, status.getIntValue("battery"));
        assertNull(status.get("worn")); assertNull(status.get("hookAEngaged")); assertNull(status.get("isWeared"));
    }
    static class Fixture {
        final MutableClock clock = new MutableClock();
        final DirectBeltProperties properties = new DirectBeltProperties();
        final DirectBeltTelemetryService telemetry = mock(DirectBeltTelemetryService.class);
        final DirectBeltGateway gateway;
        Fixture() {
            properties.setEnabled(true);
            JSONObject record = new JSONObject(); record.put("deviceId", "belt-test"); record.put("userId", "12"); record.put("userName", "测试人员");
            when(telemetry.registered("belt-test")).thenReturn(record);
            gateway = new DirectBeltGateway(properties, telemetry, new DirectBeltSessions(clock));
        }
        Session session() { Session result = mock(Session.class); when(result.isOpen()).thenReturn(true); return result; }
        JSONObject login(Session session) {
            JSONObject result = gateway.receive(session, "{\"act\":\"ca_login\",\"device_id\":\"belt-test\",\"type\":9}");
            assertTrue(result.getBooleanValue("status")); return result;
        }
    }
    static class MutableClock extends Clock {
        Instant now = Instant.parse("2026-10-20T12:00:00Z");
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
}
