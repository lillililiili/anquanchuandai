package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.DirectHelmetAccess;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import javax.websocket.CloseReason;
import javax.websocket.Session;
import java.io.IOException;

/** Runtime state is backed by a live device-owned WebSocket, never by seeded database status. */
@Component
public class DirectHelmetGateway implements DirectHelmetAccess {

    @Autowired(required=false) private com.ruoyi.cluster.DeviceOwnership ownership;
    @Autowired(required=false) private com.ruoyi.cluster.DeviceCommandRouter router;
    private final java.util.Map<Session,com.ruoyi.cluster.OwnerToken> ownerTokens=java.util.Collections.synchronizedMap(new java.util.IdentityHashMap<>());
    private boolean clustered(){return ownership!=null&&ownership.enabled();}
    @javax.annotation.PostConstruct public void clusterStart(){if(clustered()){sessions.useClock(ownership.clock());router.register("helmet",this::sendLocal);}}

    private static final Logger LOG = LoggerFactory.getLogger(DirectHelmetGateway.class);
    private final DirectHelmetProperties properties;
    private final DirectHelmetTelemetryService telemetry;
    private final DirectHelmetSessions sessions;
    @Autowired(required=false)
    private org.springframework.beans.factory.ObjectProvider<HelmetMediaService> mediaProvider;
    @Autowired(required=false) private com.ruoyi.guardian.WearableReportDelivery reports;

    @Autowired
    public DirectHelmetGateway(DirectHelmetProperties properties, @Lazy DirectHelmetTelemetryService telemetry) {
        this(properties, telemetry, new DirectHelmetSessions());
    }

    DirectHelmetGateway(DirectHelmetProperties properties, DirectHelmetTelemetryService telemetry,
            DirectHelmetSessions sessions) {
        this.properties = properties; this.telemetry = telemetry; this.sessions = sessions;
    }

    @Override public boolean isEnabled() { return properties.isEnabled(); }
    public long idleTimeoutMillis() { return (properties.getHeartbeatTimeoutSeconds() + 5L) * 1000L; }
    @Override public boolean supports(String deviceId) { return telemetry.registered(deviceId) != null; }
    @Override public boolean isOnline(String deviceId) {
        return isEnabled() && supports(deviceId) && (clustered()?ownership.readPresence("helmet",deviceId).getBooleanValue("online"):sessions.session(deviceId, properties.getHeartbeatTimeoutSeconds()) != null);
    }

    @Override public JSONObject status(String deviceId) {
        JSONObject status = clustered()?ownership.readPresence("helmet",deviceId):sessions.status(deviceId, properties.getHeartbeatTimeoutSeconds());
        if (!isEnabled()) {
            status.put("online", false); status.put("freshness", "UNKNOWN");
        }
        status.put("enabled", isEnabled());
        telemetry.enrichStatus(deviceId, status);
        HelmetMediaService media=mediaProvider==null?null:mediaProvider.getIfAvailable();
        if(media!=null){status.putAll(media.capabilities(deviceId));com.alibaba.fastjson2.JSONArray capabilities=status.getJSONArray("capabilities");
            if(capabilities==null){capabilities=new com.alibaba.fastjson2.JSONArray();status.put("capabilities",capabilities);}
            if(status.getBooleanValue("voiceAvailable"))capabilities.add("intercom");
            if(status.getBooleanValue("broadcastAvailable"))capabilities.add("tts");
            if(status.getBooleanValue("mediaAvailable"))capabilities.add("video");}
        if(status.getBooleanValue("mediaAvailable"))status.remove("mediaUnavailableReason");
        else status.put("mediaUnavailableReason","unconfigured".equals(status.getString("mediaStatus"))?"媒体服务尚未配置":"媒体服务当前未就绪；设备定位和告警可继续上报");
        return status;
    }

    // DirectHelmetSessions owns its identity/state lock. Do not hold the command-send
    // lock while persisting media receipts (the command service can send concurrently).
    public JSONObject receive(Session session, String json) {
        if (!isEnabled()) return response("error", false, "一体式安全帽直连接入未启用");
        DirectHelmetMessage message;
        try { message = DirectHelmetMessage.parse(json); }
        catch (IllegalArgumentException error) { return response("error", false, error.getMessage()); }
        try {
            if ("ca_login".equals(message.act)) return login(session, message);
            String deviceId = sessions.identity(session);
            if (deviceId == null) return response(message.act, false, "请先登录设备");
            if (message.deviceId != null && !deviceId.equals(message.deviceId))
                return response(message.act, false, "device_id 与当前连接身份不符");
            SafetyHatInfo hat = telemetry.registered(deviceId);
            if (hat == null) {
                disconnected(session); close(session, "设备登记已停用");
                return response(message.act, false, "设备未登记或已停用");
            }
            HelmetMediaService media=mediaProvider==null?null:mediaProvider.getIfAvailable();
            if(java.util.Arrays.asList("ca_upload_photo","upload_video_success","push_to_client").contains(message.act)) {
                if(reports!=null) {
                    if(clustered())reports.helmetOwned(ownerTokens.get(session),json,sessions.preview(session,message,properties.getHeartbeatTimeoutSeconds()),true);else reports.helmetMedia(deviceId,json);
                    sessions.heard(session,message);
                    return response(message.act,true,"回执已保存，处理结果以业务记录为准");
                }
                if(media!=null&&media.receipt(deviceId,JSONObject.parseObject(json))) {
                    sessions.heard(session,message);
                    return response(message.act,true,"回执已保存");
                }
            }
            if (!"ca_report_location".equals(message.act) && !"ca_sos".equals(message.act)
                    && !"ca_sip_sos".equals(message.act))
                return response(message.act, false, "当前接入尚不支持此设备消息");
            boolean processed=true;
            if(clustered()){if(reports==null)throw new IllegalStateException("持久接收服务未就绪");processed=reports.helmetOwned(ownerTokens.get(session),json,sessions.preview(session,message,properties.getHeartbeatTimeoutSeconds()),false);}
            else if(reports==null)telemetry.receive(hat,message);else processed=reports.helmet(deviceId,json);
            sessions.heard(session, message);
            if(processed)publish(deviceId);
            JSONObject result = response(message.act, true, "上报成功！");
            if ("ca_sip_sos".equals(message.act)) {
                result.put("media_status",media==null?"unconfigured":media.capabilities(deviceId).getString("mediaStatus"));
                result.put("msg", "SOS 已记录，请等待值守人员处理；本回执不代表通话已接通");
            }
            return result;
        } catch (IllegalArgumentException error) {
            return response(message.act, false, error.getMessage());
        } catch (RuntimeException error) {
            LOG.warn("Direct helmet message failed; action={}, errorType={}", message.act, error.getClass().getSimpleName());
            return response(message.act, false, "上报保存失败，请重试");
        }
    }

    private JSONObject login(Session session, DirectHelmetMessage message) {
        if (message.deviceId == null) return response(message.act, false, "缺少 device_id");
        String bound = sessions.identity(session);
        if (bound != null && !bound.equals(message.deviceId))
            return response(message.act, false, "连接已经绑定其他设备");
        SafetyHatInfo hat = telemetry.registered(message.deviceId);
        if (hat == null) return response(message.act, false, "设备未预先登记为一体式安全帽");
        if(clustered()){
            if(bound!=null){if(!ownership.current(ownerTokens.get(session)))throw new IllegalArgumentException("连接所有权已变化，请重新登录");}
            else ownerTokens.put(session,ownership.claimLogin("helmet",message.deviceId,session.getId(),properties.getHeartbeatTimeoutSeconds()*1000L,sessions.status(message.deviceId,properties.getHeartbeatTimeoutSeconds())));
        }
        if(!clustered()&&(reports==null||!reports.paused()))telemetry.connection(hat, true);
        Session replaced = sessions.register(message.deviceId, session);
        if (replaced != null) close(replaced, "设备已建立新连接");
        if(reports==null||!reports.paused())publish(message.deviceId);
        JSONObject result = response(message.act, true, "登陆成功！");
        JSONObject data = new JSONObject();
        data.put("device_id", message.deviceId);
        data.put("user_id", hat.getBindUserId() == null ? "" : hat.getBindUserId());
        data.put("user_name", hat.getBindUserName() == null ? "" : hat.getBindUserName());
        HelmetMediaService media=mediaProvider==null?null:mediaProvider.getIfAvailable();
        if(media!=null)try {media.rememberDevice(message.deviceId);JSONObject sip=media.sipInfo(message.deviceId);if(sip!=null)result.put("sip_info",sip);}
        catch(RuntimeException error){LOG.warn("Helmet media account unavailable; telemetry login remains enabled");}
        result.put("data", data);
        return result;
    }

    public synchronized void disconnected(Session session) {
        com.ruoyi.cluster.OwnerToken token=ownerTokens.remove(session);
        String deviceId = sessions.disconnect(session);
        if(clustered()&&!ownership.release(token))return;
        if (deviceId == null) return;
        try {
            SafetyHatInfo hat = telemetry.registered(deviceId);
            if (hat != null&&!clustered()&&(reports==null||!reports.paused())) telemetry.connection(hat, false);
        }
        catch (RuntimeException error) { LOG.warn("Direct helmet offline state persistence failed"); }
        if(reports==null||!reports.paused())publish(deviceId);
    }

    @Scheduled(fixedDelay = 5000)
    public synchronized void expireConnections() {
        if (!isEnabled()) return;
        if(clustered()){java.util.List<Session> stale=new java.util.ArrayList<>();synchronized(ownerTokens){for(java.util.Map.Entry<Session,com.ruoyi.cluster.OwnerToken> e:ownerTokens.entrySet())if(!ownership.current(e.getValue()))stale.add(e.getKey());}for(Session session:stale){disconnected(session);close(session,"设备连接所有权或租约已失效");}}
        if(clustered()&&(reports==null||!reports.paused()))for(String id:ownership.expiredDeviceIds("helmet"))publish(id);
        for (Session session : sessions.expired(properties.getHeartbeatTimeoutSeconds())) {
            disconnected(session);
            close(session, "设备心跳超时，请重新登录");
        }
    }

    /** Exact recipient only; no broadcast or fallback to an unrelated device. */
    public synchronized void sendCommand(String deviceId, JSONObject command) throws IOException {
        if(clustered()){router.send(deviceId,command,"legacy:"+command.getString("cmd"));return;}
        if (!isOnline(deviceId)) throw new IllegalStateException("设备不在线，未下发命令");
        Session session = sessions.session(deviceId, properties.getHeartbeatTimeoutSeconds());
        if (session == null) throw new IllegalStateException("设备心跳超时，未下发命令");
        synchronized (session) { session.getBasicRemote().sendText(command.toJSONString()); }
    }

    public void sendCommand(String deviceId,JSONObject command,String purpose) throws IOException {if(clustered())router.send(deviceId,command,purpose);else sendCommand(deviceId,command);}
    private void sendLocal(com.ruoyi.cluster.OwnerToken token,String wire,long timeout,Runnable validateAttempt) throws Exception {
        Session session=sessions.session(token.deviceId,properties.getHeartbeatTimeoutSeconds());
        com.ruoyi.cluster.OwnerToken local=session==null?null:ownerTokens.get(session);
        if(local==null||!local.connectionToken.equals(token.connectionToken)||!ownership.current(token))throw new IllegalStateException("本地目标连接已失效");
        validateAttempt.run();
        session.getAsyncRemote().setSendTimeout(timeout);
        try{session.getAsyncRemote().sendText(wire).get(timeout,java.util.concurrent.TimeUnit.MILLISECONDS);}
        catch(Exception e){close(session,"发送结果未确认，请重新连接");throw e;}
    }
    private void publish(String deviceId) {
        try { telemetry.snapshot(deviceId, status(deviceId)); }
        catch (RuntimeException error) { LOG.warn("Direct helmet snapshot update failed"); }
    }

    static JSONObject response(String command, boolean success, String message) {
        JSONObject result = new JSONObject();
        result.put("cmd", command); result.put("status", success); result.put("msg", message);
        return result;
    }

    static void close(Session session, String reason) {
        try {
            if (session != null && session.isOpen())
                session.close(new CloseReason(CloseReason.CloseCodes.NORMAL_CLOSURE, reason));
        } catch (IOException ignored) { }
    }
}
