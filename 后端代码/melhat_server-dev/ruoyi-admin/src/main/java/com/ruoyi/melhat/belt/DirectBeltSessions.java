package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import javax.websocket.Session;
import java.time.Clock;
import java.time.Instant;
import java.util.*;

/** Live session ownership and receipt times are separate from persisted last-known readings. */
public final class DirectBeltSessions {
    private final Clock clock;
    private final Map<String, Connection> devices = new HashMap<>();
    private final Map<Session, String> identities = new IdentityHashMap<>();
    public DirectBeltSessions() { this(Clock.systemUTC()); }
    public DirectBeltSessions(Clock clock) { this.clock = clock; }
    public synchronized String identity(Session session) { return identities.get(session); }
    public synchronized Session register(String deviceId, Session session) {
        String bound = identity(session);
        if (bound != null && !bound.equals(deviceId)) throw new IllegalArgumentException("连接已经绑定其他设备");
        Connection old = devices.get(deviceId);
        Session replaced = old == null ? null : old.session;
        if(replaced==session)return null;
        if (replaced != null && replaced != session) identities.remove(replaced);
        devices.put(deviceId, new Connection(session, clock.instant()));
        identities.put(session, deviceId);
        return replaced == session ? null : replaced;
    }
    public synchronized JSONObject preview(Session session, DirectBeltMessage message, DirectBeltProperties properties) {
        Connection connection = require(session);
        JSONObject next = new JSONObject(connection.telemetry);
        // A partial heartbeat must not renew a safety reading that was omitted from this report.
        if ("ca_report_location".equals(message.act)) {
            for (String field : new String[]{"battery", "isWeared", "hangerAStatus", "hangerBStatus", "relativeAltitude",
                    "altitude", "gpsAltitude", "ignoreHookAlarm", "inUse", "networkType", "networkStrength", "deviceReportedAt"})
                next.put(field, null);
        }
        // SOS/alarm coordinates may be cached; they never update a live observation.
        if("ca_report_location".equals(message.act))next.putAll(message.telemetry);
        Instant now = clock.instant();
        if ("ca_report_location".equals(message.act)) next.put("telemetryReportedAt", now.toString());
        if ("ca_report_location".equals(message.act)&&message.hasLocation()) {next.put("locationReportedAt", now.toString());next.put("locationTimeBasis","RECEIVED_AT");}
        return decorate(next, now, true, properties);
    }
    public synchronized void heard(Session session, JSONObject persisted) {
        Connection connection = require(session);
        connection.lastSeen = Instant.parse(persisted.getString("lastSeenAt"));
        connection.telemetry = new JSONObject(persisted);
    }
    public synchronized String disconnect(Session session) {
        String id = identities.remove(session);
        Connection connection = devices.get(id);
        if (connection == null || connection.session != session) return null;
        connection.session = null;
        return id;
    }
    public synchronized List<Session> expired(DirectBeltProperties properties) {
        List<Session> result = new ArrayList<>();
        for (Connection connection : devices.values())
            if (connection.session != null && !current(connection, properties)) result.add(connection.session);
        return result;
    }
    public synchronized JSONObject status(String id, DirectBeltProperties properties) {
        Connection connection = devices.get(id);
        return decorate(connection == null ? new JSONObject() : new JSONObject(connection.telemetry),
                connection == null ? null : connection.lastSeen, current(connection, properties), properties);
    }
    private JSONObject decorate(JSONObject status, Instant seen, boolean online, DirectBeltProperties properties) {
        online = online && properties.isEnabled();
        for (String field : new String[]{"battery", "isWeared", "hangerAStatus", "hangerBStatus", "relativeAltitude",
                "altitude", "gpsAltitude", "ignoreHookAlarm", "longitude", "latitude", "locationReportedAt", "deviceReportedAt"})
            if (!status.containsKey(field)) status.put(field, null);
        status.put("online", online); status.put("enabled", properties.isEnabled());
        status.put("freshness", online ? "CURRENT" : seen == null ? "UNKNOWN" : "STALE");
        status.put("lastSeenAt", seen == null ? null : seen.toString());
        String locationAt = status.getString("locationReportedAt");
        boolean locationFresh = online && locationAt != null
                && Instant.parse(locationAt).plusSeconds(properties.getHeartbeatTimeoutSeconds()).isAfter(clock.instant());
        status.put("locationFreshness", locationFresh ? "CURRENT" : locationAt == null ? "UNKNOWN" : "STALE");
        String telemetryAt = status.getString("telemetryReportedAt");
        boolean telemetryFresh = online && telemetryAt != null
                && Instant.parse(telemetryAt).plusSeconds(properties.getHeartbeatTimeoutSeconds()).isAfter(clock.instant());
        status.put("telemetryFreshness", telemetryFresh ? "CURRENT" : telemetryAt == null ? "UNKNOWN" : "STALE");
        status.put("worn", telemetryFresh ? properties.worn(status.getString("isWeared")) : null);
        status.put("hookAEngaged", telemetryFresh ? properties.hooked(status.getString("hangerAStatus")) : null);
        status.put("hookBEngaged", telemetryFresh ? properties.hooked(status.getString("hangerBStatus")) : null);
        status.put("wearMappingConfirmed", properties.wearMappingConfirmed());
        status.put("hookMappingConfirmed", properties.hookMappingConfirmed());
        status.put("communicationProtocol", "WEBSOCKET");
        JSONArray capabilities = new JSONArray();
        Collections.addAll(capabilities, "battery", "wear", "hooks", "height", "location", "alarm", "sos");
        status.put("capabilities", capabilities);
        status.put("mediaAvailable", false);
        return status;
    }
    private boolean current(Connection connection, DirectBeltProperties properties) {
        return connection != null && connection.session != null && connection.session.isOpen()
                && connection.lastSeen.plusSeconds(properties.getHeartbeatTimeoutSeconds()).isAfter(clock.instant());
    }
    private Connection require(Session session) {
        Connection connection = devices.get(identities.get(session));
        if (connection == null || connection.session != session) throw new IllegalArgumentException("请先登录设备");
        return connection;
    }
    private static final class Connection {
        Session session;
        Instant lastSeen;
        JSONObject telemetry = new JSONObject();
        Connection(Session session, Instant lastSeen) { this.session = session; this.lastSeen = lastSeen; }
    }
}
