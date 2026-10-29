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
    @org.springframework.beans.factory.annotation.Autowired(required=false) private GuardianBusinessCommands businessCommands;
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
    @PutMapping("/snapshot") public JSONObject replace(@RequestBody JSONObject next,@RequestHeader("X-Wearable-Revision") int revision,HttpServletRequest r){access.context(WearableSessions.actor(r));throw AdminQueryService.fail(410,"SNAPSHOT_WRITE_REMOVED","整份快照写入已停用，请更新客户端并使用业务命令接口");}
    @PostMapping("/business/commands") public JSONObject business(@RequestBody JSONObject body,HttpServletRequest r){return businessCommands.execute(WearableSessions.actor(r),body);}
    @GetMapping("/events") public JSONObject list(HttpServletRequest r,@RequestParam(required=false) String siteId,@RequestParam(required=false) String status,@RequestParam(required=false) String type,@RequestParam(defaultValue="1") int pageNum,@RequestParam(defaultValue="20") int pageSize){return events.list(WearableSessions.actor(r),siteId,status,type,pageNum,pageSize);}
    @GetMapping("/events/{id}") public JSONObject event(@PathVariable String id,HttpServletRequest r){return events.detail(WearableSessions.actor(r),id);}
    @PostMapping("/events/{id}/{action}") public JSONObject command(@PathVariable String id,@PathVariable String action,@RequestBody JSONObject input,HttpServletRequest r){return events.command(WearableSessions.actor(r),id,action,input);}
    @PostMapping("/sos") public JSONObject sos(@RequestBody JSONObject input,HttpServletRequest r){return events.createSos(WearableSessions.actor(r),input);}
    @PutMapping("/files/{id}") public JSONObject upload(@PathVariable String id,HttpServletRequest r)throws IOException{events.upload(WearableSessions.actor(r),id,r.getContentType(),r.getInputStream());return object("ok",true,"id",id);}
    @GetMapping("/files/{id}") public ResponseEntity<byte[]> file(@PathVariable String id,HttpServletRequest r){GuardianFiles.Stored f=events.file(WearableSessions.actor(r),id);return f==null?ResponseEntity.notFound().build():ResponseEntity.ok().contentType(MediaType.parseMediaType(f.type)).body(f.bytes);}
    @PostMapping("/broadcast") public JSONObject broadcast(@RequestBody JSONObject body,HttpServletRequest r){
        access.context(WearableSessions.actor(r));throw AdminQueryService.fail(410,"PERSON_CONTEXT_REQUIRED","请更新客户端并使用人员通讯接口");
    }
    @PostMapping("/call") public Map<String,Object> call(@RequestBody JSONObject body,HttpServletRequest r){
        access.context(WearableSessions.actor(r));throw AdminQueryService.fail(410,"PERSON_CONTEXT_REQUIRED","请更新客户端并使用人员通讯接口");
    }
    @PostMapping("/call/end") public JSONObject end(@RequestBody JSONObject body,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));String channel=body.getString("channel");JSONObject records=store.snapshot().getJSONObject("voiceSessions"),record=records==null?null:records.getJSONObject(channel);
        if(record==null||!ctx.id().equals(record.getString("ownerId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","不能结束其他账号的设备通话");
        // Ownership above and the captured authorized site remain mandatory after a return or disconnect.
        JSONArray captured=record.getJSONArray("hats");if(captured==null||captured.isEmpty())throw AdminQueryService.fail(403,"PERMISSION_DENIED","通话缺少原授权范围");
        for(Object raw:captured){JSONObject hat=(JSONObject)raw;String site=hat.getString("siteId");if(site==null||!ctx.can("communications:voice",site,hat.getString("areaId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","通话不在原授权范围");}
        voice.end(channel);return object("ok",true);
    }
}
