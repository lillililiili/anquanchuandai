package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

@RestController
@RequestMapping("/api/guardian/v1")
public class GuardianController {
    private final WearableSessions sessions;
    private final WearableCredentials credentials;
    private final GuardianStore store;
    private final GuardianEvents events;
    private final GuardianAccess access;
    private final GuardianVoiceService voice;
    public GuardianController(WearableSessions sessions,WearableCredentials credentials,GuardianStore store,GuardianEvents events,GuardianAccess access,GuardianVoiceService voice) {
        this.sessions=sessions;this.credentials=credentials;this.store=store;this.events=events;this.access=access;this.voice=voice;
    }
    @PostMapping("/login") public JSONObject login(@RequestBody JSONObject body) {
        JSONObject actor=credentials.authenticate(body.getString("account"),body.getString("password"));
        GuardianAccess.Context ctx=access.context(actor);
        boolean duty=false;
        for(Object raw:rows(ctx.data,"sites")) {JSONObject site=(JSONObject)raw;
            if(ctx.can("events:read",site.getString("id"),null)) duty=true;
            for(Object p:rows(ctx.data,"people")) {JSONObject person=(JSONObject)p;if(site.getString("id").equals(person.getString("siteId"))&&ctx.can("events:read",site.getString("id"),person.getString("areaId"))) duty=true;}
        }
        if(!duty) throw AdminQueryService.fail(403,"PERMISSION_DENIED","此账号没有PC监护权限，请使用移动端本人业务");
        return object("ok",true,"operator",identity(ctx),"token",sessions.issue(actor,"guardian"));
    }
    @PostMapping("/logout") public JSONObject logout(HttpServletRequest r){sessions.revoke(r);return object("ok",true);}
    @GetMapping("/operator") public JSONObject operator(HttpServletRequest r){return identity(access.context(WearableSessions.actor(r)));}
    private JSONObject identity(GuardianAccess.Context ctx){JSONObject body=ctx.identity();body.put("roleName","授权值守人员");return body;}
    @GetMapping("/snapshot") public JSONObject snapshot(HttpServletRequest r){return object("state",events.snapshot(WearableSessions.actor(r)));}
    @PutMapping("/snapshot") public JSONObject replace(@RequestBody JSONObject next,@RequestHeader("X-Wearable-Revision") int revision,HttpServletRequest r){store.replaceScoped(next,revision,access.context(WearableSessions.actor(r)));return object("ok",true);}
    @GetMapping("/events") public JSONObject list(HttpServletRequest r,@RequestParam(required=false) String siteId,@RequestParam(required=false) String status,@RequestParam(required=false) String type,@RequestParam(defaultValue="1") int pageNum,@RequestParam(defaultValue="20") int pageSize){return events.list(WearableSessions.actor(r),siteId,status,type,pageNum,pageSize);}
    @GetMapping("/events/{id}") public JSONObject event(@PathVariable String id,HttpServletRequest r){return events.detail(WearableSessions.actor(r),id);}
    @PostMapping("/events/{id}/{action}") public JSONObject command(@PathVariable String id,@PathVariable String action,@RequestBody JSONObject input,HttpServletRequest r){return events.command(WearableSessions.actor(r),id,action,input);}
    @PostMapping("/sos") public JSONObject sos(@RequestBody JSONObject input,HttpServletRequest r){return events.createSos(WearableSessions.actor(r),input);}
    @PutMapping("/files/{id}") public JSONObject upload(@PathVariable String id,HttpServletRequest r)throws IOException{events.upload(WearableSessions.actor(r),id,r.getContentType(),r.getInputStream());return object("ok",true,"id",id);}
    @GetMapping("/files/{id}") public ResponseEntity<byte[]> file(@PathVariable String id,HttpServletRequest r){GuardianFiles.Stored f=events.file(WearableSessions.actor(r),id);return f==null?ResponseEntity.notFound().build():ResponseEntity.ok().contentType(MediaType.parseMediaType(f.type)).body(f.bytes);}
    @PostMapping("/broadcast") public JSONObject broadcast(@RequestBody JSONObject body,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONArray hats=authorizedHats(ctx,body,"communications:broadcast");
        voice.broadcast(hats,body.getString("content"),ctx.id(),ctx.name());return object("ok",true);
    }
    @PostMapping("/call") public Map<String,Object> call(@RequestBody JSONObject body,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONArray hats=authorizedHats(ctx,body,"communications:voice");Map<String,Object> result=voice.call(hats);
        store.update(state->{JSONObject records=state.getJSONObject("voiceSessions");if(records==null){records=new JSONObject();state.put("voiceSessions",records);}records.put(String.valueOf(result.get("channel")),object("ownerId",ctx.id(),"hats",hats,"createdAt",java.time.Instant.now().toString()));return true;});
        result.put("ok",true);return result;
    }
    @PostMapping("/call/end") public JSONObject end(@RequestBody JSONObject body,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));String channel=body.getString("channel");JSONObject records=store.snapshot().getJSONObject("voiceSessions"),record=records==null?null:records.getJSONObject(channel);
        if(record==null||!ctx.id().equals(record.getString("ownerId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","不能结束其他账号的设备通话");
        authorizedHats(ctx,object("hats",record.get("hats")),"communications:voice");voice.end(channel);return object("ok",true);
    }
    private JSONArray authorizedHats(GuardianAccess.Context ctx,JSONObject body,String permission){
        JSONArray requested=body.getJSONArray("hats"),result=new JSONArray();if(requested==null||requested.isEmpty()||requested.size()>50)throw new GuardianRejected("请选择1至50个安全帽");
        for(Object raw:requested){String number=((JSONObject)raw).getString("hatNumber");JSONObject device=null;
            for(Object d:rows(ctx.data,"devices"))if(Objects.equals(number,((JSONObject)d).getString("portalDeviceId")))device=(JSONObject)d;
            if(device==null||!"HELMET".equals(device.getString("type"))||!ctx.can(permission,device.getString("siteId"),device.getString("areaId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","设备不在通讯授权范围");
            String wearer="";for(Object rawAssignment:rows(ctx.data,"assignments")){JSONObject a=(JSONObject)rawAssignment;if(a.getBooleanValue("active")&&device.getString("id").equals(a.getString("deviceId"))){JSONObject p=find(ctx.data,"people",a.getString("personId"));if(p!=null)wearer=p.getString("name");}}
            result.add(object("hatNumber",number,"name",wearer));
        }return result;
    }
}
