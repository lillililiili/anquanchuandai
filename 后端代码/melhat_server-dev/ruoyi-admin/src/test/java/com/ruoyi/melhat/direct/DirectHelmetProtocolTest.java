package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.junit.jupiter.api.Test;
import javax.websocket.RemoteEndpoint;
import javax.websocket.Session;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DirectHelmetProtocolTest {
    @Test void parsesManufacturerCoordinatesWearAndMissingFixWithoutInventingValues() {
        DirectHelmetMessage data = DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"x_point\":\"35.466123\","
                + "\"y_point\":\"112.574204\",\"bat_l\":\"85\",\"is_weared\":\"2\"}");
        assertEquals("35.466123", data.latitude);
        assertEquals("112.574204", data.longitude);
        assertEquals(2, data.isWeared.intValue());
        assertEquals(85, data.battery.intValue());
        assertEquals("device.01", DirectHelmetMessage.parse("{\"act\":\"ca_login\",\"device_id\":\"device.01\"}").deviceId);
        DirectHelmetMessage empty = DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"is_weared\":\"1\"}");
        assertFalse(empty.hasLocation()); assertNull(empty.battery); assertEquals(1, empty.isWeared.intValue());
        assertFalse(DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"x_point\":0,\"y_point\":0}").hasLocation());
        assertFalse(DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"x_point\":35,\"y_point\":112,\"gps_level\":-1}").hasLocation());
        assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"x_point\":\"NaN\",\"y_point\":112}"));
        assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"x_point\":112,\"y_point\":35}"));
        assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"bat_l\":101}"));
        assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"x_point\":\"1e-99999999\",\"y_point\":112}"));
    }

    @Test void observedRelativeAltitudeAliasKeepsTheExistingExactKeyAuthoritative() {
        assertEquals("3.2", DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"Relative_altitude\":3.2}").relativeAltitude);
        assertEquals("1.5", DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"relative_altitude\":\"1.5\",\"Relative_altitude\":\"3.2\"}").relativeAltitude);
        assertNull(DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"relative_altitude\":null,\"Relative_altitude\":\"3.2\"}").relativeAltitude);
        assertNull(DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"RELATIVE_ALTITUDE\":\"3.2\"}").relativeAltitude);
        assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(
                "{\"act\":\"ca_report_location\",\"Relative_altitude\":{\"value\":3.2}}"));
    }

    @Test void unknownSatelliteStatusAcceptsOnlyExplicitWifiOrCellLocationTypes() {
        for (Object type : new Object[]{5, "5", 6, "6"}) {
            JSONObject report = locationReport(type, -1);
            DirectHelmetMessage parsed = DirectHelmetMessage.parse(report.toJSONString());
            assertEquals("35.466123", parsed.latitude);
            assertEquals("112.574204", parsed.longitude);
        }
        for (Object type : new Object[]{1, "1", 0, 2, 4, "4", 9, "9", "unknown", null}) {
            assertFalse(DirectHelmetMessage.parse(locationReport(type, -1).toJSONString()).hasLocation(),
                    "Unknown satellite status must not authorize source " + type);
        }
        for (Object type : new Object[]{4, "4", 9, "9"}) {
            assertFalse(DirectHelmetMessage.parse(locationReport(type, 1).toJSONString()).hasLocation(),
                    "Cached locations must not become current: " + type);
        }
        assertTrue(DirectHelmetMessage.parse(locationReport(null, null).toJSONString()).hasLocation(),
                "Legacy reports without gps and gps_level remain supported");
        assertTrue(DirectHelmetMessage.parse(locationReport(1, 1).toJSONString()).hasLocation());
    }

    @Test void networkLocationStillRequiresCompleteValidNonzeroCoordinates() {
        for (Object type : new Object[]{5, 6}) {
            JSONObject report = locationReport(type, -1);
            report.remove("x_point"); report.remove("y_point");
            assertFalse(DirectHelmetMessage.parse(report.toJSONString()).hasLocation());
            report.put("x_point", null); report.put("y_point", null);
            assertFalse(DirectHelmetMessage.parse(report.toJSONString()).hasLocation());
            report.put("x_point", 0); report.put("y_point", "0.0");
            assertFalse(DirectHelmetMessage.parse(report.toJSONString()).hasLocation());
            report.put("x_point", null); report.put("y_point", 112);
            assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(report.toJSONString()));
            for (Object invalid : new Object[]{"NaN", "Infinity", 91, -91, "1e-99999999"}) {
                report.put("x_point", invalid);
                assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(report.toJSONString()));
            }
            report.put("x_point", 35); report.put("y_point", 181);
            assertThrows(IllegalArgumentException.class, () -> DirectHelmetMessage.parse(report.toJSONString()));
        }
    }

    @Test void sourceChangesAcceptNetworkFixesButCachedAndUnknownReportsDoNotRefreshLocationTime() {
        Fixture f = new Fixture();
        Session device = session();
        assertTrue(f.gateway.receive(device, login("helmet-a")).getBooleanValue("status"));
        for (Object type : new Object[]{null, 5, 6}) {
            f.clock.advance(5);
            assertTrue(f.gateway.receive(device, locationReport(type, type == null ? null : -1).toJSONString())
                    .getBooleanValue("status"));
            assertEquals(f.clock.instant().toString(), f.gateway.status("helmet-a").getString("locationReportedAt"));
            assertEquals("CURRENT", f.gateway.status("helmet-a").getString("locationFreshness"));
        }
        String locationAt = f.gateway.status("helmet-a").getString("locationReportedAt");
        for (Object type : new Object[]{4, 9, 1, "unknown", null}) {
            f.clock.advance(10);
            JSONObject rejectedFix = locationReport(type, type != null && (type.equals(4) || type.equals(9)) ? 1 : -1);
            rejectedFix.put("x_point", "36.5"); rejectedFix.put("y_point", "113.5");
            assertTrue(f.gateway.receive(device, rejectedFix.toJSONString()).getBooleanValue("status"));
            JSONObject status = f.gateway.status("helmet-a");
            assertEquals(locationAt, status.getString("locationReportedAt"));
            assertEquals("35.466123", status.getString("latitude"));
            assertEquals("112.574204", status.getString("longitude"));
            assertEquals(f.clock.instant().toString(), status.getString("lastSeenAt"));
        }
        assertTrue(f.gateway.isOnline("helmet-a"));
        assertEquals("STALE", f.gateway.status("helmet-a").getString("locationFreshness"));
    }

    @Test void observedRelativeAltitudeReachesLiveStatusWithoutInventingAGpsFix() {
        Fixture f = new Fixture();
        Session device = session();
        f.gateway.receive(device, login("helmet-a"));
        JSONObject reply = f.gateway.receive(device,
                "{\"act\":\"ca_report_location\",\"bat_l\":51,\"is_weared\":1,"
                + "\"gps_level\":-1,\"x_point\":0,\"y_point\":0,\"Relative_altitude\":\"-0.18\"}");
        assertTrue(reply.getBooleanValue("status"));
        JSONObject status = f.gateway.status("helmet-a");
        assertEquals("-0.18", status.getString("relativeAltitude"));
        assertEquals(51, status.getIntValue("battery"));
        assertNull(status.get("latitude"));
        assertNull(status.get("longitude"));
    }

    @Test void replacedSessionCannotReportOrDisconnectNewSessionAndNoCommandFallsBack() throws Exception {
        Fixture f = new Fixture();
        Session old = session(), replacement = session(), other = session();
        assertTrue(f.gateway.receive(old, login("helmet-a")).getBooleanValue("status"));
        assertTrue(f.gateway.receive(other, login("helmet-b")).getBooleanValue("status"));
        assertTrue(f.gateway.receive(replacement, login("helmet-a")).getBooleanValue("status"));
        f.gateway.disconnected(old);
        assertTrue(f.gateway.isOnline("helmet-a"));
        assertFalse(f.gateway.receive(old, "{\"act\":\"ca_report_location\",\"bat_l\":50}").getBooleanValue("status"));
        assertFalse(f.gateway.receive(replacement,
                "{\"act\":\"ca_report_location\",\"device_id\":\"helmet-b\",\"bat_l\":50}").getBooleanValue("status"));
        verify(f.telemetry, never()).receive(any(), any());
        f.gateway.disconnected(replacement);
        assertThrows(IllegalStateException.class, () -> f.gateway.sendCommand("helmet-a", new JSONObject()));
        verify(other.getBasicRemote(), never()).sendText(anyString());
    }

    @Test void onlyRealReportsUpdateReadingsAndLocationAgeSurvivesNoGpsHeartbeat() {
        Fixture f = new Fixture();
        Session device = session();
        f.gateway.receive(device, login("helmet-a"));
        assertNull(f.gateway.status("helmet-a").get("battery"));
        assertNull(f.gateway.status("helmet-a").get("latitude"));
        f.gateway.receive(device, "{\"act\":\"ca_report_location\",\"bat_l\":73,\"is_weared\":1,\"x_point\":35,\"y_point\":112}");
        String locationAt = f.gateway.status("helmet-a").getString("locationReportedAt");
        f.clock.advance(20);
        f.gateway.receive(device, "{\"act\":\"ca_report_location\",\"bat_l\":72}");
        JSONObject current = f.gateway.status("helmet-a");
        assertEquals(72, current.getIntValue("battery"));
        assertEquals(1, current.getIntValue("isWeared"));
        assertEquals(locationAt, current.getString("locationReportedAt"));
        assertNotEquals(locationAt, current.getString("lastSeenAt"));
        f.clock.advance(26);
        f.gateway.receive(device, "{\"act\":\"ca_report_location\",\"bat_l\":71}");
        assertTrue(f.gateway.isOnline("helmet-a"));
        assertEquals("STALE", f.gateway.status("helmet-a").getString("locationFreshness"));
        Session replacement = session();
        f.gateway.receive(replacement, login("helmet-a"));
        JSONObject reconnected = f.gateway.status("helmet-a");
        assertEquals(71,reconnected.getIntValue("battery"));
        assertEquals(1,reconnected.getIntValue("isWeared"));
        assertEquals("35",reconnected.getString("latitude"));
        assertEquals(locationAt,reconnected.getString("locationReportedAt"));
        assertEquals("STALE", reconnected.getString("batteryFreshness"));
        assertEquals("STALE", reconnected.getString("isWearedFreshness"));
        assertEquals("STALE", reconnected.getString("locationFreshness"));
        f.clock.advance(46);
        assertFalse(f.gateway.isOnline("helmet-a"));
        assertEquals("STALE", f.gateway.status("helmet-a").getString("freshness"));
        f.gateway.expireConnections();
        assertFalse(f.gateway.receive(device, "{\"act\":\"ca_report_location\"}").getBooleanValue("status"));
    }

    @Test void disabledAndUnregisteredDevicesNeverBecomeOnline() {
        Fixture f = new Fixture();
        Session device = session();
        assertFalse(f.gateway.receive(device, login("unregistered")).getBooleanValue("status"));
        verify(f.telemetry, never()).connection(any(), anyBoolean());
        f.properties.setEnabled(false);
        assertFalse(f.gateway.receive(device, login("helmet-a")).getBooleanValue("status"));
        assertFalse(f.gateway.isOnline("helmet-a"));
        verify(f.telemetry, never()).connection(any(), anyBoolean());
    }

    @Test void configurationUsesFirmwareStringEncodingAndRequiresExplicitReachableBase() {
        Fixture f = new Fixture();
        DirectHelmetConfigController controller = new DirectHelmetConfigController(f.properties, f.gateway);
        assertFalse(controller.configuration("config", "get_config", "helmet-a").getBooleanValue("status"));
        f.properties.setPublicBaseUrl("https://helmet.example.test");
        JSONObject result = controller.configuration("config", "get_config", "helmet-a");
        assertTrue(result.getBooleanValue("status"));
        assertTrue(result.getJSONObject("data").get("config") instanceof String);
        JSONObject config = JSONObject.parseObject(result.getJSONObject("data").getString("config"));
        assertEquals("wss://helmet.example.test/wsHat", config.getString("ws_url"));
        assertEquals("https://helmet.example.test/api/", config.getString("api_url"));
        assertFalse(controller.configuration("config", "get_config", "unregistered").getBooleanValue("status"));
        when(f.telemetry.registered("device.01")).thenReturn(new SafetyHatInfo());
        assertTrue(controller.configuration("config", "get_config", "device.01").getBooleanValue("status"));
        assertFalse(controller.deviceRequest("image", "save_image").getBooleanValue("status"));
    }

    private static JSONObject locationReport(Object type, Object satelliteStatus) {
        JSONObject report = new JSONObject();
        report.put("act", "ca_report_location");
        report.put("x_point", "35.466123"); report.put("y_point", "112.574204");
        if (type != null) report.put("gps", type);
        if (satelliteStatus != null) report.put("gps_level", satelliteStatus);
        return report;
    }

    private static String login(String id) { return "{\"act\":\"ca_login\",\"device_id\":\"" + id + "\"}"; }
    private static Session session() {
        Session session = mock(Session.class);
        when(session.isOpen()).thenReturn(true);
        when(session.getBasicRemote()).thenReturn(mock(RemoteEndpoint.Basic.class));
        return session;
    }

    private static final class Fixture {
        final DirectHelmetProperties properties = new DirectHelmetProperties();
        final DirectHelmetTelemetryService telemetry = mock(DirectHelmetTelemetryService.class);
        final MutableClock clock = new MutableClock();
        final DirectHelmetGateway gateway;
        Fixture() {
            properties.setEnabled(true);
            for (String id : new String[]{"helmet-a", "helmet-b"}) {
                SafetyHatInfo hat = new SafetyHatInfo(); hat.setId(id.equals("helmet-a") ? 1L : 2L);
                hat.setHatNumber(id); hat.setCreateBy("direct-helmet"); hat.setDelFlag("0");
                when(telemetry.registered(id)).thenReturn(hat);
            }
            gateway = new DirectHelmetGateway(properties, telemetry, new DirectHelmetSessions(clock));
        }
    }
    private static final class MutableClock extends Clock {
        private Instant now = Instant.parse("2026-10-20T12:00:00Z");
        void advance(int seconds) { now = now.plusSeconds(seconds); }
        @Override public ZoneId getZone() { return ZoneId.of("UTC"); }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
}
