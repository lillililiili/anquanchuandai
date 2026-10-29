package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import javax.websocket.Session;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;

/** Exact session ownership prevents late messages and late close events from replacing a newer login. */
public final class DirectHelmetSessions {
    private final Clock clock;
    private final Map<String, Connection> devices = new HashMap<>();
    private final Map<Session, String> identities = new IdentityHashMap<>();

    public DirectHelmetSessions() { this(Clock.systemUTC()); }
    public DirectHelmetSessions(Clock clock) { this.clock = clock; }

    public synchronized Session register(String deviceId, Session session) {
        String previousIdentity = identities.get(session);
        if (previousIdentity != null && !previousIdentity.equals(deviceId))
            throw new IllegalArgumentException("连接已经绑定其他设备");
        Connection previous = devices.get(deviceId);
        Session replaced = previous == null ? null : previous.session;
        // A repeated login on the same socket is not a new observation or a new session.
        if (replaced == session) return null;
        if (replaced != null && replaced != session) identities.remove(replaced);
        Connection next = new Connection(session, clock.instant());
        if(previous!=null)next.telemetry.putAll(previous.telemetry);
        devices.put(deviceId, next);
        identities.put(session, deviceId);
        return replaced == session ? null : replaced;
    }

    public synchronized String identity(Session session) { return identities.get(session); }

    public synchronized void heard(Session session, DirectHelmetMessage message) {
        String deviceId = identities.get(session);
        Connection connection = devices.get(deviceId);
        if (connection == null || connection.session != session)
            throw new IllegalArgumentException("请先登录设备");
        connection.lastSeen = clock.instant();
        if ("ca_report_location".equals(message.act)) {
            observed(connection, "battery", message.battery);
            observed(connection, "isWeared", message.isWeared);
            observed(connection, "inUse", message.inUse);
            observed(connection, "networkType", message.networkType);
            observed(connection, "networkStrength", message.networkStrength);
            observed(connection, "relativeAltitude", message.relativeAltitude);
            observed(connection, "firmware", message.firmware);
        }
        if ("ca_report_location".equals(message.act) && message.hasLocation()) {
            connection.telemetry.put("longitude", message.longitude);
            connection.telemetry.put("latitude", message.latitude);
            connection.telemetry.put("locationReportedAt", connection.lastSeen.toString());
            connection.telemetry.put("coordinateSystem", "UNKNOWN");
            connection.telemetry.put("locationSource", message.locationSource);
            connection.telemetry.put("gps", message.gps);
            connection.telemetry.put("accuracyMeters", message.accuracyMeters);
            connection.observed.add("location");
        }
    }

    public synchronized String disconnect(Session session) {
        String deviceId = identities.remove(session);
        Connection current = devices.get(deviceId);
        if (current == null || current.session != session) return null;
        current.session = null;
        return deviceId;
    }

    public synchronized Session session(String deviceId, int timeoutSeconds) {
        Connection connection = devices.get(deviceId);
        return current(connection, timeoutSeconds) ? connection.session : null;
    }

    public synchronized List<Session> expired(int timeoutSeconds) {
        List<Session> result = new ArrayList<>();
        for (Connection connection : devices.values()) {
            if (connection.session != null && !current(connection, timeoutSeconds)) result.add(connection.session);
        }
        return result;
    }

    public synchronized JSONObject status(String deviceId, int timeoutSeconds) {
        Connection connection = devices.get(deviceId);
        JSONObject status = connection == null ? new JSONObject() : new JSONObject(connection.telemetry);
        for (String field : new String[]{"battery", "isWeared", "longitude", "latitude", "locationReportedAt"}) {
            if (!status.containsKey(field)) status.put(field, null);
        }
        boolean online = current(connection, timeoutSeconds);
        status.put("online", online);
        status.put("freshness", online ? "CURRENT" : connection == null ? "UNKNOWN" : "STALE");
        status.put("lastSeenAt", connection == null ? null : connection.lastSeen.toString());
        String locationAt = status.getString("locationReportedAt");
        boolean freshLocation = online && connection.observed.contains("location") && locationAt != null
                && Instant.parse(locationAt).plusSeconds(timeoutSeconds).isAfter(clock.instant());
        status.put("locationFreshness", freshLocation ? "CURRENT" : locationAt == null ? "UNKNOWN" : "STALE");
        for (String field : new String[]{"battery", "isWeared", "inUse", "networkType", "networkStrength", "relativeAltitude"}) {
            String at = status.getString(field + "ReportedAt");
            status.put(field + "Freshness", at == null ? "UNKNOWN" : online && connection.observed.contains(field)
                    && Instant.parse(at).plusSeconds(timeoutSeconds).isAfter(clock.instant()) ? "CURRENT" : "STALE");
        }
        if (!status.containsKey("coordinateSystem")) status.put("coordinateSystem", "UNKNOWN");
        status.put("communicationProtocol", "SIP");
        JSONArray capabilities = new JSONArray();
        capabilities.add("battery"); capabilities.add("wear"); capabilities.add("location");
        capabilities.add("alarm"); capabilities.add("sos");
        status.put("capabilities", capabilities);
        status.put("mediaAvailable", false);
        status.put("mediaUnavailableReason", "尚未配置并验证 SRS 推流和 FreeSWITCH SIP 媒体链路");
        return status;
    }

    private boolean current(Connection connection, int timeoutSeconds) {
        return connection != null && connection.session != null && connection.session.isOpen()
                && connection.lastSeen.plusSeconds(timeoutSeconds).isAfter(clock.instant());
    }

    private static void observed(Connection connection, String field, Object value) {
        if (value == null) return;
        connection.telemetry.put(field, value);
        connection.telemetry.put(field + "ReportedAt", connection.lastSeen.toString());
        connection.observed.add(field);
    }

    private static final class Connection {
        private Session session;
        private Instant lastSeen;
        private final JSONObject telemetry = new JSONObject();
        private final java.util.Set<String> observed = new java.util.HashSet<>();
        private Connection(Session session, Instant lastSeen) { this.session = session; this.lastSeen = lastSeen; }
    }
}
