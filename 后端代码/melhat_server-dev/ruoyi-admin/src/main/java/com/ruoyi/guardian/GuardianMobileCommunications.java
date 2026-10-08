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
    private final GuardianStore store;
    private final GuardianAccess access;
    private final GuardianVoiceService voice;
    public GuardianMobileCommunications(GuardianStore store,GuardianAccess access,GuardianVoiceService voice){this.store=store;this.access=access;this.voice=voice;}

    @PostMapping("/calls") public synchronized JSONObject start(@RequestBody JSONObject input,HttpServletRequest request){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));
        JSONObject device=device(ctx,input.getString("deviceId"),"communications:voice");
        event(ctx,input.getString("eventId"));
        if(input.getBooleanValue("video"))throw fail(400,"VOICE_ONLY","当前仅支持安全帽语音");
        JSONObject previous=previous(ctx,input,"call");if(previous!=null){own(ctx,previous);return offered(previous,true);}
        JSONObject row=base(ctx,input,"call");row.put("deviceId",device.getString("portalDeviceId"));row.put("siteId",device.getString("siteId"));row.put("areaId",device.get("areaId"));row.put("status","requesting");row.put("kind","single");row.put("video",false);row.put("demo",false);
        row.put("sn",device.getString("portalDeviceId"));row.put("personId",wearer(ctx,device));save(row);
        try {
            JSONArray hats=new JSONArray();hats.add(object("hatNumber",device.getString("portalDeviceId")));
            Map<String,Object> rtc=voice.call(hats);
            row.put("channelName",rtc.get("channel"));row.put("status","offered");row.put("expiresAt",Instant.now().plusSeconds(3600).toString());
            row.put("credentials",object("agoraAppId",rtc.get("appId"),"channelName",rtc.get("channel"),"agoraToken",rtc.get("token"),"agoraUid",rtc.get("uid"),"expiresAt",row.get("expiresAt"),"demo",false,"video",false));
            save(row);return offered(row,true);
        }catch(RuntimeException error){row.put("status","unknown");row.put("failReason","设备平台结果未确认，请核实设备状态，勿重复发起");save(row);throw fail(502,"PLATFORM_UNCONFIRMED",row.getString("failReason"));}
    }
    @GetMapping("/calls") public JSONArray calls(@RequestParam(required=false)String eventId,@RequestParam(required=false)String deviceId,HttpServletRequest request){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));JSONArray out=new JSONArray();
        for(Object raw:rows(store.snapshot(),"sharedCommunications")){JSONObject row=(JSONObject)raw;
            if("call".equals(row.getString("operationType"))&&visible(ctx,row)&& (eventId==null||eventId.equals(row.getString("eventId")))&&(deviceId==null||deviceId.equals(row.getString("deviceId"))))out.add(publicRow(row));}
        return out;
    }
    @GetMapping("/calls/{id}") public JSONObject details(@PathVariable String id,HttpServletRequest r){return publicRow(owned(id,r));}
    @GetMapping("/calls/{id}/credentials") public JSONObject credentials(@PathVariable String id,HttpServletRequest r){
        JSONObject row=owned(id,r);offered(row,false);return copy(row.getJSONObject("credentials"));
    }
    @PostMapping("/calls/{id}/joined") public synchronized JSONObject joined(@PathVariable String id,@RequestBody JSONObject body,HttpServletRequest r){
        JSONObject row=owned(id,r);offered(row,false);
        if(!Objects.equals(String.valueOf(row.getJSONObject("credentials").get("agoraUid")),body.getString("agoraUid")))throw fail(400,"UID_MISMATCH","通话身份不匹配");
        row.put("status","connected");row.put("connectedAt",Instant.now().toString());row.put("connectionQuality","local_joined");save(row);return publicRow(row);
    }
    @PostMapping("/calls/{id}/end") public synchronized JSONObject end(@PathVariable String id,HttpServletRequest r){
        JSONObject row=owned(id,r);if("ended".equals(row.getString("status")))return publicRow(row);
        if(text(row,"channelName").isEmpty())throw fail(409,"PLATFORM_UNCONFIRMED","未取得设备频道，无法确认挂断，请核实设备状态");
        voice.end(row.getString("channelName"));row.put("status","ended");row.put("endedAt",Instant.now().toString());row.remove("credentials");save(row);return publicRow(row);
    }
    @PostMapping("/broadcast") public synchronized JSONArray broadcast(@RequestBody JSONObject input,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONArray ids=input.getJSONArray("deviceIds");String text=text(input,"text");
        if(ids==null||ids.isEmpty()||ids.size()>50||text.isEmpty()||text.length()>200)throw fail(400,"INVALID_BROADCAST","请选择设备，广播内容为1至200字");
        JSONArray hats=new JSONArray(),recipients=new JSONArray();String site=null;
        for(Object id:ids){JSONObject d=device(ctx,String.valueOf(id),"communications:broadcast");if(site!=null&&!site.equals(d.getString("siteId")))throw fail(400,"SITE_MISMATCH","广播设备必须属于同一厂站");site=d.getString("siteId");hats.add(object("hatNumber",d.getString("portalDeviceId"),"name",personName(ctx,wearer(ctx,d))));recipients.add(object("deviceId",d.getString("portalDeviceId"),"areaId",d.get("areaId")));}
        event(ctx,input.getString("eventId"));JSONObject previous=previous(ctx,input,"broadcast");if(previous!=null){if(!"accepted".equals(previous.getString("status")))throw fail(409,"PLATFORM_UNCONFIRMED","上次广播结果未确认，不能自动重发");return broadcastResult(previous);}
        JSONObject row=base(ctx,input,"broadcast");row.put("deviceIds",ids);row.put("recipients",recipients);row.put("siteId",site);row.put("text",text);row.put("status","requesting");save(row);
        try{voice.broadcast(hats,text,ctx.id(),ctx.name());row.put("status","accepted");save(row);return broadcastResult(row);}
        catch(RuntimeException error){row.put("status","unknown");row.put("failReason","设备平台受理结果未确认，未报告播放成功");save(row);throw fail(502,"PLATFORM_UNCONFIRMED",row.getString("failReason"));}
    }
    private JSONArray broadcastResult(JSONObject row){JSONArray out=new JSONArray();for(Object id:row.getJSONArray("deviceIds"))out.add(object("id",row.getString("id")+":"+id,"deviceId",id,"status","accepted","vendorMsg","设备平台已受理，实际播放待设备确认"));return out;}
    private JSONObject owned(String id,HttpServletRequest r){GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONObject row=find(store.snapshot(),"sharedCommunications",id);own(ctx,row);device(ctx,row.getString("deviceId"),"communications:voice");return row;}
    private static void own(GuardianAccess.Context ctx,JSONObject row){if(row==null||!ctx.id().equals(row.getString("requesterUserId")))throw fail(404,"CALL_NOT_FOUND","通话不存在或不属于当前账号");}
    private JSONObject previous(GuardianAccess.Context ctx,JSONObject input,String type){
        String key=text(input,"idempotencyKey");if(!key.matches("[A-Za-z0-9_-]{8,100}"))throw fail(400,"REQUEST_ID_REQUIRED","请提供稳定的请求编号");
        String hash=org.apache.commons.codec.digest.DigestUtils.sha256Hex(input.toJSONString());
        for(Object raw:rows(store.snapshot(),"sharedCommunications")){JSONObject r=(JSONObject)raw;if(ctx.id().equals(r.getString("requesterUserId"))&&key.equals(r.getString("requestId"))&&type.equals(r.getString("operationType"))){if(!hash.equals(r.getString("fingerprint")))throw fail(409,"IDEMPOTENCY_CONFLICT","相同请求编号不能用于不同内容");return r;}}return null;
    }
    private JSONObject base(GuardianAccess.Context ctx,JSONObject input,String type){return object("id","COMM-"+UUID.randomUUID(),"operationType",type,"requesterUserId",ctx.id(),"actorName",ctx.name(),"eventId",input.get("eventId"),"requestId",input.get("idempotencyKey"),"fingerprint",org.apache.commons.codec.digest.DigestUtils.sha256Hex(input.toJSONString()),"startedAt",Instant.now().toString(),"version",1);}
    private void save(JSONObject row){store.update(state->{JSONArray list=rows(state,"sharedCommunications");JSONObject prior=find(state,"sharedCommunications",row.getString("id"));if(prior!=null)list.remove(prior);row.put("version",row.getIntValue("version")+1);list.add(0,copy(row));state.put("seq",state.getIntValue("seq")+1);return true;});}
    private JSONObject offered(JSONObject row,boolean credentials){
        if(!Arrays.asList("offered","connected").contains(row.getString("status")))throw fail(409,"CALL_UNAVAILABLE","通话结果未确认或已经结束，请刷新记录核实");
        if(row.getJSONObject("credentials")==null||!Instant.parse(row.getString("expiresAt")).isAfter(Instant.now()))throw fail(409,"CALL_EXPIRED","通话凭证已过期，请结束此会话");
        JSONObject out=publicRow(row);if(credentials)out.put("credentials",copy(row.getJSONObject("credentials")));return out;
    }
    private JSONObject device(GuardianAccess.Context ctx,String id,String operation){
        for(Object raw:rows(ctx.data,"devices")){JSONObject d=(JSONObject)raw;if(Objects.equals(id,d.getString("portalDeviceId"))){
            if(!ctx.can(operation,d.getString("siteId"),d.getString("areaId")))throw fail(403,"PERMISSION_DENIED","设备不在通讯授权范围");
            if(!"HELMET".equals(d.getString("type"))||!"PLATFORM".equals(d.getString("source"))||Arrays.asList("DISABLED","SCRAPPED").contains(d.getString("lifecycle")))throw fail(409,"DEVICE_UNAVAILABLE","此设备尚无可用的真实安全帽通讯能力");return d;}}
        throw fail(404,"DEVICE_NOT_FOUND","设备不存在或不在授权范围");
    }
    private void event(GuardianAccess.Context ctx,String id){if(id!=null&&!id.isEmpty())ctx.requireEvent(find(store.snapshot(),"events",id),null);}
    private static String wearer(GuardianAccess.Context ctx,JSONObject d){for(Object raw:rows(ctx.data,"assignments")){JSONObject a=(JSONObject)raw;if(a.getBooleanValue("active")&&d.getString("id").equals(a.getString("deviceId"))){JSONObject p=find(ctx.data,"people",a.getString("personId"));if(p!=null)return p.getString("portalId");}}return "";}
    private static String personName(GuardianAccess.Context ctx,String id){JSONObject p=person(ctx.data,id);return p==null?"未关联人员":p.getString("name");}
    static boolean visible(GuardianAccess.Context ctx,JSONObject row){
        if("call".equals(row.getString("operationType")))return ctx.can("communications:voice",row.getString("siteId"),row.getString("areaId"));
        for(Object raw:rows(row,"recipients"))if(!ctx.can("communications:broadcast",row.getString("siteId"),((JSONObject)raw).getString("areaId")))return false;return ctx.site(row.getString("siteId"));
    }
    static JSONObject publicRow(JSONObject row){JSONObject out=copy(row);out.remove("credentials");out.remove("requestId");out.remove("fingerprint");return out;}
    private static AdminQueryService.QueryFailed fail(int status,String code,String text){return AdminQueryService.fail(status,code,text);}
}
