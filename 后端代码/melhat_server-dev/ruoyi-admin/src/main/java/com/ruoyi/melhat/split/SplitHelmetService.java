package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.PersonEquipmentContext;
import com.ruoyi.guardian.WearableMaintenance;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.util.*;
import org.apache.commons.codec.digest.DigestUtils;
import static com.ruoyi.melhat.split.SplitTelemetry.*;

/** Split helmets have their own protocol, journals and device leases; no legacy device is adopted. */
@Service
public class SplitHelmetService {
    public static final String PROTOCOL="ZLM_WEBRTC";
    private final SplitHelmetProperties properties;
    private final SplitHelmetClient client;
    private final SplitHelmetStore store;
    private final ObjectProvider<SplitHelmetBridge> bridges;
    private final java.util.concurrent.ConcurrentHashMap<String,java.util.concurrent.locks.ReentrantReadWriteLock> signalLocks=new java.util.concurrent.ConcurrentHashMap<>();
    private final java.util.concurrent.ConcurrentHashMap<String,Object> commandLocks=new java.util.concurrent.ConcurrentHashMap<>();
    private java.util.concurrent.locks.ReentrantReadWriteLock signalLock(String id){return signalLocks.computeIfAbsent(id,k->new java.util.concurrent.locks.ReentrantReadWriteLock(true));}
    @Autowired(required=false) private ObjectProvider<PersonEquipmentContext> equipment;
    @Autowired(required=false) private WearableMaintenance maintenance;
    public SplitHelmetService(SplitHelmetProperties p,SplitHelmetClient c,SplitHelmetStore s,ObjectProvider<SplitHelmetBridge>b){properties=p;client=c;store=s;bridges=b;}
    public boolean enabled(){return properties.isEnabled();}
    public boolean supports(String sn){return enabled()&&properties.allowed().contains(sn)&&bridge()!=null&&bridge().isRegistered(sn);}
    public boolean ownsIdentity(String sn){return bridge()!=null&&bridge().ownsIdentity(sn);}
    private SplitHelmetBridge bridge(){return bridges.getIfAvailable();}
    private void require(String sn){if(!supports(sn))throw fail(409,"SPLIT_DEVICE_UNAVAILABLE","设备未登记为本平台管理的分体式安全帽");}
    /** This read deliberately never calls the ledger or GuardianStore (it is used inside their projection). */
    public JSONObject status(String sn){
        if(!enabled()||!properties.allowed().contains(sn))return null;
        JSONObject s=SplitTelemetry.view(store.state(sn),properties.getFreshnessSeconds(),System.currentTimeMillis());
        boolean ready=client.configured()&&Boolean.TRUE.equals(s.getBoolean("online"));
        s.put("mediaAvailable",ready);s.put("voiceAvailable",ready);s.put("broadcastAvailable",ready);s.put("mediaStatus",!client.configured()?"unconfigured":ready?"ready":"unavailable");
        s.put("capabilities",JSONArray.of("video","intercom","tts","take_photo","start_recording","stop_recording","list_recordings","set_watermark"));return s;
    }
    public JSONObject receive(String kind,JSONObject payload,String ingressId,String receivedAt){
        if(!enabled())throw fail(503,"SPLIT_DISABLED","分体帽接入未启用");
        if(!Arrays.asList("gnss","baro","deviceStatus","sosCall","sosCallEnd","sos").contains(kind))throw fail(404,"NOT_FOUND","回调类型不存在");
        if(payload==null||ingressId==null||!ingressId.matches("[A-Za-z0-9._:-]{8,100}"))throw fail(400,"INVALID_INGRESS","回调必须携带稳定的接收编号");
        long received;try{received=Instant.parse(receivedAt).toEpochMilli();if(received>System.currentTimeMillis()+300000||received<946684800000L)throw new IllegalArgumentException();}catch(Exception bad){throw fail(400,"INVALID_INGRESS_TIME","回调接收时间无效");}
        String sn=sn(payload.get("helmetSn"));require(sn);
        String fingerprint=DigestUtils.sha256Hex(kind+"\n"+receivedAt+"\n"+payload.toJSONString());
        JSONObject existing=store.inbox(ingressId);
        if(existing!=null){if(!fingerprint.equals(existing.getString("fingerprint")))throw fail(409,"INGRESS_CONFLICT","回调编号冲突");return obj("code",200,"message","accepted","duplicate",true);}
        String observed=SplitTelemetry.normalizeTimestamp(payload.get("timestamp"),received);
        JSONObject envelope=obj("ingressId",ingressId,"deviceId",sn,"kind",kind,"payload",copy(payload),"captured",bridge().capture(sn,receivedAt),"receivedAt",receivedAt,"receivedMillis",received,"observedAt",observed,"fingerprint",fingerprint);
        if(payload.get("timestamp")!=null){try{String raw=String.valueOf(payload.get("timestamp"));long t=raw.matches("[0-9]{10}|[0-9]{13}")?Long.parseLong(raw)*(raw.length()==10?1000L:1L):Instant.parse(raw).toEpochMilli();if(t>received+300000)envelope.put("timeAnomaly","FUTURE_TIME_USING_RECEIVED_AT");else if(t<946684800000L)envelope.put("timeAnomaly","INVALID_TIME_USING_RECEIVED_AT");}catch(RuntimeException invalid){envelope.put("timeAnomaly","INVALID_TIME_USING_RECEIVED_AT");}}
        try{SplitTelemetry.validate(kind,payload,received);}catch(com.ruoyi.guardian.AdminQueryService.QueryFailed invalid){envelope.put("processingState","REJECTED");envelope.put("validationError",invalid.errorCode);store.receive(envelope);store.rejected(ingressId);return obj("code",200,"message","accepted","processingState","REJECTED");}
        envelope.put("processingState","PENDING");store.receive(envelope);
        try{project(envelope);}catch(RuntimeException pending){/* Durable inbox is retried; acceptance is not a projection acknowledgement. */}
        return obj("code",200,"message","accepted","ingressId",ingressId);
    }
    private void project(JSONObject envelope){
        if("REJECTED".equals(envelope.getString("processingState"))){store.rejected(envelope.getString("ingressId"));return;}
        store.state(envelope.getString("deviceId"),s->SplitTelemetry.merge(s,envelope));
        bridge().ingest(copy(envelope));store.delivered(envelope.getString("ingressId"));
    }
    @Scheduled(initialDelay=15000,fixedDelay=10000)
    public void recover(){
        if(!enabled()||bridge()==null||maintenance!=null&&!maintenance.tryBeginWrite())return;
        try{
            for(JSONObject e:store.pending())try{project(e);}catch(RuntimeException ignored){}
            // Only cleanup is repeated. Never replay an uncertain create/capture/record/broadcast.
            for(JSONObject row:store.activeSessions())if(row.getLongValue("expiresMillis")<System.currentTimeMillis())try{end(row.getString("id"));}catch(RuntimeException ignored){}
            List<String> revokedSessions=new ArrayList<>();List<JSONObject> revokedRecordings=new ArrayList<>();
            if(equipment!=null&&equipment.getIfAvailable()!=null)equipment.getIfAvailable().withSessionAuthority(authority->{
                for(JSONObject row:store.activeSessions())for(Object raw:row.getJSONArray("recipients"))if(!authority.test(row.getString("actorId"),(JSONObject)raw)){revokedSessions.add(row.getString("id"));break;}
                for(JSONObject row:store.unfinishedCommands())if("start_recording".equals(row.getString("action"))&&row.getString("sid")!=null&&!row.containsKey("stopRequestedAt")&&!Arrays.asList("completed","stopped","failed").contains(row.getString("status"))&&!authority.test(row.getString("actorId"),row))revokedRecordings.add(row);
            });
            for(String id:revokedSessions)try{end(id);}catch(RuntimeException ignored){}
            for(JSONObject row:revokedRecordings)stopRevokedRecording(row);
            int checked=0;for(JSONObject row:store.unfinishedCommands())if("start_recording".equals(row.getString("action"))&&row.getString("sid")!=null&&!Arrays.asList("completed","stopped","failed").contains(row.getString("status"))&&System.currentTimeMillis()-row.getLongValue("lastStatusCheck")>=30000){refreshRecording(row);if(++checked>=10)break;}
        }finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private void stopRevokedRecording(JSONObject original){synchronized(commandLocks.computeIfAbsent(original.getString("deviceId"),k->new Object())){JSONObject row=store.command(original.getString("id"));if(row==null||row.containsKey("stopRequestedAt"))return;row.put("stopRequestedAt",Instant.now().toString());row.put("status","stop_unknown");row.put("stopReason","AUTHORITY_REVOKED");store.saveCommand(row);try{client.post("/api/monitor/record/stop",obj("sid",row.getString("sid")));row.put("status","stopping");store.saveCommand(row);}catch(RuntimeException unknown){/* Keep the durable attempt and SID; status reads can reconcile, controls never replay. */}}}
    @Scheduled(initialDelay=5000,fixedDelay=30000)
    public void poll(){
        if(!enabled()||bridge()==null||maintenance!=null&&!maintenance.tryBeginWrite())return;
        try{
            List<String> sns=new ArrayList<>();for(String sn:bridge().registered())if(properties.allowed().contains(sn))sns.add(sn);
            for(int from=0;from<sns.size();from+=100){List<String> group=sns.subList(from,Math.min(sns.size(),from+100));
                try{JSONArray result=client.online(group);Set<String> seen=new HashSet<>();List<JSONObject> valid=new ArrayList<>();
                    for(Object raw:result){if(!(raw instanceof JSONObject))throw new IllegalArgumentException();JSONObject r=(JSONObject)raw;String sn=sn(r.get("helmetSn"));String online=String.valueOf(r.get("online"));if(!group.contains(sn)||!seen.add(sn)||!Arrays.asList("0","1","true","false").contains(online))throw new IllegalArgumentException();valid.add(r);}
                    long now=System.currentTimeMillis();for(JSONObject r:valid){String sn=r.getString("helmetSn");store.state(sn,s->{s.put("vendorOnline",Arrays.asList("1","true").contains(String.valueOf(r.get("online"))));s.put("onlineUnknown",false);s.put("onlineReportedAt",Instant.ofEpochMilli(now).toString());return s;});}
                    for(String sn:group)if(!seen.contains(sn))unknownOnline(sn);
                }catch(RuntimeException ignored){for(String sn:group)unknownOnline(sn);/* Failure is unknown, never a fabricated offline or a fresh online. */}
            }
        }finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private void unknownOnline(String sn){store.state(sn,s->{s.put("onlineUnknown",true);s.put("onlineCheckedAt",Instant.now().toString());return s;});}
    public synchronized JSONObject create(String actor,JSONArray recipients,boolean video,String mode,String requestId){
        if(recipients==null||recipients.isEmpty()||recipients.size()>8)throw fail(400,"INVALID_CALL","请选择1至8顶分体式安全帽");
        if(actor==null||requestId==null||requestId.length()<8||requestId.length()>150||!Arrays.asList("preview","call").contains(mode))throw fail(400,"INVALID_CALL","会话参数无效");
        String key=DigestUtils.sha256Hex(requestId==null?"":requestId),fingerprint=DigestUtils.sha256Hex(recipients.toJSONString()+"|"+video+"|"+mode);
        JSONObject previous=store.sessionRequest(actor,key);if(previous!=null){if(!fingerprint.equals(previous.getString("fingerprint")))throw fail(409,"IDEMPOTENCY_CONFLICT","相同操作编号不能用于不同呼叫");return credentials(previous);}
        JSONArray ids=new JSONArray();Set<String> seen=new HashSet<>();
        for(Object raw:recipients){JSONObject r=(JSONObject)raw;String sn=sn(r.get("deviceId"));require(sn);if(!seen.add(sn))throw fail(400,"INVALID_CALL","安全帽不能重复");if(!Boolean.TRUE.equals(status(sn).getBoolean("online")))throw fail(409,"DEVICE_OFFLINE","安全帽未在线，未发送呼叫");ids.add(sn);}
        long now=System.currentTimeMillis();JSONObject row=obj("id","SPLIT-"+UUID.randomUUID(),"actorId",actor,"requestKey",key,"fingerprint",fingerprint,"status","requesting","mode",mode,"video",video,"recipients",JSON.parseArray(recipients.toJSONString()),"deviceIds",ids,"createdAt",Instant.ofEpochMilli(now).toString(),"expiresMillis",now+properties.getLeaseSeconds()*1000L,"remoteSessions",new JSONArray());
        store.acquire(row);
        try{
            JSONObject data=client.post("/api/webrtc/session",obj("helmetSnList",ids)).getJSONObject("data");
            if(data==null||!"webrtc".equalsIgnoreCase(data.getString("mediaType"))||!(data.get("sessions") instanceof JSONArray))throw new IllegalArgumentException();
            JSONArray remote=data.getJSONArray("sessions");Set<String> accepted=new HashSet<>();
            for(Object raw:remote){if(!(raw instanceof JSONObject))throw new IllegalArgumentException();JSONObject s=(JSONObject)raw;String sn=sn(s.get("helmetSn"));if(!ids.contains(sn)||!accepted.add(sn))throw new IllegalArgumentException();client.validateSignal(s.getString("playUrl"),sn,"play");client.validateSignal(s.getString("talkUrl"),sn,"talk");}
            row.put("remoteSessions",remote);row.put("status",accepted.isEmpty()?"failed":"offered");row.put("lastHeartbeatMillis",now);
            JSONArray skipped=new JSONArray();for(Object id:ids)if(!accepted.contains(String.valueOf(id))){skipped.add(obj("deviceId",id,"reason","厂家未返回此设备的会话"));store.releaseDevice(row.getString("id"),String.valueOf(id));}row.put("skipped",skipped);
            if(accepted.isEmpty())store.release(row);else store.saveSession(row);
        }catch(RuntimeException unknown){row.put("status","unknown");row.put("message","厂家创建结果未确认，未自动重发；请结束此记录后重试");store.saveSession(row);}
        return credentials(row);
    }
    public JSONObject session(String id){JSONObject row=enabled()?store.session(id):null;if(row==null)throw fail(404,"CALL_NOT_FOUND","分体帽会话不存在");return row;}
    public JSONObject owned(String actor,String id){JSONObject row=session(id);if(!Objects.equals(actor,row.getString("actorId")))throw fail(404,"CALL_NOT_FOUND","会话不存在或不属于当前账号");return row;}
    public JSONObject callState(String id){JSONObject r=session(id);return obj("status",r.get("status"),"expiresAt",Instant.ofEpochMilli(r.getLongValue("expiresMillis")).toString(),"statusVerified",false,"protocol",PROTOCOL,"deviceIds",r.get("deviceIds"),"skipped",r.get("skipped"),"connectedDeviceIds",r.getOrDefault("connectedDeviceIds",new JSONArray()),"connectionQuality",r.get("connectionQuality"));}
    public JSONObject credentials(JSONObject row){
        JSONObject result=obj("protocol",PROTOCOL,"channel",row.getString("id"),"sessionId",row.getString("id"),"status",row.get("status"),"expiresAt",Instant.ofEpochMilli(row.getLongValue("expiresMillis")).toString(),"video",row.getBooleanValue("video"),"heartbeatUrl",path(row.getString("id"))+"/heartbeat","endUrl",path(row.getString("id"))+"/end","sessions",new JSONArray(),"skipped",row.get("skipped"),"message",row.get("message"));
        if(Arrays.asList("offered","connected").contains(row.getString("status")))for(Object raw:row.getJSONArray("remoteSessions")){String sn=((JSONObject)raw).getString("helmetSn");JSONObject s=obj("deviceId",sn,"helmetSn",sn,"playUrl",path(row.getString("id"))+"/devices/"+sn+"/play");if(!"preview".equals(row.getString("mode")))s.put("talkUrl",path(row.getString("id"))+"/devices/"+sn+"/talk");result.getJSONArray("sessions").add(s);}
        return result;
    }
    private static String path(String id){return "/api/guardian/v1/split/sessions/"+id;}
    public synchronized JSONObject heartbeat(String actor,String id){
        JSONObject row=owned(actor,id);if(!Arrays.asList("offered","connected").contains(row.getString("status"))||row.getLongValue("expiresMillis")<System.currentTimeMillis())throw fail(409,"CALL_EXPIRED","分体帽会话已过期或尚未确认");
        JSONArray sns=leased(row);if(sns.isEmpty())throw fail(409,"CALL_EXPIRED","设备会话占用已变化");
        long now=System.currentTimeMillis();if(now-row.getLongValue("lastHeartbeatMillis")>=55000){client.post("/api/webrtc/heartbeat",obj("helmetSnList",sns));row.put("lastHeartbeatMillis",now);}
        row.put("expiresMillis",now+properties.getLeaseSeconds()*1000L);store.saveSession(row);return callState(id);
    }
    public synchronized void end(String id){
        java.util.concurrent.locks.Lock lock=signalLock(id).writeLock();lock.lock();try{endLocked(id);}finally{lock.unlock();}
    }
    private void endLocked(String id){
        JSONObject row=session(id);if(Arrays.asList("ended","failed").contains(row.getString("status")))return;
        JSONArray sns=leased(row);row.put("status","ending");store.saveSession(row);
        try{if(!sns.isEmpty())client.post("/api/webrtc/hangup",obj("helmetSnList",sns));row.put("status","ended");row.put("endedAt",Instant.now().toString());row.put("remoteSessions",new JSONArray());store.release(row);}
        catch(RuntimeException unknown){row.put("status","unknown");row.put("expiresMillis",System.currentTimeMillis());row.put("message","挂断结果未确认，保留设备占用并继续核实");store.saveSession(row);throw unknown;}
    }
    private JSONArray leased(JSONObject row){JSONArray out=new JSONArray();for(Object raw:row.getJSONArray("deviceIds"))if(store.owns(row.getString("id"),String.valueOf(raw)))out.add(raw);return out;}
    synchronized void enableMonitorTalk(String actor, String id, String sn) {
        JSONObject row = owned(actor, id);
        if (!"preview".equals(row.getString("mode")) || !JSONArray.of(sn).equals(row.getJSONArray("deviceIds"))
                || !Arrays.asList("offered", "connected").contains(row.getString("status"))
                || row.getLongValue("expiresMillis") < System.currentTimeMillis() || !store.owns(id, sn))
            throw fail(409, "CALL_EXPIRED", "监看会话已结束或设备占用已变化");
        if (!row.getBooleanValue("monitorTalk")) {
            row.put("monitorTalk", true);
            store.saveSession(row);
        }
    }
    public String signal(String actor,String id,String sn,String kind,String offer){require(sn);java.util.concurrent.locks.Lock lock=signalLock(id).readLock();lock.lock();try{JSONObject row=owned(actor,id);
        if(!Arrays.asList("play","talk").contains(kind)||"talk".equals(kind)&&"preview".equals(row.getString("mode"))&&!row.getBooleanValue("monitorTalk"))throw fail(400,"INVALID_SIGNAL","会话信令用途无效");
        if(!Arrays.asList("offered","connected").contains(row.getString("status"))||row.getLongValue("expiresMillis")<System.currentTimeMillis()||!store.owns(id,sn))throw fail(409,"CALL_EXPIRED","会话已结束或设备占用变化");
        for(Object raw:row.getJSONArray("remoteSessions")){JSONObject s=(JSONObject)raw;if(sn.equals(s.getString("helmetSn")))return client.signal(s.getString("play".equals(kind)?"playUrl":"talkUrl"),sn,kind,offer);}throw fail(404,"CALL_NOT_FOUND","设备未参与本次会话");
        }finally{lock.unlock();}
    }
    public synchronized void joined(String actor,String id,boolean connected,JSONArray connectedIds){
        JSONObject row=owned(actor,id);if(!connected||!Arrays.asList("offered","connected").contains(row.getString("status"))||row.getLongValue("expiresMillis")<System.currentTimeMillis())throw fail(409,"CALL_UNAVAILABLE","会话尚未建立或已过期");
        JSONArray accepted=new JSONArray();for(Object raw:row.getJSONArray("remoteSessions"))accepted.add(((JSONObject)raw).getString("helmetSn"));
        if(connectedIds==null&&accepted.size()==1)connectedIds=accepted;
        if(connectedIds==null||connectedIds.isEmpty()||new HashSet<>(connectedIds).size()!=connectedIds.size()||!accepted.containsAll(connectedIds))throw fail(400,"INVALID_PEER_EVIDENCE","连接设备必须属于本次会话");
        for(Object sn:connectedIds)if(!store.owns(id,String.valueOf(sn)))throw fail(409,"CALL_EXPIRED","设备占用已变化");
        row.put("status","connected");row.put("connectedDeviceIds",connectedIds);row.put("clientConnectedAt",Instant.now().toString());row.put("connectionQuality","client_peer_connected");store.saveSession(row);
    }
    public JSONObject live(String actor, String sn, JSONObject input) {
        JSONObject target = new JSONObject();
        for (String key : Arrays.asList("personId","assignmentId","assignmentVersion","siteId","areaId","ledgerDeviceId","acceptanceTest"))
            target.put(key, input.get(key));
        target.put("deviceId", sn);
        String viewer = input.getString("viewerSessionId");
        if (viewer == null || !viewer.matches("[A-Za-z0-9_-]{8,100}"))
            throw fail(400, "VIEWER_REQUIRED", "请提供稳定的观看会话编号");
        JSONObject c = create(actor, JSONArray.of(target), true, "preview", "preview:" + viewer);
        JSONArray sessions = c.getJSONArray("sessions");
        boolean available = sessions != null && !sessions.isEmpty();
        String url = available ? sessions.getJSONObject(0).getString("playUrl") : null;
        return obj("available", available, "protocol", PROTOCOL, "sessionId", c.get("sessionId"), "deviceId", sn,
                "streamId", c.get("sessionId"), "url", url, "playUrl", url, "whepUrl", url,
                "talkUrl", available ? path(c.getString("sessionId")) + "/devices/" + sn + "/talk" : null,
                "heartbeatUrl", c.get("heartbeatUrl"), "endUrl", c.get("endUrl"), "expiresAt", c.get("expiresAt"),
                "reason", c.get("message"));
    }

    public JSONObject command(String actor,String sn,JSONObject input){synchronized(commandLocks.computeIfAbsent(sn,k->new Object())){return commandLocked(actor,sn,input);}}
    private JSONObject commandLocked(String actor,String sn,JSONObject input){
        String action=input.getString("action"),request=input.getString("idempotencyKey");
        if(!Arrays.asList("stop_video","stop_recording").contains(action))require(sn);
        if(request==null||!request.matches("[A-Za-z0-9_-]{8,100}"))throw fail(400,"REQUEST_ID_REQUIRED","请提供稳定的指令编号");
        String key=DigestUtils.sha256Hex(request),fingerprint=DigestUtils.sha256Hex(sn+"\n"+input.toJSONString());JSONObject previous=store.commandRequest(actor,key);
        if(previous!=null){if(!fingerprint.equals(previous.getString("fingerprint")))throw fail(409,"IDEMPOTENCY_CONFLICT","指令编号冲突");return publicCommand(previous);}
        if(!Arrays.asList("take_photo","start_recording","stop_recording","list_recordings","set_watermark","broadcast","start_video","stop_video").contains(action))throw fail(400,"COMMAND_NOT_AVAILABLE","分体帽不支持此指令");
        JSONObject p=input.getJSONObject("parameters");if(p==null)p=new JSONObject();JSONObject parameters=copy(p);
        if("start_video".equals(action)){JSONObject result=live(actor,sn,input);result.put("status",result.getBooleanValue("available")?"sent":"unknown");result.put("action",action);return result;}
        if("stop_video".equals(action)){JSONObject session=requireCleanup(actor,sn,input);end(session.getString("id"));return obj("status","ended","action",action);}
        String watermark=parameters.getString("watermark");if(watermark!=null&&watermark.length()>512)throw fail(400,"INVALID_WATERMARK","水印最多512个字符");
        int duration=300;if("start_recording".equals(action)&&parameters.containsKey("durationSeconds")){Object raw=parameters.get("durationSeconds");try{if(!(raw instanceof Number))throw new IllegalArgumentException();duration=new java.math.BigDecimal(String.valueOf(raw)).intValueExact();}catch(RuntimeException invalid){throw fail(400,"INVALID_DURATION","录像时长须为整数秒");}}if("start_recording".equals(action)&&(duration<1||duration>86400))throw fail(400,"INVALID_DURATION","录像时长为1至86400秒");
        if("set_watermark".equals(action)&&(watermark==null||watermark.trim().isEmpty()))throw fail(400,"INVALID_WATERMARK","请输入水印");
        if("broadcast".equals(action)){String text=parameters.getString("text");if(text==null||text.trim().isEmpty()||text.length()>200)throw fail(400,"INVALID_BROADCAST","广播内容须为1至200字");}
        JSONObject source=null;if("stop_recording".equals(action)){source=requireCleanup(actor,sn,input);if(source.getString("sid")==null)throw fail(409,"RECORDING_NOT_FOUND","尚无已确认的录像任务编号");if(source.containsKey("stopRequestedAt")||Arrays.asList("stopping","stop_unknown","stopped","completed","failed").contains(source.getString("status")))return obj("id",source.getString("id"),"action",action,"status",source.get("status"),"message","原录像停止请求已记录，不重复下发");}
        JSONObject row=obj("id","SC-"+UUID.randomUUID(),"actorId",actor,"deviceId",sn,"requestKey",key,"fingerprint",fingerprint,"action",action,"status","requesting","createdMillis",System.currentTimeMillis(),"createdAt",Instant.now().toString(),"parameters",parameters,"recordingOrigin","device");
        for(String field:Arrays.asList("siteId","areaId","personId","assignmentId","assignmentVersion","ledgerDeviceId"))row.put(field,input.get(field));
        if(source!=null)row.put("sourceCommandId",source.getString("id"));store.commandIntent(row);
        try{
            JSONObject params=obj("helmetSnList",JSONArray.of(sn));if(watermark!=null)params.put("watermark",watermark);
            if("list_recordings".equals(action)){JSONArray files=readFiles(sn,row);row.put("result",files);row.put("status","completed");}
            else if("stop_recording".equals(action)){source.put("stopRequestedAt",Instant.now().toString());source.put("status","stop_unknown");store.saveCommand(source);client.post("/api/monitor/record/stop",obj("sid",source.getString("sid")));row.put("status","sent");source.put("status","stopping");store.saveCommand(source);}
            else if("broadcast".equals(action)){String text=parameters.getString("text");if(text==null||text.trim().isEmpty()||text.length()>200)throw fail(400,"INVALID_BROADCAST","广播内容须为1至200字");params.put("tts_text",text);client.post("/api/monitor/tts",params);row.put("status","sent");}
            else{
                if("start_recording".equals(action))params.put("recordTimeLength",duration);
                String path="take_photo".equals(action)?"capture":"start_recording".equals(action)?"record":"watermark";
                JSONObject data=client.post("/api/monitor/"+path,params).getJSONObject("data");JSONObject accepted=sent(data,sn);
                if("start_recording".equals(action)){String sid=accepted.getString("sid");if(sid==null)sid=data.getString("sid");if(sid==null||!sid.matches("[A-Za-z0-9._-]{1,128}"))throw new IllegalArgumentException();row.put("sid",sid);}
                if(accepted.get("task_id")!=null)row.put("vendorTaskId",accepted.get("task_id"));row.put("status","sent");
            }
            row.put("message","completed".equals(row.getString("status"))?"设备文件目录已读取":"指令已发送，实际完成状态须以设备回传或文件为准");
        }catch(RuntimeException unknown){row.put("status","unknown");row.put("message","设备指令结果未确认，未自动重发；请核对原任务或文件");}
        store.saveCommand(row);return publicCommand(row);
    }
    private static JSONObject sent(JSONObject data,String sn){if(data==null||!(data.get("sent") instanceof JSONArray))throw new IllegalArgumentException();JSONObject match=null;for(Object raw:data.getJSONArray("sent")){if(!(raw instanceof JSONObject)||!sn.equals(((JSONObject)raw).getString("helmetSn"))||match!=null)throw new IllegalArgumentException();match=(JSONObject)raw;}if(match==null)throw new IllegalArgumentException();return match;}
    public JSONObject media(String sn){
        JSONArray commands=new JSONArray(),files=new JSONArray();if(enabled()){for(JSONObject r:store.commands(sn)){commands.add(publicCommand(r));}files.addAll(store.files(sn));}
        JSONObject status=status(sn);return obj("status",status==null?"unconfigured":status.get("mediaStatus"),"protocol",PROTOCOL,"recordingOrigin","device","items",files,"recordings",files,"commands",commands,"actions",JSONArray.of("take_photo","start_recording","stop_recording","list_recordings","set_watermark"));
    }
    public JSONArray assets(String sn){return media(sn).getJSONArray("items");}
    private void refreshRecording(JSONObject original){synchronized(commandLocks.computeIfAbsent(original.getString("deviceId"),k->new Object())){JSONObject row=store.command(original.getString("id"));if(row==null)return;row.put("lastStatusCheck",System.currentTimeMillis());store.saveCommand(row);try{Map<String,String> q=new HashMap<>();q.put("sid",row.getString("sid"));JSONObject d=client.get("/api/monitor/record/status",q).getJSONObject("data");if(d==null||!row.getString("sid").equals(d.getString("sid"))||d.getString("flashid")!=null&&!row.getString("deviceId").equals(d.getString("flashid"))||!d.containsKey("status"))return;String status;switch(d.getIntValue("status")){case 0:status="pending";break;case 1:status="recording";break;case 2:status="completed";break;case 3:status="failed";break;case 7:status="stopped";break;default:return;}row.put("status",status);row.put("recordingStatus",d.get("status"));row.put("message","厂家录像状态已返回；文件是否可播放须由文件目录确认");store.saveCommand(row);}catch(RuntimeException ignored){}}}
    private JSONArray readFiles(String sn,JSONObject context){
        JSONArray output=new JSONArray();Set<String> ids=new HashSet<>();
        for(int page=1;page<=10;page++){JSONObject data=client.files(sn,page);JSONArray files=data.getJSONArray("file_list");
            for(Object raw:files){if(!(raw instanceof JSONObject))continue;JSONObject f=(JSONObject)raw;String path=f.getString("key");if(path==null)path=f.getString("path");if(path==null||!path.startsWith(sn+"/")||path.contains("..")||path.contains("\\")||path.contains("%")||!Arrays.asList("image","video","audio").contains(f.getString("type")))continue;
                String id=DigestUtils.sha256Hex(sn+"\n"+path+"\n"+f.getString("lastModified")+"\n"+f.getString("size"));if(!ids.add(id))continue;String safe=safeFile(f.getString("url"),sn,path);JSONObject owner=null;
                try{String observed=Instant.parse(f.getString("lastModified")).toString();long millis=Instant.parse(observed).toEpochMilli();if(millis>=946684800000L&&millis<=System.currentTimeMillis()+300000)owner=bridge().captureFile(sn,observed);}catch(RuntimeException invalid){/* No inference from query-time ownership. */}
                if(owner==null)safe=null;
                JSONObject item=obj("id",id,"deviceId",sn,"source","SPLIT_HELMET","protocol",PROTOCOL,"kind","image".equals(f.getString("type"))?"photo":f.getString("type"),"name",f.getString("name"),"fileName",f.getString("name"),"createdAt",f.get("lastModified"),"size",f.get("size"),"available",safe!=null,"url",safe==null?null:"/api/guardian/v1/split/devices/"+sn+"/files/"+id,"unavailableReason",safe==null?"文件未提供可信HTTPS下载地址":"","recordingOrigin","device");
                item.put("timeBasis","FILE_LAST_MODIFIED");item.put("attribution",owner==null?"UNKNOWN":"ASSIGNMENT_INTERVAL");
                if(owner!=null)for(String field:Arrays.asList("siteId","areaId","personId","personName","assignmentId","assignmentVersion","ledgerDeviceId"))item.put(field,owner.get(field));
                if(owner==null)item.put("unavailableReason","文件时间或历史归属无法核实");
                output.add(item);store.saveFile(sn,item,path,safe);associateFile(sn,f,item);
            }
            if(files.size()<100||data.containsKey("total")&&page*100>=data.getIntValue("total"))break;
        }return output;
    }
    private String safeFile(String url,String sn,String key){String safe=client.safeFileUrl(url,sn);return safe!=null&&java.net.URI.create(safe).getPath().endsWith("/"+key)?safe:null;}
    private void associateFile(String sn,JSONObject vendor,JSONObject item){for(JSONObject command:store.mediaCommands(sn)){boolean matches="take_photo".equals(command.getString("action"))&&command.getString("vendorTaskId")!=null&&command.getString("vendorTaskId").equals(vendor.getString("task_id"))||"start_recording".equals(command.getString("action"))&&command.getString("sid")!=null&&command.getString("sid").equals(vendor.getString("sid"));if(matches){JSONArray ids=command.getJSONArray("assetIds");if(ids==null){ids=new JSONArray();command.put("assetIds",ids);}if(!ids.contains(item.getString("id")))ids.add(item.getString("id"));command.put("fileAvailable",item.getBooleanValue("available"));command.put("fileConfirmedAt",Instant.now().toString());if("take_photo".equals(command.getString("action")))command.put("status","completed");store.saveCommand(command);}}}
    public JSONObject fileContext(String sn,String id){if(!enabled()||id==null||!id.matches("[a-f0-9]{64}"))throw fail(404,"FILE_NOT_FOUND","设备文件不存在");JSONObject row=store.file(sn,id);if(row==null||row.getString("siteId")==null||row.getString("privateSourceUrl")==null)throw fail(404,"FILE_NOT_FOUND","设备文件不存在或历史归属无法核实");return row;}
    public JSONObject fileSnapshot(String sn,String id){
        JSONObject row=fileContext(sn,id);
        for(int page=1;page<=10;page++){JSONObject data=client.files(sn,page);JSONArray files=data.getJSONArray("file_list");for(Object raw:files){if(!(raw instanceof JSONObject))continue;JSONObject f=(JSONObject)raw;String key=f.getString("key");if(key==null)key=f.getString("path");if(!Objects.equals(key,row.getString("privateFileKey"))||!Objects.equals(f.getString("lastModified"),row.getString("createdAt"))||!Objects.equals(f.getString("size"),row.getString("size")))continue;String safe=safeFile(f.getString("url"),sn,key);if(safe==null)break;JSONObject item=copy(row);item.remove("privateFileKey");item.remove("privateSourceUrl");item.remove("privateRefreshedAt");store.saveFile(sn,item,key,safe);return fileContext(sn,id);}if(files.size()<100||data.containsKey("total")&&page*100>=data.getIntValue("total"))break;}
        throw fail(410,"FILE_REVISION_UNAVAILABLE","原文件版本已不存在或无法刷新可信地址，请重新查询目录");
    }
    public String fileUrl(String sn,String id){return fileSnapshot(sn,id).getString("privateSourceUrl");}
    public JSONObject requireCleanup(String actor,String sn,JSONObject input){
        if("stop_recording".equals(input.getString("action"))){JSONObject p=input.getJSONObject("parameters");String id=p==null?null:p.getString("commandId");if(id==null)id=input.getString("sourceCommandId");JSONObject source=store.command(id);if(source==null||!actor.equals(source.getString("actorId"))||!sn.equals(source.getString("deviceId"))||!"start_recording".equals(source.getString("action")))throw fail(404,"RECORDING_NOT_FOUND","录像任务不存在或不属于当前账号");PersonEquipmentContext.sameContext(source,input);return source;}
        JSONObject p=input.getJSONObject("parameters");String id=p==null?null:p.getString("sessionId");if(id==null)id=input.getString("sessionId");if(id==null){JSONObject s=store.sessionRequest(actor,DigestUtils.sha256Hex("preview:"+input.getString("viewerSessionId")));if(s!=null)id=s.getString("id");}
        JSONObject row=owned(actor,id);if(!row.getJSONArray("deviceIds").contains(sn)||!"preview".equals(row.getString("mode")))throw fail(404,"CALL_NOT_FOUND","观看会话不存在或设备不匹配");
        JSONObject result=copy(row);for(Object raw:row.getJSONArray("recipients")){JSONObject r=(JSONObject)raw;if(sn.equals(r.getString("deviceId")))result.putAll(r);}PersonEquipmentContext.sameContext(result,input);return result;
    }
    public SplitHelmetClient client(){return client;}
    public JSONObject publicCommand(JSONObject row){JSONObject result=copy(row);for(String key:Arrays.asList("sid","vendorTaskId","fileSources","fingerprint","requestKey","createdMillis"))result.remove(key);return result;}
}
