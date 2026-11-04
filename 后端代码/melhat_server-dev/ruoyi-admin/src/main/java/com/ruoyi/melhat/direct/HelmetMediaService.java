package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import java.time.Instant;
import java.util.*;
import org.apache.commons.codec.digest.DigestUtils;

/** Device control is journalled before sending. A socket write is never a device acknowledgement. */
@Service
public class HelmetMediaService {
    private final HelmetCloudClient cloud;
    private final HelmetMediaStore store;
    private final HelmetMediaProperties properties;
    private final ObjectProvider<DirectHelmetGateway> gateways;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.guardian.WearableMaintenance maintenance;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.guardian.ExternalDataStore externalData;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private ObjectProvider<com.ruoyi.guardian.PersonEquipmentContext> equipmentContexts;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterWorkCoordinator coordinator;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.MediaOperationJournal journal;
    private <T>T coordinated(boolean background,java.util.function.Supplier<T> action){return coordinator==null?action.get():coordinator.run("media",background,action);}
    private volatile long healthCheckedAt;
    private volatile boolean healthy;
    private volatile boolean ttsHealthy;
    private final Set<String> pendingAccounts=java.util.concurrent.ConcurrentHashMap.newKeySet();
    private volatile Set<String> registeredDevices=Collections.emptySet();
    public HelmetMediaService(HelmetCloudClient cloud, HelmetMediaStore store, HelmetMediaProperties properties,
            ObjectProvider<DirectHelmetGateway> gateways) {
        this.cloud=cloud; this.store=store; this.properties=properties; this.gateways=gateways;
    }
    public boolean available() { return cloud.configured() && healthy && (coordinator==null||!coordinator.enabled()||System.nanoTime()-healthCheckedAt<java.util.concurrent.TimeUnit.SECONDS.toNanos(45)); }
    /** Device-authorized service leases remain separate from person-authorized viewer sessions. */
    public synchronized JSONObject gbDeviceStatus(String deviceId) {
        if(!gateway().supports(deviceId))throw new IllegalArgumentException("GB_HELMET_NOT_FOUND");
        return obj("deviceId",deviceId,"online",gateway().isOnline(deviceId),"busy",hasActiveCall(deviceId),"mediaAvailable",available());
    }
    public JSONObject gbAcquire(String leaseId,String deviceId,int ttlSeconds) { return coordinated(false,()->gbAcquireCoordinated(leaseId,deviceId,ttlSeconds)); }
    private synchronized JSONObject gbAcquireCoordinated(String leaseId,String deviceId,int ttlSeconds) {
        if(!leaseId.matches("[A-Za-z0-9_-]{16,100}")||ttlSeconds<30||ttlSeconds>180)throw new IllegalArgumentException("GB_INVALID_LEASE");
        JSONObject status=gbDeviceStatus(deviceId);
        if(!status.getBooleanValue("online"))throw new IllegalStateException("GB_DEVICE_OFFLINE");
        if(status.getBooleanValue("busy"))throw new IllegalStateException("GB_DEVICE_BUSY");
        requireCloud();
        JSONObject lease=map(store.snapshot(),"gbLeases").getJSONObject(leaseId);
        if(lease!=null&&!deviceId.equals(lease.getString("deviceId")))throw new IllegalArgumentException("GB_LEASE_CONFLICT");
        if(lease!=null&&lease.getBooleanValue("released"))throw new IllegalArgumentException("GB_LEASE_RELEASED");
        if(lease!=null&&!Instant.parse(lease.getString("expiresAt")).isAfter(now())){gbRelease(leaseId);throw new IllegalArgumentException("GB_LEASE_EXPIRED");}
        boolean fresh=lease==null;
        JSONObject current=stream(deviceId);
        if(fresh)lease=obj("leaseId",leaseId,"deviceId",deviceId,"createdAt",now().toString());
        lease.put("expiresAt",now().plusSeconds(ttlSeconds).toString());
        final JSONObject saved=lease;
        store.update(s->{map(s,"gbLeases").put(leaseId,saved);return null;});
        boolean alreadyDemanded=current.getBooleanValue("watchRequested")||current.getBooleanValue("recordRequested");
        setGbWatcher(current,leaseId,true);saveStream(deviceId,current);
        if(fresh&&!alreadyDemanded)try{sendDevice(deviceId,obj("cmd","server_push_open_rtsp","push_url",current.getString("pushUrl")),"gb-open:"+leaseId);}
        catch(com.ruoyi.cluster.DeviceCommandRouter.Pending pending){saved.put("commandId",pending.commandId);store.update(state->{map(state,"gbLeases").put(leaseId,saved);return null;});}
        catch(Exception error){gbRelease(leaseId);throw new IllegalStateException("GB_DEVICE_COMMAND_UNCONFIRMED");}
        return gbLeaseStatus(leaseId);
    }
    public JSONObject gbLeaseStatus(String leaseId) { return coordinated(false,()->gbLeaseStatusCoordinated(leaseId)); }
    private synchronized JSONObject gbLeaseStatusCoordinated(String leaseId) {
        JSONObject lease=map(store.snapshot(),"gbLeases").getJSONObject(leaseId);
        if(lease==null||lease.getBooleanValue("released"))throw new IllegalArgumentException("GB_LEASE_NOT_FOUND");
        if(!Instant.parse(lease.getString("expiresAt")).isAfter(now())){gbRelease(leaseId);throw new IllegalArgumentException("GB_LEASE_EXPIRED");}
        String deviceId=lease.getString("deviceId");JSONObject result=gbDeviceStatus(deviceId);
        JSONObject current=map(store.snapshot(),"streams").getJSONObject(deviceId);
        if(current==null)throw new IllegalStateException("GB_STREAM_NOT_FOUND");
        JSONObject actual=cloud.request("GET","/streams/"+current.getString("streamId"),null);
        // Only a scoped playback ticket crosses this boundary; never return the device push URL.
        String token="";try{String query=java.net.URI.create(actual.getString("hlsUrl")).getRawQuery();
            for(String pair:query.split("&"))if(pair.startsWith("token="))token=java.net.URLDecoder.decode(pair.substring(6),"UTF-8");
        }catch(Exception error){throw new IllegalStateException("GB_PLAY_TICKET_UNAVAILABLE");}
        if(token.isEmpty())throw new IllegalStateException("GB_PLAY_TICKET_UNAVAILABLE");
        result.putAll(obj("leaseId",leaseId,"leaseExpiresAt",lease.get("expiresAt"),"streamId",actual.get("streamId"),"playToken",token,
                "publishing",actual.getBooleanValue("publishing"),"statusVerified",actual.getBooleanValue("statusVerified"),"expiresAt",actual.get("expiresAt")));
        if(clusteredCommands()&&lease.getString("commandId")!=null){JSONObject command=commandRouter.read(lease.getString("commandId"));if(command!=null){result.put("deliveryStatus",command.get("deliveryStatus"));result.put("deliveryReason",command.get("deliveryReason"));}}
        return result;
    }
    public JSONObject gbRelease(String leaseId) { return coordinated(false,()->gbReleaseCoordinated(leaseId)); }
    private synchronized JSONObject gbReleaseCoordinated(String leaseId) {
        JSONObject lease=map(store.snapshot(),"gbLeases").getJSONObject(leaseId);
        if(lease==null||lease.getBooleanValue("released"))return obj("released",true);
        String deviceId=lease.getString("deviceId");JSONObject current=map(store.snapshot(),"streams").getJSONObject(deviceId);
        if(current!=null){setGbWatcher(current,leaseId,false);saveStream(deviceId,current);}
        lease.put("released",true);lease.put("releasedAt",now().toString());
        store.update(s->{map(s,"gbLeases").put(leaseId,lease);return null;});
        if(current!=null&&!current.getBooleanValue("watchRequested")&&!current.getBooleanValue("recordRequested")&&gateway().isOnline(deviceId))
            try{sendDevice(deviceId,obj("cmd","server_push_stop_rtsp"),"gb-stop:"+leaseId);}catch(Exception ignored){/* No remaining demand; the disconnected device is not retried. */}
        return obj("released",true);
    }
    @Scheduled(fixedDelay=10000)
    public void expireGbLeases() { coordinated(true,()->{expireGbLeasesCoordinated();return null;}); }
    private void expireGbLeasesCoordinated() {
        if(maintenance!=null&&!maintenance.tryBeginWrite())return;
        try{synchronized(this){expireGbLeasesActive();}}
        finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private void expireGbLeasesActive(){
        JSONObject leases=map(store.snapshot(),"gbLeases");if(leases.isEmpty())return;
        boolean prune=false;
        for(Map.Entry<String,Object> item:leases.entrySet()){
            JSONObject lease=(JSONObject)item.getValue();
            if(!lease.getBooleanValue("released")&&!Instant.parse(lease.getString("expiresAt")).isAfter(now()))gbRelease(item.getKey());
            if(lease.getBooleanValue("released")&&Instant.parse(lease.getString("releasedAt")).isBefore(now().minusSeconds(86400)))prune=true;
        }
        if(prune)store.update(s->{map(s,"gbLeases").entrySet().removeIf(e->{JSONObject l=(JSONObject)e.getValue();return l.getBooleanValue("released")&&Instant.parse(l.getString("releasedAt")).isBefore(now().minusSeconds(86400));});return null;});
    }
    public JSONObject capabilities() { return obj("mediaAvailable",available(),"voiceAvailable",available(),
            "broadcastAvailable",available()&&ttsHealthy,"mediaProtocol","SIP","mediaStatus",!cloud.configured()?"unconfigured":healthy?"ready":"unavailable",
            "mediaVerification","pending"); }
    public JSONObject capabilities(String deviceId){JSONObject result=capabilities();result.put("voiceAvailable",available()&&registeredDevices.contains(deviceId));result.put("sipRegistered",registeredDevices.contains(deviceId));return result;}
    public void rememberDevice(String deviceId){if(cloud.configured()&&map(store.snapshot(),"accounts").getJSONObject(deviceId)==null)pendingAccounts.add(deviceId);}
    /** Login remains operational when the cloud is down. Account provisioning is performed in the background. */
    public JSONObject sipInfo(String deviceId) {
        JSONObject account = map(store.snapshot(),"accounts").getJSONObject(deviceId);
        return account == null || !available() ? null : obj("sip_id",account.getString("sipId"),
                "sip_pwd",account.getString("password"),"sip_host",account.getString("sipHost"));
    }
    public JSONObject provision(String deviceId) { return coordinated(false,()->provisionCoordinated(deviceId)); }
    private synchronized JSONObject provisionCoordinated(String deviceId) {
        requireCloud();
        JSONObject account = map(store.snapshot(),"accounts").getJSONObject(deviceId);
        if (account == null) {
            account = obj("sipId","h"+DigestUtils.sha256Hex(deviceId).substring(0,20),"password",random());
            final JSONObject created=account; store.update(s->{map(s,"accounts").put(deviceId,created);return null;});
        }
        JSONObject reply=cloud.request("PUT","/accounts/"+account.getString("sipId"),obj("password",account.getString("password"),"kind","helmet","deviceId",deviceId));
        account.put("sipHost",reply.getString("sipHost")); account.put("wssUrl",reply.getString("wssUrl"));
        final JSONObject saved=account; store.update(s->{map(s,"accounts").put(deviceId,saved);return null;});
        return account;
    }
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.DeviceCommandRouter commandRouter;
    private Instant now(){return clusteredCommands()?commandRouter.now():Instant.now();}
    private boolean clusteredCommands(){return commandRouter!=null&&commandRouter.enabled();}
    public JSONObject command(String actorId,String deviceId,JSONObject input) { return coordinated(false,()->commandCoordinated(actorId,deviceId,input)); }
    private synchronized JSONObject commandCoordinated(String actorId,String deviceId,JSONObject input) {
        String action=text(input,"action"), key=text(input,"idempotencyKey");
        if(!key.matches("[A-Za-z0-9_-]{8,100}"))throw new IllegalArgumentException("请提供稳定的请求编号");
        if(!Arrays.asList("take_photo","start_video","stop_video","list_recordings","upload_recording",
                "start_recording","stop_recording","broadcast","set_config","configure_sip").contains(action))
            throw new IllegalArgumentException("不支持此设备操作");
        String fingerprint=clusteredCommands()?com.ruoyi.cluster.DeviceCommandRouter.fingerprint(input):DigestUtils.sha256Hex(input.toJSONString());
        if(clusteredCommands()){JSONObject prior=commandRouter.find(commandRouter.scope(actorId,deviceId,key),fingerprint);if(prior!=null){JSONObject business=map(store.snapshot(),"commands").getJSONObject(prior.getString("id"));return publicCommand(business==null?prior:business);}}
        for(Object raw:map(store.snapshot(),"commands").values()) {
            JSONObject previous=(JSONObject)raw;
            if(actorId.equals(previous.getString("actorId"))&&deviceId.equals(previous.getString("deviceId"))&&key.equals(previous.getString("requestId"))) {
                if(!fingerprint.equals(previous.getString("fingerprint")))throw new IllegalArgumentException("相同请求编号不能用于不同内容");
                return publicCommand(previous);
            }
        }
        if(Arrays.asList("start_video","stop_video").contains(action))viewerId(input);
        if("stop_video".equals(action)||"stop_recording".equals(action))requireCleanup(actorId,deviceId,input);
        if(!Arrays.asList("stop_recording","stop_video").contains(action)&&!gateway().isOnline(deviceId))throw new IllegalStateException("设备不在线，未下发命令");
        if(!"stop_video".equals(action))requireCloud();
        if(Arrays.asList("take_photo","start_video","start_recording","set_config").contains(action)&&hasActiveCall(deviceId))
            throw new IllegalStateException("设备正在通话，请结束后再操作摄像头或参数");
        JSONObject params=input.getJSONObject("parameters"); if(params==null)params=new JSONObject();
        if("broadcast".equals(action)&&(!ttsHealthy||text(params,"text").isEmpty()||text(params,"text").length()>200))throw new IllegalArgumentException("广播服务尚未就绪或内容不在1至200字范围内");
        JSONObject wire=wire(action,params);
        JSONArray requestedFiles="upload_recording".equals(action)?validateListedFiles(deviceId,params.getJSONArray("files")):null;
        String id="HC-"+UUID.randomUUID(); wire.put("talkback_id",id);
        JSONObject row=obj("id",id,"deviceId",deviceId,"actorId",actorId,"action",action,"requestId",key,"fingerprint",fingerprint,
                "siteId",input.get("siteId"),"areaId",input.get("areaId"),"personId",input.get("personId"),
                "status","requesting","createdAt",now().toString(),"expiresAt",now().plusSeconds(properties.getCommandTimeoutSeconds()).toString());
        // The controller supplies this name from the validated assignment authority. Keep
        // the captured name with the command; historical media must not look up today's wearer.
        if(!text(input,"name").isEmpty())row.put("personName",input.getString("name"));
        for(String field:Arrays.asList("assignmentId","assignmentVersion","ledgerDeviceId","viewerSessionId"))if(input.containsKey(field))row.put(field,input.get(field));
        if(requestedFiles!=null)row.put("requestedFiles",requestedFiles);
        if(clusteredCommands()){
            JSONObject admitted=commandRouter.admit(id,commandRouter.scope(actorId,deviceId,key),fingerprint,"helmet",deviceId,row,wire,false,()->saveCommand(row));
            if(!id.equals(admitted.getString("id"))){JSONObject existing=map(store.snapshot(),"commands").getJSONObject(admitted.getString("id"));return publicCommand(existing==null?admitted:existing);}
        }else saveCommand(row);
        JSONObject recordingStopStream=null;
        try {
            if("configure_sip".equals(action)) {
                provision(deviceId); row.put("status","configured"); row.put("message","SIP 账号已配置，设备下次登录时生效");
            } else if("start_video".equals(action)) {
                JSONObject stream=stream(deviceId); wire.put("push_url",stream.getString("pushUrl"));
                boolean needed=!stream.getBooleanValue("watchRequested")&&!stream.getBooleanValue("recordRequested");
                setViewer(stream,actorId,input,true);saveStream(deviceId,stream);if(needed)sendDevice(deviceId,wire);sent(row);if(!needed&&clusteredCommands()){row.put("status","accepted");row.put("message","已订阅现有共享视频，播放情况以实时画面为准");}
            } else if("stop_video".equals(action)) {
                JSONObject stream=map(store.snapshot(),"streams").getJSONObject(deviceId);
                if(stream!=null) {setViewer(stream,actorId,input,false);saveStream(deviceId,stream);}
                if(stream!=null&&!stream.getBooleanValue("recordRequested")&&!stream.getBooleanValue("watchRequested")&&gateway().isOnline(deviceId))sendDevice(deviceId,wire);
                row.put("status","completed");row.put("message","已释放本次观看会话");
            } else if("start_recording".equals(action)) {
                JSONObject stream=stream(deviceId);
                if(stream.getBooleanValue("recordRequested")||!text(stream,"recordingId").isEmpty()||stream.getBooleanValue("recordStartUnknown"))throw new IllegalArgumentException("平台录像已在启动、录制或等待停止确认");
                stream.remove("sessionInvalidatedAt");stream.remove("cleanupStatus");
                stream.put("recordRequestId",id);stream.put("recordRequested",true);saveStream(deviceId,stream);
                sendDevice(deviceId,obj("cmd","server_push_open_rtsp","push_url",stream.getString("pushUrl"),"talkback_id",id));
                row.put("status","waiting_media");row.put("message","已请求设备推流，收到真实视频后开始录像");
            } else if("stop_recording".equals(action)) {
                JSONObject stream=map(store.snapshot(),"streams").getJSONObject(deviceId);
                if(stream==null||(!stream.getBooleanValue("recordRequested")&&text(stream,"recordingId").isEmpty()))throw new IllegalArgumentException("没有进行中的平台录像");
                // Persist the stop intent before any external call, including a recorder still waiting for video.
                stream.put("recordRequested",false);saveStream(deviceId,stream);
                String recordingId=text(stream,"recordingId");
                JSONObject source=map(store.snapshot(),"commands").getJSONObject(stream.getString("recordRequestId"));
                if(!recordingId.isEmpty()){
                    cloud.request("DELETE","/recordings/"+recordingId,null);
                    row.put("recordingId",recordingId);row.put("sourceCommandId",stream.get("recordRequestId"));
                    stream.remove("recordingId");saveStream(deviceId,stream);
                    row.put("status","finalizing");row.put("message","录像正在封装，文件入库后才可回放");
                }else{
                    if(source!=null){source.put("status","cancelled");source.put("message","已取消等待视频，未开始录像");saveCommand(source);}
                    row.put("status","completed");row.put("message","已取消等待中的平台录像");
                }
                if(clusteredCommands())recordingStopStream=stream;
                else if(!stream.getBooleanValue("watchRequested")&&gateway().isOnline(deviceId))sendDevice(deviceId,obj("cmd","server_push_stop_rtsp"));
            } else {
                if("broadcast".equals(action)) {
                    String content=text(params,"text"); if(content.isEmpty()||content.length()>200)throw new IllegalArgumentException("广播内容需为1至200字");
                    JSONObject audio=cloud.request("POST","/tts",obj("text",content,"requestId",id));
                    if(!"ready".equals(audio.getString("status"))||text(audio,"audioUrl").isEmpty())throw new IllegalStateException("语音文件尚未生成");
                    wire.put("message",audio.getString("audioUrl"));wire.put("message_type",0);
                }
                sendDevice(deviceId,wire);sent(row);
            }
        } catch(com.ruoyi.cluster.DeviceCommandRouter.Pending pending) {
            row.put("status",pending.status.toLowerCase(java.util.Locale.ROOT));row.put("deliveryStatus",pending.status);
            row.put("message","QUEUED".equals(pending.status)?"请求已保存，正在等待设备所在节点发送":"结果未确认，不会自动重复下发");
        } catch(Exception error) {
            if(clusteredCommands())commandRouter.failBeforeSend(id,"准备设备指令失败，尚未开始发送");
            row.put("status","unknown");row.put("message","操作结果未确认，请核对记录和设备状态；不会自动重复下发");
        }
        // Confirmed cloud phase cleanup/readback must not enter the preparation-failure catch above.
        if(recordingStopStream!=null)return finishRecordingStop(row,recordingStopStream);
        if(clusteredCommands()&&Arrays.asList("configured","completed","accepted").contains(row.getString("status")))commandRouter.completeWithoutSend(id);
        saveCommand(row); return commandState(row.getString("id"));
    }
    /** Cloud recording phase and the optional device cleanup delivery have separate outcomes. */
    private JSONObject finishRecordingStop(JSONObject row,JSONObject stream) {
        String id=row.getString("id"),deviceId=row.getString("deviceId");
        // Publish the confirmed phase before activating delivery; never write this old row after send.
        saveCommand(row);
        try {
            if(!stream.getBooleanValue("watchRequested")&&gateway().isOnline(deviceId))
                sendDevice(deviceId,obj("cmd","server_push_stop_rtsp","talkback_id",id));
            else commandRouter.completeWithoutSend(id);
        } catch(com.ruoyi.cluster.DeviceCommandRouter.Pending pending) {
            // The same HC owns cleanup delivery. QUEUED/UNKNOWN cannot undo cloud finalization/cancellation.
        } catch(Exception error) {
            commandRouter.failBeforeSend(id,"录像停止已处理，但设备停止推流指令准备失败");
        }
        return commandState(id);
    }
    public JSONObject commandState(String id){JSONObject row=map(store.snapshot(),"commands").getJSONObject(id);return row==null?null:publicCommand(row);}
    public JSONObject media(String deviceId) {
        JSONObject state=store.snapshot();
        JSONArray commands=new JSONArray();
        for(Object raw:map(state,"commands").values())if(deviceId.equals(((JSONObject)raw).getString("deviceId")))commands.add(publicCommand((JSONObject)raw));
        commands.sort((a,b)->text((JSONObject)b,"createdAt").compareTo(text((JSONObject)a,"createdAt")));
        JSONArray assets=new JSONArray(); String mediaState=capabilities().getString("mediaStatus");
        if(available())try {
            assets=assets(deviceId);
        }catch(RuntimeException error){mediaState="unavailable";}
        JSONArray actions=new JSONArray(),recordings=new JSONArray();
        if(available()&&gateway().isOnline(deviceId))actions.addAll(Arrays.asList("configure_sip","take_photo","start_video","stop_video","list_recordings","upload_recording","start_recording","stop_recording"));
        if(available()&&ttsHealthy&&gateway().isOnline(deviceId))actions.add("broadcast");
        for(Object raw:commands){JSONObject c=(JSONObject)raw;if("list_recordings".equals(c.getString("action"))&&c.getJSONArray("result")!=null){
            for(Object value:c.getJSONArray("result")){if(value instanceof String)recordings.add(obj("fileName",value,"name",value));else if(value instanceof JSONObject){JSONObject file=(JSONObject)value;String filename=text(file,"fileName");if(filename.isEmpty())filename=text(file,"file_name");if(filename.isEmpty())filename=text(file,"name");if(!filename.isEmpty())recordings.add(obj("fileName",filename,"name",filename,"createdAt",file.get("createdAt")));}}
            break;}}
        return obj("deviceId",deviceId,"status",mediaState,"items",assets,"recordings",recordings,"commands",commands,"actions",actions,"capabilities",capabilities());
    }
    /** Only an authenticated, still-assigned viewer can renew its lease and obtain live tickets. */
    public JSONObject live(String actorId,String deviceId,JSONObject input) { return coordinated(false,()->liveCoordinated(actorId,deviceId,input)); }
    private synchronized JSONObject liveCoordinated(String actorId,String deviceId,JSONObject input) {
        if(maintenance!=null)maintenance.beginWrite();
        try{return liveActive(actorId,deviceId,input);}finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private JSONObject liveActive(String actorId,String deviceId,JSONObject input) {
        JSONObject stream=map(store.snapshot(),"streams").getJSONObject(deviceId);
        JSONObject viewer=ownedViewer(stream,actorId,input);
        if(!Instant.parse(viewer.getString("expiresAt")).isAfter(now()))throw new IllegalArgumentException("观看会话已过期，请重新开始观看");
        requireCloud();if(!gateway().isOnline(deviceId))throw new IllegalStateException("设备离线");
        JSONObject current=cloud.request("GET","/streams/"+stream.getString("streamId"),null);
        try {
            Instant expiry=Instant.parse(current.getString("expiresAt")),now=now();
            if(!expiry.isAfter(now)||expiry.isAfter(now.plusSeconds(45)))throw new IllegalArgumentException();
        }catch(RuntimeException error){throw com.ruoyi.guardian.AdminQueryService.fail(503,"MEDIA_SERVICE_UPGRADE_REQUIRED","媒体服务播放票据需升级，暂不提供实时画面");}
        setViewer(stream,actorId,input,true);saveStream(deviceId,stream);
        JSONObject live=current.getBooleanValue("publishing")?obj("protocol","HLS","url",current.get("hlsUrl"),"hlsUrl",current.get("hlsUrl"),"iceServers",current.get("iceServers"),"expiresAt",current.get("expiresAt")):null;
        return obj("deviceId",deviceId,"viewerSessionId",viewerId(input),"status",live==null?"waiting_media":"playing","live",live,"leaseExpiresAt",now().plusSeconds(30).toString());
    }
    public synchronized JSONObject requireCleanup(String actorId,String deviceId,JSONObject input) {
        JSONObject state=store.snapshot(),stream=map(state,"streams").getJSONObject(deviceId),captured;
        if("stop_video".equals(text(input,"action"))){
            captured=stream==null?null:map(stream,"viewers").getJSONObject(viewerId(input));
            if(captured==null)for(Object raw:map(state,"commands").values()){JSONObject command=(JSONObject)raw;if("start_video".equals(command.getString("action"))&&actorId.equals(command.getString("actorId"))&&deviceId.equals(command.getString("deviceId"))&&viewerId(input).equals(command.getString("viewerSessionId"))){captured=command;break;}}
            if(captured==null||!actorId.equals(captured.getString("actorId")))throw new IllegalArgumentException("观看会话不存在或不属于当前账号");
            if(captured.containsKey("assignmentId"))com.ruoyi.guardian.PersonEquipmentContext.sameContext(captured,input);
        }
        else {
            captured=stream==null?null:map(state,"commands").getJSONObject(stream.getString("recordRequestId"));
            if(captured==null||!actorId.equals(captured.getString("actorId")))throw new IllegalArgumentException("录像会话不存在或不属于当前账号");
            if(!Objects.equals(captured.getString("id"),input.getString("sourceCommandId")))throw new IllegalArgumentException("录像会话已变化，请使用原录像指令编号");
            if(captured.containsKey("assignmentId"))com.ruoyi.guardian.PersonEquipmentContext.sameContext(captured,input);
        }
        return new JSONObject(captured);
    }
    public JSONArray assets(String deviceId){
        if(!available())return new JSONArray();
        JSONObject files=cloud.request("GET","/assets?deviceId="+deviceId,null);
        JSONArray values=files.getJSONArray("items");if(values==null)values=files.getJSONArray("assets");
        JSONArray out=new JSONArray();if(values==null)return out;
        for(Object raw:values){JSONObject file=new JSONObject((JSONObject)raw);if(!Arrays.asList("photo","video").contains(file.getString("kind")))continue;
            file.put("id",file.get("assetId"));file.put("source","DIRECT_HELMET");file.put("created",file.get("createdAt"));file.put("name",file.getOrDefault("originalName",file.get("assetId")));
            JSONObject command=assetCommand(deviceId,file);
            if(command!=null){file.put("requestId",command.get("id"));
                file.put("commandAction",command.get("action"));
                // Uploading an older on-device recording does not establish who wore it when filmed.
                if(!"upload_recording".equals(command.getString("action")))for(String key:Arrays.asList("personId","personName","siteId","areaId","assignmentId","assignmentVersion"))file.put(key,command.get(key));}
            else file.remove("requestId"); // An unvalidated upstream identifier cannot complete or authorize a local command.
            String action=command==null?"":text(command,"action");
            file.put("mediaOrigin","photo".equals(file.getString("kind"))?"DEVICE_PHOTO":
                    "start_recording".equals(action)?"PLATFORM_RECORDING":"upload_recording".equals(action)?"DEVICE_RECORDING":"UNKNOWN");
            file.put("unassigned",text(file,"siteId").isEmpty());
            out.add(file);
        }return out;
    }
    public JSONObject call(String actorId,List<String> devices,boolean video) { return coordinated(false,()->callCoordinated(actorId,devices,video)); }
    private synchronized JSONObject callCoordinated(String actorId,List<String> devices,boolean video) {
        return call(actorId,devices,video,new JSONArray());
    }
    public JSONObject call(String actorId,List<String> devices,boolean video,JSONArray recipients) { return coordinated(false,()->callCoordinated(actorId,devices,video,recipients)); }
    private synchronized JSONObject callCoordinated(String actorId,List<String> devices,boolean video,JSONArray recipients) {
        requireCallReady(devices);
        String id="SIP-"+UUID.randomUUID(),room="r"+random().substring(0,20),operator="o"+random().substring(0,20);
        JSONObject row=obj("id",id,"actorId",actorId,"deviceIds",new JSONArray(devices),"status","requesting","createdAt",now().toString());
        row.put("recipients",com.alibaba.fastjson2.JSON.parseArray(recipients.toJSONString()));
        saveCall(row);
        try {
            JSONArray participants=new JSONArray();
            for(String device:devices) {
                JSONObject account=provision(device); participants.add(account.getString("sipId"));
                try{sendDevice(device,obj("cmd","server_push_stop_rtsp"),"call-stop:"+id);}
                catch(com.ruoyi.cluster.DeviceCommandRouter.Pending pending){JSONObject delivery=row.getJSONObject("deviceDelivery");if(delivery==null){delivery=new JSONObject();row.put("deviceDelivery",delivery);}delivery.put(device,obj("commandId",pending.commandId,"deliveryStatus",pending.status));saveCall(row);}
            }
            String password=random(), expiry=now().plusSeconds(3600).toString();
            JSONObject op=cloud.request("PUT","/accounts/"+operator,obj("password",password,"kind","operator","roomId",room,"expiresAt",expiry));
            JSONObject result=cloud.request("POST","/calls",obj("callId",id,"roomId",room,"participants",participants,"video",video));
            JSONObject credentials=obj("protocol","SIP","server",op.get("wssUrl"),"uri","sip:"+operator+"@"+op.getString("sipHost"),
                    "authorizationUsername",operator,"authorizationPassword",password,"target",result.get("target"),
                    "iceServers",op.get("iceServers"),"expiresAt",expiry,"video",video,"demo",false);
            row.put("status","offered");row.put("credentials",credentials);saveCall(row);
            JSONObject out=new JSONObject(credentials);out.put("channel",id);out.put("channelName",id);out.put("callId",id);return out;
        }catch(Exception error){row.put("status","unknown");row.put("message","云端呼叫结果未确认，请先结束本次会话");saveCall(row);
            return obj("protocol","SIP","callId",id,"channel",id,"channelName",id,"status","unknown","message",row.get("message"));}
    }
    /** These failures are proven before creating a media call or sending any command. */
    public synchronized void requireCallReady(List<String> devices){
        if(!available())throw com.ruoyi.guardian.AdminQueryService.fail(503,"MEDIA_SERVICE_UNAVAILABLE","云语音服务暂不可用，尚未发起呼叫");
        if(devices.isEmpty()||devices.size()>32)throw com.ruoyi.guardian.AdminQueryService.fail(400,"INVALID_CALL","请选择1至32个安全帽");
        for(String device:devices){
            if(hasActiveCall(device))throw com.ruoyi.guardian.AdminQueryService.fail(409,"CALL_BUSY","设备存在未结束通话，请先刷新或结束原通话");
            if(!gateway().isOnline(device))throw com.ruoyi.guardian.AdminQueryService.fail(409,"DEVICE_OFFLINE","设备离线，尚未发起呼叫");
            if(!registeredDevices.contains(device))throw com.ruoyi.guardian.AdminQueryService.fail(409,"SIP_NOT_REGISTERED","设备尚未注册SIP，尚未发起呼叫");
        }
    }
    public void endCall(String id) { coordinated(false,()->{endCallCoordinated(id);return null;}); }
    private synchronized void endCallCoordinated(String id) {
        JSONObject row=map(store.snapshot(),"calls").getJSONObject(id);
        if(row==null)throw new IllegalArgumentException("通话不存在");if("ended".equals(row.getString("status")))return;
        cloud.request("DELETE","/calls/"+id,null);row.put("status","ending");row.remove("credentials");saveCall(row);
    }
    public JSONObject callState(String id){JSONObject row=map(store.snapshot(),"calls").getJSONObject(id);if(row==null)return null;JSONObject out=new JSONObject(row);out.remove("credentials");return out;}
    public JSONObject credentials(String id,String actorId){
        JSONObject row=map(store.snapshot(),"calls").getJSONObject(id);
        if(row==null||!actorId.equals(row.getString("actorId")))throw new IllegalArgumentException("通话不存在");
        JSONObject credentials=row.getJSONObject("credentials");
        if(!Arrays.asList("offered","answered","connected").contains(row.getString("status"))||credentials==null||!Instant.parse(credentials.getString("expiresAt")).isAfter(now()))throw new IllegalArgumentException("通话凭据已失效");
        return new JSONObject(credentials);
    }
    public boolean receipt(String deviceId,JSONObject message) { return coordinated(false,()->receiptCoordinated(deviceId,message)); }
    private boolean receiptCoordinated(String deviceId,JSONObject message) { return receipt(deviceId,message,null); }
    public boolean receipt(String deviceId,JSONObject message,String receivedAt) { return coordinated(false,()->receiptCoordinated(deviceId,message,receivedAt)); }
    private synchronized boolean receiptCoordinated(String deviceId,JSONObject message,String receivedAt) {
        String act=text(message,"act");
        if(!Arrays.asList("ca_upload_photo","upload_video_success","push_to_client").contains(act))return false;
        String id=text(message,"talkback_id"); JSONObject res=message.getJSONObject("res");
        if(id.isEmpty()&&res!=null)id=text(res,"talkback_id");
        JSONObject row=map(store.snapshot(),"commands").getJSONObject(id);
        if(row==null||!deviceId.equals(row.getString("deviceId")))return true; // Uncorrelated legacy data never completes another command.
        if("push_to_client".equals(act)&&!Arrays.asList("list_recordings","upload_recording").contains(row.getString("action")))return false;
        if(!Arrays.asList("sent","requesting","queued","dispatching","unknown","timeout").contains(row.getString("status")))return true;
        row.put("receiptAt",receivedAt==null?now().toString():Instant.parse(receivedAt).toString());
        boolean success=res!=null?res.getBooleanValue("status"):message.getBooleanValue("status");
        if(clusteredCommands())commandRouter.acknowledge(id,deviceId,success);
        row.put("status",success?"acknowledged":"rejected");
        row.put("message",success?"设备已确认；上传文件是否入库请查看媒体列表":"设备拒绝了此操作");
        if("list_recordings".equals(row.getString("action"))&&res!=null)row.put("result",res.getJSONArray("data"));
        if(externalData!=null)externalData.record("helmet-media","安全帽媒体服务",row.getString("siteId"),"MEDIA",id+":"+act,message,id);
        saveCommand(row);return true;
    }
    @Scheduled(fixedDelay=15000,initialDelay=5000)
    public void reconcile() { refreshHealth(); coordinated(true,()->{reconcileCoordinated();return null;}); }
    private void reconcileCoordinated() {
        if(maintenance!=null && !maintenance.tryBeginWrite())return;
        try {
            com.ruoyi.guardian.PersonEquipmentContext equipment=equipmentContexts==null?null:equipmentContexts.getIfAvailable();
            if(equipment==null){synchronized(this){reconcileActive();}}
            else equipment.withSessionAuthority(authority->{synchronized(this){invalidateSessions(authority);reconcileActive();}});
        }
        finally { if(maintenance!=null)maintenance.endWrite(); }
    }
    /** Frozen authority view: no ledger callback while holding the media monitor. Historical assets are retained. */
    private void invalidateSessions(java.util.function.BiPredicate<String,JSONObject> authority) {
        JSONObject state=store.snapshot();
        for(Map.Entry<String,Object> entry:map(state,"streams").entrySet()) {
            String deviceId=entry.getKey();JSONObject stream=(JSONObject)entry.getValue(),viewers=map(stream,"viewers");
            boolean previouslyWatching=stream.getBooleanValue("watchRequested");
            for(String id:new ArrayList<>(viewers.keySet())) {
                JSONObject captured=new JSONObject(viewers.getJSONObject(id));captured.put("deviceId",deviceId);
                if(!authority.test(captured.getString("actorId"),captured))viewers.remove(id);
            }
            refreshWatching(stream);
            JSONObject command=map(state,"commands").getJSONObject(stream.getString("recordRequestId"));
            boolean recording=stream.getBooleanValue("recordRequested")||!text(stream,"recordingId").isEmpty();
            boolean invalid=(recording||stream.getBooleanValue("recordStartUnknown"))&&(stream.containsKey("sessionInvalidatedAt")||command==null||!authority.test(command.getString("actorId"),command));
            if(invalid){
                stream.put("recordRequested",false);stream.put("sessionInvalidatedAt",now().toString());
                saveStream(deviceId,stream); // Disable delayed recording before attempting external stop.
                if(command!=null){command.put("sessionInvalidatedAt",stream.get("sessionInvalidatedAt"));command.put("status",text(stream,"recordingId").isEmpty()&&!stream.getBooleanValue("recordStartUnknown")?"cancelled":"unknown");command.put("message","领用或权限已变化，正在结束原录像会话");saveCommand(command);}
                if(!text(stream,"recordingId").isEmpty())try{
                    // Cloud stopRecording only finalizes ffmpeg and registers the historical asset; it does not delete files.
                    cloud.request("DELETE","/recordings/"+stream.getString("recordingId"),null);
                    stream.put("cleanupStatus","requested");
                    if(command!=null){command.put("status","finalizing");command.put("message","原录像已请求停止，等待云端确认保存结果");saveCommand(command);}
                }catch(RuntimeException error){stream.put("cleanupStatus","unknown");}
            }
            saveStream(deviceId,stream);
            if((previouslyWatching||invalid)&&!stream.getBooleanValue("watchRequested")&&!stream.getBooleanValue("recordRequested")&&gateway().isOnline(deviceId))try{sendDevice(deviceId,obj("cmd","server_push_stop_rtsp"));}catch(Exception ignored){}
        }
        for(Object raw:map(store.snapshot(),"calls").values()) {
            JSONObject call=(JSONObject)raw;if(Arrays.asList("ended","failed").contains(call.getString("status")))continue;
            JSONArray recipients=call.getJSONArray("recipients");boolean valid=recipients!=null&&!recipients.isEmpty();
            if(valid)for(Object recipient:recipients)if(!authority.test(call.getString("actorId"),(JSONObject)recipient)){valid=false;break;}
            if(valid&&!call.containsKey("sessionInvalidatedAt"))continue;
            call.remove("credentials");call.put("sessionInvalidatedAt",now().toString());call.put("status","unknown");call.put("message","领用或权限已变化，原通话正在结束，结果待确认");saveCall(call);
            // Cloud endCall hangs up channels and retains the call record.
            try{cloud.request("DELETE","/calls/"+call.getString("id"),null);call.put("status","ending");saveCall(call);}catch(RuntimeException ignored){}
        }
    }
    public void refreshHealth(){
        if(!cloud.configured()){healthy=false;return;}
        try{
            JSONObject health=cloud.request("GET","/health",null);healthy=health.getBooleanValue("ready");
            ttsHealthy=health.getJSONObject("components")!=null&&health.getJSONObject("components").getBooleanValue("tts");
            if(!healthy){healthCheckedAt=System.nanoTime();return;}
            Set<String> registered=new HashSet<>();JSONArray registrations=health.getJSONArray("devices");
            if(registrations!=null)for(Object raw:registrations){JSONObject row=(JSONObject)raw;if(row.getBooleanValue("registered")&&row.getString("deviceId")!=null)registered.add(row.getString("deviceId"));}
            registeredDevices=registered;
            healthCheckedAt=System.nanoTime();
        }catch(RuntimeException unavailable){healthy=false;ttsHealthy=false;registeredDevices=Collections.emptySet();}
    }
    private void reconcileActive() {
        expireViewers();
        if(!cloud.configured()){healthy=false;return;}
        try {
            refreshHealth();if(!healthy)return;
            if(journal!=null&&coordinator!=null&&coordinator.enabled())journal.reconcile(hash->cloud.request("GET","/operations/"+hash,null));
            if(clusteredCommands())for(String device:commandRouter.knownHelmetDevices())if(gateway().supports(device)&&map(store.snapshot(),"accounts").getJSONObject(device)==null)pendingAccounts.add(device);
            for(Map.Entry<String,Object> entry:map(store.snapshot(),"accounts").entrySet())if(((JSONObject)entry.getValue()).getString("sipHost")==null)pendingAccounts.add(entry.getKey());
            for(String device:new HashSet<>(pendingAccounts)){try{provision(device);pendingAccounts.remove(device);}catch(RuntimeException pending){/* Durable claim/account remains pending; unrelated streams and receipts must still recover. */}}
            JSONObject state=store.snapshot();
            JSONObject events=cloud.request("GET","/events?after="+state.getLongValue("eventCursor")+"&limit=100",null);
            JSONArray entries=events.getJSONArray("events");if(entries==null)entries=events.getJSONArray("items");
            if(entries!=null)for(Object raw:entries)applyEvent((JSONObject)raw);
            reconcileCalls();resumeCompletedCalls();
            startPendingRecordings();
            reconcileRecordings();
            store.update(s->{for(Object raw:map(s,"commands").values()) {JSONObject c=(JSONObject)raw;
                if(Arrays.asList("sent","requesting").contains(c.getString("status"))&&Instant.parse(c.getString("expiresAt")).isBefore(now())){c.put("status","timeout");c.put("message","超时未收到可关联的设备确认，不代表设备未执行");}}
                return null;});
        } catch(RuntimeException error){healthy=false;}
    }
    private void applyEvent(JSONObject event) {
        if(event.getLongValue("sequence")<=store.snapshot().getLongValue("eventCursor"))return;
        JSONArray evidence=Arrays.asList("asset.ready","asset.bound").contains(text(event,"type"))&&!text(event,"deviceId").isEmpty()?assets(event.getString("deviceId")):new JSONArray();
        store.atomic(()->{applyEventSaved(event,evidence);return null;});
        resumeCompletedCalls();
    }
    private void applyEventSaved(JSONObject event,JSONArray evidence) {
        String callId=text(event,"callId"),type=text(event,"type");
        JSONObject call=map(store.snapshot(),"calls").getJSONObject(callId);
        if(call!=null&&Arrays.asList("call.answered","call.connected","call.ended","call.failed","call.participant-ended").contains(type)
                &&event.getLongValue("sequence")>call.getLongValue("lastCloudEventSequence")) {
            String status="call.participant-ended".equals(type)?call.getString("status"):type.substring(5);
            if(mergeCallEvidence(call,status,event)){
                call.put("lastCloudEventSequence",event.getLongValue("sequence"));
                if(Arrays.asList("ended","failed").contains(status))call.put("resumePending",true);saveCall(call);
            }
        }
        if(Arrays.asList("asset.ready","asset.bound").contains(type)&&!text(event,"deviceId").isEmpty()&&!text(event,"assetId").isEmpty()) {
            for(Object raw:evidence){JSONObject asset=(JSONObject)raw;
                if(!event.getString("assetId").equals(asset.getString("id")))continue;
                String requestId=asset.getString("requestId");JSONObject command=map(store.snapshot(),"commands").getJSONObject(requestId);
                if(command!=null){recordAsset(command,asset);
                    for(Object value:map(store.snapshot(),"commands").values()){JSONObject stop=(JSONObject)value;if(requestId.equals(stop.getString("sourceCommandId"))&&"finalizing".equals(stop.getString("status"))){stop.put("status","completed");stop.put("assetId",asset.get("id"));stop.put("message","录像文件已保存，可回放");saveCommand(stop);}}}}
        }
        store.update(s->{s.put("eventCursor",Math.max(s.getLongValue("eventCursor"),event.getLongValue("sequence")));return null;});
    }
    private void startPendingRecordings(){
        for(Map.Entry<String,Object> entry:map(store.snapshot(),"streams").entrySet()){
            JSONObject stream=(JSONObject)entry.getValue();if(!stream.getBooleanValue("recordRequested")||!text(stream,"recordingId").isEmpty())continue;
            JSONObject command=map(store.snapshot(),"commands").getJSONObject(stream.getString("recordRequestId"));if(command==null)continue;
            try{
                if(Instant.parse(command.getString("expiresAt")).isBefore(now())){stream.put("recordRequested",false);saveStream(entry.getKey(),stream);command.put("status","timeout");command.put("message","未收到真实视频，录像没有开始");saveCommand(command);if(!stream.getBooleanValue("watchRequested"))try{sendDevice(entry.getKey(),obj("cmd","server_push_stop_rtsp"));}catch(Exception ignored){}continue;}
                JSONObject actual=cloud.request("GET","/streams/"+stream.getString("streamId"),null);if(!actual.getBooleanValue("publishing"))continue;
                stream.put("recordStartUnknown",true);saveStream(entry.getKey(),stream);
                JSONObject recording=cloud.request("POST","/recordings",obj("streamId",stream.getString("streamId"),"requestId",command.get("id")));
                stream.put("recordingId",recording.get("recordingId"));stream.put("recordStartUnknown",false);saveStream(entry.getKey(),stream);command.put("status","starting");command.put("message","已收到设备视频，正在启动平台录像");saveCommand(command);
            }catch(RuntimeException error){command.put("message","录像启动结果待确认，正在核对同一请求");saveCommand(command);}
        }
    }
    private void resumeCompletedCalls(){
        for(Object raw:map(store.snapshot(),"calls").values()){JSONObject call=(JSONObject)raw;
            if(call.getBooleanValue("resumePending")&&resumeStreams(call)){call.put("resumePending",false);saveCall(call);}
        }
    }
    private boolean resumeStreams(JSONObject call) {
        boolean accepted=true;JSONArray devices=call.getJSONArray("deviceIds");if(devices==null)return true;
        for(Object raw:devices) {
            String device=String.valueOf(raw);JSONObject stream=map(store.snapshot(),"streams").getJSONObject(device);
            if(stream!=null&&(stream.getBooleanValue("watchRequested")||stream.getBooleanValue("recordRequested")))
                try{sendDevice(device,obj("cmd","server_push_open_rtsp","push_url",stream.getString("pushUrl")),"call-resume:"+call.getString("id"));}catch(com.ruoyi.cluster.DeviceCommandRouter.Pending durable){/* Persisted intent is recoverable. */}catch(Exception failed){accepted=false;}
        }
        return accepted;
    }
    private JSONObject stream(String deviceId) {
        JSONObject old=map(store.snapshot(),"streams").getJSONObject(deviceId);
        if(old!=null&&!text(old,"expiresAt").isEmpty()&&Instant.parse(old.getString("expiresAt")).isAfter(now().plusSeconds(30)))return old;
        if(old!=null&&!text(old,"streamId").isEmpty()){
            JSONObject fresh=cloud.request("GET","/streams/"+old.getString("streamId"),null);
            // Refresh signed URLs without abandoning an existing recorder or its owner intentions.
            old.putAll(fresh);saveStream(deviceId,old);return old;
        }
        String sessionId=old==null?null:old.getString("pendingSessionId");
        if(sessionId==null){sessionId=UUID.randomUUID().toString();saveStream(deviceId,obj("pendingSessionId",sessionId,"deviceId",deviceId));}
        JSONObject stream=cloud.request("POST","/streams",obj("deviceId",deviceId,"sessionId",sessionId));saveStream(deviceId,stream);return stream;
    }
    /** Human expiry/assignment cleanup and GB release each remove only their own demand. */
    private static void refreshWatching(JSONObject stream){
        JSONArray leases=stream.getJSONArray("gbLeaseIds");
        stream.put("watchRequested",!map(stream,"viewers").isEmpty()||(leases!=null&&!leases.isEmpty()));
    }
    private static void setGbWatcher(JSONObject stream,String leaseId,boolean watching){
        JSONArray leases=stream.getJSONArray("gbLeaseIds");if(leases==null)leases=new JSONArray();
        leases.remove(leaseId);if(watching)leases.add(leaseId);stream.put("gbLeaseIds",leases);
        refreshWatching(stream);
    }
    private static String viewerId(JSONObject input){String id=text(input,"viewerSessionId");if(!id.matches("[A-Za-z0-9_-]{8,100}"))throw new IllegalArgumentException("请提供观看会话编号");return id;}
    private static JSONObject ownedViewer(JSONObject stream,String actorId,JSONObject input) {
        JSONObject viewer=stream==null?null:map(stream,"viewers").getJSONObject(viewerId(input));
        if(viewer==null||!actorId.equals(viewer.getString("actorId")))throw new IllegalArgumentException("观看会话不存在或不属于当前账号");
        if(viewer.containsKey("assignmentId"))com.ruoyi.guardian.PersonEquipmentContext.sameContext(viewer,input);return viewer;
    }
    private void setViewer(JSONObject stream,String actorId,JSONObject input,boolean watching){
        JSONObject viewers=map(stream,"viewers");String id=viewerId(input);JSONObject prior=viewers.getJSONObject(id);
        if(prior!=null){if(!actorId.equals(prior.getString("actorId")))throw new IllegalArgumentException("观看会话已被其他账号使用");if(prior.containsKey("assignmentId"))com.ruoyi.guardian.PersonEquipmentContext.sameContext(prior,input);}
        if(watching){
            // GET /live omits server-owned site/area fields. Renew the original authorized lease,
            // otherwise the next assignment/permission reconciliation incorrectly revokes it.
            JSONObject viewer=prior==null?obj("actorId",actorId):new JSONObject(prior);
            viewer.put("expiresAt",now().plusSeconds(30).toString());
            for(String field:Arrays.asList("personId","assignmentId","assignmentVersion","siteId","areaId"))
                if(input.containsKey(field)&&!viewer.containsKey(field))viewer.put(field,input.get(field));
            viewers.put(id,viewer);
        }else viewers.remove(id);
        stream.remove("watchActorIds");refreshWatching(stream);
    }
    private void expireViewers(){
        for(Map.Entry<String,Object> entry:map(store.snapshot(),"streams").entrySet()){
            JSONObject stream=(JSONObject)entry.getValue(),viewers=map(stream,"viewers");boolean before=stream.getBooleanValue("watchRequested");
            for(String id:new ArrayList<>(viewers.keySet())){JSONObject viewer=viewers.getJSONObject(id);try{if(Instant.parse(viewer.getString("expiresAt")).isAfter(now()))continue;}catch(RuntimeException ignored){}viewers.remove(id);}
            stream.remove("watchActorIds");refreshWatching(stream);saveStream(entry.getKey(),stream);
            if(before&&!stream.getBooleanValue("watchRequested")&&!stream.getBooleanValue("recordRequested")&&gateway().isOnline(entry.getKey()))try{sendDevice(entry.getKey(),obj("cmd","server_push_stop_rtsp"));}catch(Exception ignored){}
        }
    }
    private void reconcileCalls(){
        for(Object raw:map(store.snapshot(),"calls").values()){
            JSONObject call=(JSONObject)raw;if(Arrays.asList("ended","failed").contains(call.getString("status")))continue;
            try{
                JSONObject actual=cloud.request("GET","/calls/"+call.getString("id"),null);
                if(actual==null)continue;String status=text(actual,"status");
                if(!Arrays.asList("offered","answered","connected","ending","ended","failed").contains(status))continue;
                if(mergeCallEvidence(call,status,actual)){
                    saveCall(call);if(Arrays.asList("ended","failed").contains(status))resumeStreams(call);
                }
            }catch(RuntimeException ignored){/* Keep unknown rather than releasing a potentially active camera. */}
        }
    }
    /** A device leg answering is distinct from the browser and device both joining. */
    private boolean mergeCallEvidence(JSONObject call,String status,JSONObject evidence){
        String current=text(call,"status");
        if(Arrays.asList("ended","failed").contains(current))return false;
        boolean terminal=Arrays.asList("ended","failed").contains(status);
        if(!terminal){
            if(call.containsKey("sessionInvalidatedAt"))return false;
            List<String> stages=Arrays.asList("offered","answered","connected","ending");
            if(stages.contains(current)&&stages.contains(status)&&stages.indexOf(status)<stages.indexOf(current))return false;
        }
        call.put("status",status);
        if(evidence.containsKey("connectedDeviceIds")){
            JSONArray allowed=call.getJSONArray("deviceIds"),reported=evidence.getJSONArray("connectedDeviceIds"),connected=new JSONArray();
            if(!terminal&&allowed!=null&&reported!=null)for(Object id:reported)if(id instanceof String&&allowed.contains(id)&&!connected.contains(id))connected.add(id);
            call.put("connectedDeviceIds",connected);
        }else if(terminal)call.put("connectedDeviceIds",new JSONArray());
        if(evidence.containsKey("statusVerified"))call.put("statusVerified",evidence.getBooleanValue("statusVerified"));else call.remove("statusVerified");
        call.put("updatedAt",evidence.containsKey("createdAt")?evidence.get("createdAt"):now().toString());
        if(terminal)call.remove("credentials");return true;
    }
    private void reconcileRecordings(){
        for(Map.Entry<String,Object> entry:map(store.snapshot(),"streams").entrySet()){
            JSONObject stream=(JSONObject)entry.getValue();String id=text(stream,"recordingId");if(id.isEmpty())continue;
            try{
                JSONObject actual=cloud.request("GET","/recordings/"+id,null);String status=text(actual,"status");
                JSONObject command=map(store.snapshot(),"commands").getJSONObject(stream.getString("recordRequestId"));
                boolean terminal=Arrays.asList("ready","failed","interrupted").contains(status);
                if(command!=null){
                    if("recording".equals(status)&&!command.containsKey("sessionInvalidatedAt")){command.put("status","recording");command.put("message","平台正在录制设备视频");}
                    if(terminal){command.put("status","ready".equals(status)?"completed":"failed");command.put("message","ready".equals(status)?"录像文件已保存，可回放":"录像已中断或失败，未确认有完整文件");command.put("assetId",actual.get("assetId"));}
                    saveCommand(command);
                }
                if(terminal){stream.put("recordRequested",false);stream.remove("recordingId");saveStream(entry.getKey(),stream);
                    if(!stream.getBooleanValue("watchRequested")&&gateway().isOnline(entry.getKey()))try{sendDevice(entry.getKey(),obj("cmd","server_push_stop_rtsp"));}catch(Exception ignored){}
                }
            }catch(RuntimeException ignored){/* Keep last confirmed state; do not silently start a second recorder. */}
        }
        for(Object raw:map(store.snapshot(),"commands").values()){
            JSONObject command=(JSONObject)raw;if(!"stop_recording".equals(command.getString("action"))||!"finalizing".equals(command.getString("status")))continue;
            try{JSONObject actual=cloud.request("GET","/recordings/"+command.getString("recordingId"),null);String status=text(actual,"status");
                if(Arrays.asList("ready","failed","interrupted").contains(status)){command.put("status","ready".equals(status)?"completed":"failed");command.put("message","ready".equals(status)?"录像文件已保存，可回放":"录像封装失败，未确认有完整文件");command.put("assetId",actual.get("assetId"));saveCommand(command);}}
            catch(RuntimeException ignored){}
        }
    }
    private JSONArray validateListedFiles(String deviceId,JSONArray files){
        Map<String,JSONObject> known=new HashMap<>();
        for(Object raw:map(store.snapshot(),"commands").values()){
            JSONObject command=(JSONObject)raw;if(!deviceId.equals(command.getString("deviceId"))||!"list_recordings".equals(command.getString("action"))||!"acknowledged".equals(command.getString("status")))continue;
            JSONArray result=command.getJSONArray("result");if(result==null)continue;
            for(Object item:result){if(item instanceof JSONObject){JSONObject value=(JSONObject)item;for(String key:Arrays.asList("file_name","fileName","name"))if(!text(value,key).isEmpty())known.put(text(value,key),obj("fileName",text(value,key),"progressId",value.get("file_md5")));}else if(item instanceof String)known.put((String)item,obj("fileName",item));}
        }
        JSONArray requested=new JSONArray();for(Object file:files){JSONObject found=known.get(String.valueOf(file));if(found==null)throw new IllegalArgumentException("请先查询设备录像，再选择设备实际返回的文件");requested.add(found);}return requested;
    }
    private JSONObject assetCommand(String deviceId,JSONObject asset){
        if(!deviceId.equals(asset.getString("deviceId"))||!"ready".equals(asset.getString("status")))return null;
        String requestId=text(asset,"requestId");
        if(!requestId.isEmpty()) {
            JSONObject direct=map(store.snapshot(),"commands").getJSONObject(requestId);
            if(direct==null||!deviceId.equals(direct.getString("deviceId")))return null;
            String action=text(direct,"action");
            if(!("photo".equals(asset.getString("kind"))&&"take_photo".equals(action)
                    ||"video".equals(asset.getString("kind"))&&Arrays.asList("start_recording","upload_recording").contains(action)))return null;
            // A real device echo identifies the request, but cannot give an older file a
            // new wearer or turn a different operation into a capture. Never match by time alone.
            if(!assetArrivedAfterCommand(asset,direct))return null;
            String completedAsset=text(direct,"assetId");
            if(!"upload_recording".equals(action)&&!completedAsset.isEmpty()&&!completedAsset.equals(text(asset,"assetId")))return null;
            return direct;
        }
        if(!"video".equals(asset.getString("kind")))return null;
        String progress=text(asset,"progressId"),name=text(asset,"originalName");
        if(progress.isEmpty()||name.isEmpty())return null;JSONObject match=null;
        for(Object raw:map(store.snapshot(),"commands").values()){
            JSONObject command=(JSONObject)raw;if(!deviceId.equals(command.getString("deviceId"))||!"upload_recording".equals(command.getString("action")))continue;
            JSONArray requested=command.getJSONArray("requestedFiles");if(requested==null)continue;
            if(!assetArrivedAfterCommand(asset,command))continue;
            for(Object value:requested){JSONObject file=(JSONObject)value;if(progress.equals(text(file,"progressId"))&&name.equals(text(file,"fileName"))){if(match!=null)return null;match=command;break;}}
        }return match;
    }
    private static boolean assetArrivedAfterCommand(JSONObject asset,JSONObject command) {
        try{return !Instant.parse(text(asset,"createdAt")).isBefore(Instant.parse(text(command,"createdAt")));}
        catch(RuntimeException error){return false;}
    }
    private void recordAsset(JSONObject command,JSONObject asset){
        if(externalData!=null)externalData.record("helmet-media","安全帽媒体服务",asset.getString("siteId"),"MEDIA",asset.getString("id"),asset,asset.getString("id"));
        JSONArray requested=command.getJSONArray("requestedFiles");
        if("upload_recording".equals(command.getString("action"))&&requested!=null){
            JSONObject received=command.getJSONObject("receivedFiles");if(received==null)received=new JSONObject();
            received.put(asset.getString("originalName"),asset.get("id"));command.put("receivedFiles",received);
            boolean all=true;for(Object raw:requested)if(!received.containsKey(((JSONObject)raw).getString("fileName")))all=false;
            command.put("status",all?"completed":"receiving_files");command.put("message",all?"所选录像已全部保存，可查看或回放":"部分录像已保存，仍在等待其他文件");
        }else{command.put("status","completed");command.put("message","文件已保存，可查看或回放");}
        command.put("assetId",asset.get("id"));saveCommand(command);
    }
    private boolean hasActiveCall(String device) {
        for(Object raw:map(store.snapshot(),"calls").values()){JSONObject call=(JSONObject)raw;if(!Arrays.asList("ended","failed").contains(call.getString("status"))&&call.getJSONArray("deviceIds").contains(device))return true;}return false;
    }
    public static JSONObject wire(String action,JSONObject p) {
        switch(action) {
            case "take_photo": return obj("cmd","server_push_take_photo");
            case "start_video":return obj("cmd","server_push_open_rtsp");
            case "stop_video":return obj("cmd","server_push_stop_rtsp");
            case "broadcast":return obj("cmd","server_push_ma_broadcast");
            case "list_recordings":
                String from=text(p,"startTime"),to=text(p,"endTime");
                if(!from.matches("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}")||!to.matches("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}")||from.compareTo(to)>=0)throw new IllegalArgumentException("请填写正确的录像起止时间");
                java.time.format.DateTimeFormatter inputFormat=java.time.format.DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss").withResolverStyle(java.time.format.ResolverStyle.STRICT);
                java.time.format.DateTimeFormatter wireFormat=java.time.format.DateTimeFormatter.ofPattern("yyyyMMddHHmmss");
                try{return obj("cmd","server_push_get_local_video_list","start_time",java.time.LocalDateTime.parse(from,inputFormat).format(wireFormat),"end_time",java.time.LocalDateTime.parse(to,inputFormat).format(wireFormat));}
                catch(java.time.DateTimeException error){throw new IllegalArgumentException("录像日期无效");}
            case "upload_recording":
                JSONArray files=p.getJSONArray("files");if(files==null||files.isEmpty()||files.size()>20)throw new IllegalArgumentException("请选择1至20个设备录像");
                for(Object f:files)if(!(f instanceof String)||((String)f).length()>200||((String)f).contains("..")||((String)f).contains("\\"))throw new IllegalArgumentException("录像文件名无效");
                return obj("cmd","server_push_upload_video","file_list",files);
            case "set_config":
                // This firmware applies the entire settings bundle. Never fill omitted fields with defaults.
                Set<String> keys=new HashSet<>(Arrays.asList("sos_height","local_record","electrostatic","record_video_name","privacy_switch"));
                if(!p.keySet().equals(keys))throw new IllegalArgumentException("设备要求完整参数组，请先确认当前设置后提交");
                if(!text(p,"sos_height").matches("[0-9]{1,3}(\\.[0-9]{1,2})?")||!text(p,"local_record").matches("[01]")||!text(p,"electrostatic").matches("[01]")||!text(p,"privacy_switch").matches("[01]")||text(p,"record_video_name").length()>80)throw new IllegalArgumentException("设备参数格式无效");
                JSONObject config=new JSONObject(p);config.put("cmd","server_push_set_sos_height");return config;
            default:return new JSONObject();
        }
    }
    private void sent(JSONObject row){row.put("status","sent");row.put("message","指令已发送，等待设备确认");row.put("sentAt",now().toString());}
    private void saveCommand(JSONObject row){store.update(s->{
        JSONObject old=map(s,"commands").getJSONObject(row.getString("id")),next=new JSONObject(row);
        if(old!=null){
            for(String key:Arrays.asList("receiptAt","result","receipt","assetId"))if(old.containsKey(key)&&!next.containsKey(key))next.put(key,old.get(key));
            if(Arrays.asList("acknowledged","rejected","completed","finalizing","recording").contains(old.getString("status"))
                    &&Arrays.asList("requesting","queued","sent","unknown","timeout").contains(next.getString("status"))&&!next.containsKey("sessionInvalidatedAt"))
                for(String key:Arrays.asList("status","message","receiptAt","result"))if(old.containsKey(key))next.put(key,old.get(key));
        }
        map(s,"commands").put(row.getString("id"),next);return null;});}
    private void saveCall(JSONObject row){store.update(s->{map(s,"calls").put(row.getString("id"),new JSONObject(row));return null;});}
    private void saveStream(String id,JSONObject row){store.update(s->{map(s,"streams").put(id,new JSONObject(row));return null;});}
    private void sendDevice(String device,JSONObject wire,String purpose) throws java.io.IOException {if(clusteredCommands())gateway().sendCommand(device,wire,purpose);else gateway().sendCommand(device,wire);}
    private void sendDevice(String device,JSONObject wire) throws java.io.IOException {
        if(!clusteredCommands()){gateway().sendCommand(device,wire);return;}
        JSONObject stream=map(store.snapshot(),"streams").getJSONObject(device);
        JSONObject purpose=new JSONObject();if(stream!=null)for(String key:Arrays.asList("recordRequestId","recordingId","viewers","watchRequested","recordRequested","sessionInvalidatedAt"))purpose.put(key,stream.get(key));
        gateway().sendCommand(device,wire,"media:"+com.ruoyi.cluster.DeviceCommandRouter.fingerprint(purpose));
    }
    private JSONObject publicCommand(JSONObject row){JSONObject out=new JSONObject(row);
        if(clusteredCommands()){JSONObject delivery=commandRouter.read(row.getString("id"));if(delivery!=null){String state=delivery.getString("deliveryStatus");out.put("deliveryStatus","PREPARING".equals(state)?"QUEUED":state);out.put("deliveryReason",delivery.get("deliveryReason"));
            if(Arrays.asList("requesting","queued","dispatching","sent","unknown","timeout").contains(out.getString("status"))){
                String status="PREPARING".equals(state)?"requesting":state.toLowerCase(java.util.Locale.ROOT);
                if("start_recording".equals(out.getString("action"))&&Arrays.asList("SENT","ACKNOWLEDGED").contains(state)){status="waiting_media";out.put("message","已请求设备推流，收到真实视频后开始录像");}
                else out.put("message",delivery.get("deliveryReason")!=null?delivery.get("deliveryReason"):"QUEUED".equals(state)?"请求已保存，等待设备所在节点发送":"正在准备设备操作");out.put("status",status);
            }
        }}
        for(String key:Arrays.asList("fingerprint","wire"))out.remove(key);return out;
    }
    private DirectHelmetGateway gateway(){return gateways.getObject();}
    private void requireCloud(){if(!available())throw new IllegalStateException("云媒体服务未就绪，请先完成部署和健康检查");}
    private static JSONObject map(JSONObject s,String key){JSONObject value=s.getJSONObject(key);if(value==null){value=new JSONObject();s.put(key,value);}return value;}
    private static String text(JSONObject s,String key){String value=s.getString(key);return value==null?"":value.trim();}
    private static String random(){return UUID.randomUUID().toString().replace("-","")+UUID.randomUUID().toString().replace("-","");}
    public static JSONObject obj(Object... pairs){JSONObject out=new JSONObject();for(int i=0;i<pairs.length;i+=2)out.put((String)pairs[i],pairs[i+1]);return out;}
}
