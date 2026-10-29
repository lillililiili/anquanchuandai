package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.DirectBeltAccess;
import com.ruoyi.guardian.DirectBeltTelemetryService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import javax.websocket.CloseReason;
import javax.websocket.Session;
import java.io.IOException;
import java.time.Instant;

@Component
public class DirectBeltGateway implements DirectBeltAccess {
    private static final Logger LOG = LoggerFactory.getLogger(DirectBeltGateway.class);
    private final DirectBeltProperties properties;
    private final DirectBeltTelemetryService telemetry;
    private final DirectBeltSessions sessions;
    @Autowired(required=false) private com.ruoyi.guardian.WearableReportDelivery reports;
    @Autowired
    public DirectBeltGateway(DirectBeltProperties properties, @Lazy DirectBeltTelemetryService telemetry) {
        this(properties, telemetry, new DirectBeltSessions());
    }
    DirectBeltGateway(DirectBeltProperties properties, DirectBeltTelemetryService telemetry, DirectBeltSessions sessions) {
        this.properties = properties; this.telemetry = telemetry; this.sessions = sessions;
    }
    public boolean isEnabled() { return properties.isEnabled(); }
    public long idleTimeoutMillis() { return (properties.getHeartbeatTimeoutSeconds() + 5L) * 1000L; }
    public boolean supports(String id) { return telemetry.registered(id) != null; }
    // Called while GuardianStore is locked: never look up registration or acquire the gateway monitor here.
    @Override public JSONObject status(String id) { return sessions.status(id, properties); }

    public synchronized JSONObject receive(Session session, String json) {
        if (!isEnabled()) return response("error", false, "安全带直连接入未启用");
        DirectBeltMessage message;
        try { message = DirectBeltMessage.parse(json); }
        catch (IllegalArgumentException error) { return response("error", false, error.getMessage()); }
        try {
            if ("ca_login".equals(message.act)) return login(session, message);
            String id = sessions.identity(session);
            if (id == null) return response(message.act, false, "请先登录设备");
            if (!status(id).getBooleanValue("online")) {
                disconnected(session); close(session, "设备心跳超时，请重新登录");
                return response(message.act, false, "设备心跳超时，请重新登录");
            }
            if (message.deviceId != null && !id.equals(message.deviceId))
                return response(message.act, false, "device_id/imei 与当前连接身份不符");
            if (!supports(id)) {
                disconnected(session); close(session, "设备登记已停用");
                return response(message.act, false, "设备未登记或已停用");
            }
            boolean alarm = "ca_sos".equals(message.act), sos = "ca_sip_sos".equals(message.act);
            if (!"ca_report_location".equals(message.act) && !alarm && !sos)
                return response(message.act, false, "尚不支持此设备消息");
            JSONObject next = sessions.preview(session, message, properties);
            String rawType=alarm?(message.alarmType==null?"unknown":message.alarmType):null;
            String timestamp=message.deviceReportedAt==null?next.getString("lastSeenAt"):message.deviceReportedAt;
            if(reports==null)telemetry.receive(id,next,rawType,timestamp,sos);else reports.belt(id,json,next,rawType,timestamp,sos);
            sessions.heard(session, next);
            JSONObject result = response(message.act, true, "上报成功！");
            if ("ca_report_location".equals(message.act)) {
                result.put("f_id", ""); result.put("f_key", ""); result.put("bt_beacon", ""); result.put("report_time", 0);
            }
            if (sos) {
                result.put("media_status", "unavailable");
                result.put("msg", "SOS 已记录；SIP 通话未接入");
            }
            return result;
        } catch (IllegalArgumentException error) {
            return response(message.act, false, error.getMessage());
        } catch (RuntimeException error) {
            LOG.warn("Direct belt persistence failed; action={}, errorType={}", message.act, error.getClass().getSimpleName());
            return response(message.act, false, "上报保存失败，请重试");
        }
    }
    private JSONObject login(Session session, DirectBeltMessage message) {
        if (message.deviceId == null) return response(message.act, false, "缺少 device_id");
        String bound = sessions.identity(session);
        if (bound != null && !bound.equals(message.deviceId)) return response(message.act, false, "连接已经绑定其他设备");
        JSONObject device = telemetry.registered(message.deviceId);
        if (device == null) return response(message.act, false, "设备未预先登记为直连安全带");
        Session previous = sessions.register(message.deviceId, session);
        if (previous != null) close(previous, "设备已建立新连接");
        try { if(reports==null||!reports.paused())telemetry.snapshot(message.deviceId, status(message.deviceId)); }
        catch (RuntimeException error) { sessions.disconnect(session); throw error; }
        JSONObject result = response(message.act, true, "登陆成功！");
        JSONObject data = new JSONObject();
        data.put("device_id", message.deviceId);
        data.put("user_id", device.get("userId") == null ? "" : device.get("userId"));
        data.put("user_name", device.get("userName") == null ? "" : device.get("userName"));
        result.put("data", data);
        return result;
    }
    public synchronized void disconnected(Session session) {
        String id = sessions.disconnect(session);
        if (id == null) return;
        try { if(reports==null||!reports.paused())telemetry.snapshot(id, status(id)); }
        catch (RuntimeException error) { LOG.warn("Direct belt offline snapshot could not be saved"); }
    }
    @Scheduled(fixedDelay = 5000)
    public synchronized void expireConnections() {
        for (Session session : sessions.expired(properties)) {
            disconnected(session); close(session, "设备心跳超时，请重新登录");
        }
    }
    static JSONObject response(String command, boolean success, String message) {
        JSONObject result = new JSONObject();
        result.put("cmd", command); result.put("status", success); result.put("msg", message);
        return result;
    }
    static void close(Session session, String reason) {
        try {
            if (session != null && session.isOpen()) session.close(new CloseReason(CloseReason.CloseCodes.NORMAL_CLOSURE, reason));
        } catch (IOException ignored) { }
    }
}
