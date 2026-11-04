package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Mobile session records around the existing device platform, never phone-to-phone RTC. */
@RestController
@RequestMapping("/api/guardian/v1/mobile")
public class GuardianMobileCommunications {
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterWorkCoordinator coordinator;
    private final GuardianStore store;
    private final GuardianAccess access;
    private final GuardianVoiceService voice;
    @org.springframework.beans.factory.annotation.Autowired private PersonEquipmentContext equipment;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableMaintenance maintenance;
    public GuardianMobileCommunications(GuardianStore store,GuardianAccess access,GuardianVoiceService voice){this.store=store;this.access=access;this.voice=voice;}
    @ModelAttribute public void privateResponses(javax.servlet.http.HttpServletResponse response){response.setHeader("Cache-Control","no-store, private");response.setHeader("Pragma","no-cache");}

    @PostMapping("/calls") public JSONObject start(@RequestBody JSONObject input,HttpServletRequest request){
        if(coordinator!=null&&coordinator.enabled())return coordinator.run("media",false,()->startCoordinated(input,request));
        return startCoordinated(input,request);
    }
    private synchronized JSONObject startCoordinated(JSONObject input,HttpServletRequest request){
        return equipment.execute(WearableSessions.actor(request),ctx->start(ctx,input));
    }
    private JSONObject start(GuardianAccess.Context ctx,JSONObject input){
        // Retry identifies an already-owned request; it must not become a new-call
        // validation failure that hides the original session after return/reassignment.
        JSONObject previous=previous(ctx,input,"call");if(previous!=null){own(ctx,previous);refreshCall(previous);return recover(ctx,previous);}
        JSONObject device=device(ctx,input.getString("deviceId"),"communications:voice");
        JSONObject target=equipment.require(ctx,device.getString("portalDeviceId"),input,"voice","communications:voice");
        if(input.getBooleanValue("video"))equipment.require(ctx,device.getString("portalDeviceId"),input,"videoCall","communications:voice");
        event(ctx,input.getString("eventId"));
        if(input.getBooleanValue("video")&&!voice.isDirect(device.getString("portalDeviceId")))throw fail(400,"VOICE_ONLY","此设备当前仅支持安全帽语音");
        for(Object raw:rows(store.snapshot(),"sharedCommunications")){
            JSONObject existing=(JSONObject)raw;
            if("call".equals(existing.getString("operationType"))&&ctx.id().equals(existing.getString("requesterUserId"))&&device.getString("portalDeviceId").equals(existing.getString("deviceId"))){
                refreshCall(existing);if(activeCall(existing))throw fail(409,"CALL_BUSY","当前设备存在未结束请求，请先刷新或结束原通话");
            }
        }
        if(voice.isDirect(device.getString("portalDeviceId")))voice.directMedia().requireCallReady(Collections.singletonList(device.getString("portalDeviceId")));
        JSONObject row=base(ctx,input,"call");row.put("deviceId",device.getString("portalDeviceId"));row.put("siteId",device.getString("siteId"));row.put("areaId",device.get("areaId"));row.put("status","requesting");row.put("kind","single");row.put("video",false);row.put("demo",false);
        row.putAll(target);row.put("sn",device.getString("portalDeviceId"));row.put("personId",target.get("personId"));row.put("acceptanceTest",input.getBooleanValue("acceptanceTest"));save(row);
        try {
            JSONArray hats=new JSONArray();JSONObject recipient=copy(target);recipient.put("hatNumber",device.getString("portalDeviceId"));hats.add(recipient);
            Map<String,Object> rtc=voice.call(hats,ctx.id(),input.getBooleanValue("video"));
            if("unknown".equals(rtc.get("status"))){row.put("protocol","SIP");row.put("channelName",rtc.get("channel"));row.put("status","unknown");row.put("errorCode","PLATFORM_UNCONFIRMED");row.put("failReason",rtc.get("message"));save(row);return publicRow(row);}
            row.put("channelName",rtc.get("channel"));row.put("status","offered");row.put("expiresAt",Instant.now().plusSeconds(3600).toString());
            row.put("credentials",object("agoraAppId",rtc.get("appId"),"channelName",rtc.get("channel"),"agoraToken",rtc.get("token"),"agoraUid",rtc.get("uid"),"expiresAt",row.get("expiresAt"),"demo",false,"video",false));
            if("SIP".equals(rtc.get("protocol"))){row.put("protocol","SIP");row.put("video",input.getBooleanValue("video"));row.put("credentials",new JSONObject(rtc));row.put("expiresAt",rtc.get("expiresAt"));}
            save(row);return offered(row,true);
        }catch(AdminQueryService.QueryFailed error){
            if(Arrays.asList("CALL_BUSY","DEVICE_OFFLINE","SIP_NOT_REGISTERED","MEDIA_SERVICE_UNAVAILABLE","INVALID_CALL").contains(error.errorCode)){
                row.put("status","failed");row.put("errorCode",error.errorCode);row.put("failReason",error.getMessage());row.put("submissionState","NOT_SENT");save(row);throw error;
            }
            return unconfirmed(row);
        }catch(RuntimeException error){return unconfirmed(row);}
    }
    @GetMapping("/calls") public JSONArray calls(@RequestParam(required=false)String eventId,@RequestParam(required=false)String deviceId,@RequestParam(required=false)String personId,@RequestParam(defaultValue="false")boolean owned,@RequestParam(required=false)String status,HttpServletRequest request){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));JSONArray out=new JSONArray();
        for(Object raw:rows(store.snapshot(),"sharedCommunications")){JSONObject row=(JSONObject)raw;
            if("call".equals(row.getString("operationType"))&&visible(ctx,row)&&(!owned||ctx.id().equals(row.getString("requesterUserId")))&& (eventId==null||eventId.equals(row.getString("eventId")))&&(deviceId==null||deviceId.equals(row.getString("deviceId")))&&(personId==null||personId.equals(row.getString("personId")))){
                if(owned)refreshCall(row);
                if(status==null||("active".equals(status)?activeCall(row):status.equals(row.getString("status"))))out.add(publicRow(row));
            }}
        return out;
    }
    @GetMapping("/calls/{id}") public JSONObject details(@PathVariable String id,HttpServletRequest r){return publicRow(owned(id,r));}
    /** Same controller -> ledger -> media order as start(); no browser heartbeat is needed to revoke a call. */
    @org.springframework.scheduling.annotation.Scheduled(fixedDelay=15000,initialDelay=10000)
    public void reconcileInvalidSessions(){
        if(coordinator!=null&&coordinator.enabled()){coordinator.run("media",true,()->{reconcileInvalidSessionsCoordinated();return null;});return;}
        reconcileInvalidSessionsCoordinated();
    }
    private void reconcileInvalidSessionsCoordinated(){
        if(maintenance!=null&&!maintenance.tryBeginWrite())return;
        try { equipment.withSessionAuthority(authority->{
            for(Object raw:rows(store.snapshot(),"sharedCommunications")){
                JSONObject row=(JSONObject)raw;
                if(!"call".equals(row.getString("operationType"))||Arrays.asList("ended","failed").contains(row.getString("status"))||!row.containsKey("sessionInvalidatedAt")&&authority.test(row.getString("requesterUserId"),row))continue;
                row.remove("credentials");row.put("sessionInvalidatedAt",Instant.now().toString());row.put("status","unknown");row.put("failReason","领用或权限已变化，原通话正在结束，结果待确认");save(row);
                try{
                    if(text(row,"channelName").isEmpty())continue;
                    voice.end(row.getString("channelName"));row.put("status","ending");
                    if("SIP".equals(row.getString("protocol"))){JSONObject remote=voice.directMedia().callState(row.getString("channelName"));if(remote!=null&&Arrays.asList("ended","failed").contains(remote.getString("status")))row.put("status",remote.getString("status"));}
                    else row.put("status","ended");
                    save(row);
                }catch(RuntimeException ignored){/* Retain unknown and retry hangup; never return stale credentials. */}
            }
        }); } finally {if(maintenance!=null)maintenance.endWrite();}
    }
    @GetMapping("/calls/{id}/credentials") public JSONObject credentials(@PathVariable String id,HttpServletRequest r){
        return equipment.execute(WearableSessions.actor(r),ctx->{JSONObject row=owned(id,r);requireCall(ctx,row);offered(row,false);return copy(row.getJSONObject("credentials"));});
    }
    @PostMapping("/calls/{id}/joined") public JSONObject joined(@PathVariable String id,@RequestBody JSONObject body,HttpServletRequest r){
        if(coordinator!=null&&coordinator.enabled())return coordinator.run("media",false,()->joinedCoordinated(id,body,r));
        return joinedCoordinated(id,body,r);
    }
    private synchronized JSONObject joinedCoordinated(String id,JSONObject body,HttpServletRequest r){
        JSONObject row=owned(id,r);requireCall(access.context(WearableSessions.actor(r)),row);offered(row,false);
        if("SIP".equals(row.getString("protocol"))){row.put("clientJoinedAt",Instant.now().toString());save(row);return publicRow(row);}
        if(!Objects.equals(String.valueOf(row.getJSONObject("credentials").get("agoraUid")),body.getString("agoraUid")))throw fail(400,"UID_MISMATCH","通话身份不匹配");
        row.put("status","connected");row.put("connectedAt",Instant.now().toString());row.put("connectionQuality","local_joined");save(row);return publicRow(row);
    }
    @PostMapping("/calls/{id}/end") public JSONObject end(@PathVariable String id,HttpServletRequest r){
        if(coordinator!=null&&coordinator.enabled())return coordinator.run("media",false,()->endCoordinated(id,r));
        return endCoordinated(id,r);
    }
    private synchronized JSONObject endCoordinated(String id,HttpServletRequest r){
        JSONObject row=owned(id,r);if("ended".equals(row.getString("status")))return publicRow(row);
        if(text(row,"channelName").isEmpty())throw fail(409,"PLATFORM_UNCONFIRMED","未取得设备频道，无法确认挂断，请核实设备状态");
        voice.end(row.getString("channelName"));row.put("status","SIP".equals(row.getString("protocol"))?"ending":"ended");row.put("endedAt",Instant.now().toString());row.remove("credentials");save(row);return publicRow(row);
    }
    @PostMapping("/broadcast") public JSONArray broadcast(@RequestBody JSONObject input,HttpServletRequest r){
        if(coordinator!=null&&coordinator.enabled())return coordinator.run("media",false,()->broadcastCoordinated(input,r));
        return broadcastCoordinated(input,r);
    }
    private synchronized JSONArray broadcastCoordinated(JSONObject input,HttpServletRequest r){
        return equipment.execute(WearableSessions.actor(r),ctx->broadcast(ctx,input));
    }
    private JSONArray broadcast(GuardianAccess.Context ctx,JSONObject input){
        JSONArray requested=input.getJSONArray("recipients"),ids=new JSONArray();String text=text(input,"text");
        if(requested==null||requested.isEmpty()||requested.size()>50||text.isEmpty()||text.length()>200)throw fail(400,"INVALID_BROADCAST","请选择已领用的设备，广播内容为1至200字");
        JSONArray hats=new JSONArray(),recipients=new JSONArray();String site=null;
        for(int i=0;i<requested.size();i++){JSONObject request=copy(requested.getJSONObject(i));request.put("acceptanceTest",input.getBooleanValue("acceptanceTest"));JSONObject d=device(ctx,request.getString("deviceId"),"communications:broadcast");JSONObject recipient=equipment.require(ctx,d.getString("portalDeviceId"),request,"broadcast","communications:broadcast");if(ids.contains(d.getString("portalDeviceId")))throw fail(400,"INVALID_BROADCAST","广播设备不能重复");if(site!=null&&!site.equals(d.getString("siteId")))throw fail(400,"SITE_MISMATCH","广播设备必须属于同一厂站");site=d.getString("siteId");recipient.put("hatNumber",d.getString("portalDeviceId"));hats.add(recipient);recipients.add(copy(recipient));ids.add(d.getString("portalDeviceId"));}
        event(ctx,input.getString("eventId"));JSONObject previous=previous(ctx,input,"broadcast");if(previous!=null){if(!"accepted".equals(previous.getString("status")))throw fail(409,"PLATFORM_UNCONFIRMED","上次广播结果未确认，不能自动重发");return broadcastResult(previous);}
        JSONObject row=base(ctx,input,"broadcast");row.put("deviceIds",ids);row.put("recipients",recipients);row.put("siteId",site);row.put("text",text);row.put("status","requesting");save(row);
        try{if(voice.durableBroadcastEnabled())row.put("commandResults",voice.broadcastCommands(hats,text,ctx.id(),ctx.name(),input.getString("idempotencyKey")));else voice.broadcast(hats,text,ctx.id(),ctx.name());row.put("status","accepted");save(row);return broadcastResult(row);}
        catch(RuntimeException error){row.put("status","unknown");row.put("failReason","设备平台受理结果未确认，未报告播放成功");save(row);throw fail(502,"PLATFORM_UNCONFIRMED",row.getString("failReason"));}
    }
    private JSONArray broadcastResult(JSONObject row){if(row.getJSONArray("commandResults")!=null)return voice.refreshBroadcastCommands(row.getJSONArray("commandResults"));JSONArray out=new JSONArray();for(Object id:row.getJSONArray("deviceIds"))out.add(object("id",row.getString("id")+":"+id,"deviceId",id,"status","accepted","vendorMsg","设备平台已受理，实际播放待设备确认"));return out;}
    private JSONObject owned(String id,HttpServletRequest r){GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONObject row=find(store.snapshot(),"sharedCommunications",id);own(ctx,row);if(!visible(ctx,row))throw fail(403,"PERMISSION_DENIED","通话不在授权范围");
        refreshCall(row);return row;}
    private void refreshCall(JSONObject row){
        if(!"SIP".equals(row.getString("protocol"))||text(row,"channelName").isEmpty())return;
        JSONObject before=copy(row),remote;
        try{remote=voice.directMedia().callState(row.getString("channelName"));}catch(GuardianRejected error){return;}
        if(remote==null)return;
        row.put("status",remote.get("status"));row.put("serverConnected","connected".equals(remote.getString("status")));
        if(remote.containsKey("connectedDeviceIds"))row.put("connectedDeviceIds",remote.get("connectedDeviceIds"));
        if(remote.containsKey("statusVerified"))row.put("statusVerified",remote.get("statusVerified"));else row.remove("statusVerified");
        if(Arrays.asList("ended","failed").contains(remote.getString("status")))row.remove("credentials");
        if(!before.equals(row))save(row);
    }
    private static boolean activeCall(JSONObject row){return !Arrays.asList("ended","failed").contains(row.getString("status"));}
    private JSONObject recover(GuardianAccess.Context ctx,JSONObject row){
        if(Arrays.asList("offered","answered","connected").contains(row.getString("status"))&&row.getJSONObject("credentials")!=null&&Instant.parse(row.getString("expiresAt")).isAfter(Instant.now())){
            try{requireCall(ctx,row);return offered(row,true);}
            catch(AdminQueryService.QueryFailed error){JSONObject out=publicRow(row);out.put("recoveryOnly",true);out.put("operationErrorCode",error.errorCode);return out;}
        }
        return publicRow(row);
    }
    private JSONObject unconfirmed(JSONObject row){row.put("status","unknown");row.put("errorCode","PLATFORM_UNCONFIRMED");row.put("failReason","设备平台结果未确认，请刷新原记录核实，勿重复发起");save(row);return publicRow(row);}
    private static void own(GuardianAccess.Context ctx,JSONObject row){if(row==null||!ctx.id().equals(row.getString("requesterUserId")))throw fail(404,"CALL_NOT_FOUND","通话不存在或不属于当前账号");}
    private JSONObject previous(GuardianAccess.Context ctx,JSONObject input,String type){
        String key=text(input,"idempotencyKey");if(!key.matches("[A-Za-z0-9_-]{8,100}"))throw fail(400,"REQUEST_ID_REQUIRED","请提供稳定的请求编号");
        String hash=org.apache.commons.codec.digest.DigestUtils.sha256Hex(input.toJSONString());
        for(Object raw:rows(store.snapshot(),"sharedCommunications")){JSONObject r=(JSONObject)raw;if(ctx.id().equals(r.getString("requesterUserId"))&&key.equals(r.getString("requestId"))&&type.equals(r.getString("operationType"))){if(!hash.equals(r.getString("fingerprint")))throw fail(409,"IDEMPOTENCY_CONFLICT","相同请求编号不能用于不同内容");return r;}}return null;
    }
    private JSONObject base(GuardianAccess.Context ctx,JSONObject input,String type){return object("id","COMM-"+UUID.randomUUID(),"operationType",type,"requesterUserId",ctx.id(),"actorName",ctx.name(),"eventId",input.get("eventId"),"requestId",input.get("idempotencyKey"),"fingerprint",org.apache.commons.codec.digest.DigestUtils.sha256Hex(input.toJSONString()),"startedAt",Instant.now().toString(),"version",1);}
    private void save(JSONObject row){store.update(state->{JSONArray list=rows(state,"sharedCommunications");JSONObject prior=find(state,"sharedCommunications",row.getString("id"));if(prior!=null)list.remove(prior);row.put("version",row.getIntValue("version")+1);list.add(0,copy(row));state.put("seq",state.getIntValue("seq")+1);return true;});}
    private JSONObject offered(JSONObject row,boolean credentials){
        if(!Arrays.asList("offered","answered","connected").contains(row.getString("status")))throw fail(409,"CALL_UNAVAILABLE","通话结果未确认或已经结束，请刷新记录核实");
        if(row.getJSONObject("credentials")==null||!Instant.parse(row.getString("expiresAt")).isAfter(Instant.now()))throw fail(409,"CALL_EXPIRED","通话凭证已过期，请结束此会话");
        JSONObject out=publicRow(row);if(credentials)out.put("credentials",copy(row.getJSONObject("credentials")));return out;
    }
    private JSONObject device(GuardianAccess.Context ctx,String id,String operation){
        for(Object raw:rows(ctx.data,"devices")){JSONObject d=(JSONObject)raw;if(Objects.equals(id,d.getString("portalDeviceId"))){
            if(!ctx.can(operation,d.getString("siteId"),d.getString("areaId")))throw fail(403,"PERMISSION_DENIED","设备不在通讯授权范围");
            if(!"HELMET".equals(d.getString("type"))||!Arrays.asList("PLATFORM","DIRECT_HELMET").contains(d.getString("source"))||Arrays.asList("DISABLED","SCRAPPED").contains(d.getString("lifecycle")))throw fail(409,"DEVICE_UNAVAILABLE","此设备尚无可用的真实安全帽通讯能力");return d;}}
        throw fail(404,"DEVICE_NOT_FOUND","设备不存在或不在授权范围");
    }
    private void event(GuardianAccess.Context ctx,String id){if(id!=null&&!id.isEmpty())ctx.requireEvent(find(store.snapshot(),"events",id),null);}
    private void requireCall(GuardianAccess.Context ctx,JSONObject row){equipment.require(ctx,row.getString("deviceId"),row,"voice","communications:voice");if(row.getBooleanValue("video"))equipment.require(ctx,row.getString("deviceId"),row,"videoCall","communications:voice");}
    static boolean visible(GuardianAccess.Context ctx,JSONObject row){
        if("call".equals(row.getString("operationType")))return ctx.can("communications:voice",row.getString("siteId"),row.getString("areaId"));
        for(Object raw:rows(row,"recipients"))if(!ctx.can("communications:broadcast",row.getString("siteId"),((JSONObject)raw).getString("areaId")))return false;return ctx.site(row.getString("siteId"));
    }
    static JSONObject publicRow(JSONObject row){JSONObject out=copy(row);out.remove("credentials");out.remove("requestId");out.remove("fingerprint");out.remove("correctionAudit");return out;}
    private static AdminQueryService.QueryFailed fail(int status,String code,String text){return AdminQueryService.fail(status,code,text);}
}
