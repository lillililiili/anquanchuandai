package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Mobile reads are projections of PC data; event writes use GuardianController. */
@RestController
@RequestMapping("/api/guardian/v1/mobile")
public class GuardianMobileController {
    private final WearableCredentials credentials;
    private final WearableSessions sessions;
    private final GuardianAccess access;
    private final GuardianEvents events;
    private final AdminAssignmentService assignments;
    private final AdminLedgerStore ledger;
    public GuardianMobileController(WearableCredentials credentials,WearableSessions sessions,GuardianAccess access,GuardianEvents events,AdminAssignmentService assignments,AdminLedgerStore ledger) {
        this.credentials=credentials;this.sessions=sessions;this.access=access;this.events=events;this.assignments=assignments;this.ledger=ledger;
    }
    @PostMapping("/login") public JSONObject login(@RequestBody JSONObject body){
        JSONObject actor=credentials.authenticate(body.getString("account"),body.getString("password"));GuardianAccess.Context ctx=access.context(actor);
        JSONObject identity=ctx.identity();if(identity.getJSONArray("sites").isEmpty())throw AdminQueryService.fail(403,"NO_SITE","账号尚未分配厂站权限");
        boolean manager=false;for(Object s:identity.getJSONArray("sites")){String site=((JSONObject)s).getString("id");if(ctx.can("events:read",site,null)||ctx.can("assets:write",site,null))manager=true;for(Object p:rows(ctx.data,"people")){JSONObject person=(JSONObject)p;if(site.equals(person.getString("siteId"))&&(ctx.can("events:read",site,person.getString("areaId"))||ctx.can("assets:write",site,person.getString("areaId"))))manager=true;}}
        if(!manager&&ctx.person==null)throw AdminQueryService.fail(403,"PERSON_REQUIRED","普通用户须先由管理员关联人员");
        return object("token",sessions.issue(actor,"mobile"),"identity",identity,"expiresIn",28800);
    }
    @GetMapping("/identity") public JSONObject identity(HttpServletRequest r){return access.context(WearableSessions.actor(r)).identity();}
    @GetMapping("/sites") public JSONArray sites(HttpServletRequest r){return identity(r).getJSONArray("sites");}
    /** A scoped read model, including the versions needed by existing assignment commands. */
    @GetMapping("/context") public JSONObject context(@RequestParam String siteId,HttpServletRequest r){
        synchronized(ledger){
            GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));
            JSONObject state=siteSnapshot(r,siteId);
            for(Object raw:rows(state,"people")){
                JSONObject p=(JSONObject)raw, master=find(ctx.data,"people",p.getString("ledgerId"));
                if(master!=null){p.put("version",master.get("version"));p.put("code",master.get("code"));}
            }
            for(Object raw:rows(state,"devices")){
                JSONObject d=(JSONObject)raw, master=find(ctx.data,"devices",d.getString("ledgerId"));
                if(master!=null){d.put("version",master.get("version"));d.put("lifecycle",master.get("lifecycle"));d.put("source",master.get("source"));}
            }
            // Authorized work details may show participant names without granting personnel-profile access.
            for(Object raw:rows(state,"works")){
                JSONObject work=(JSONObject)raw,names=new JSONObject();
                Set<String> ids=new HashSet<>();if(work.getJSONArray("members")!=null)for(Object id:work.getJSONArray("members"))ids.add(String.valueOf(id));
                ids.add(work.getString("leader"));ids.add(work.getString("supervisor"));
                for(String id:ids){JSONObject person=WearableModel.person(ctx.data,id);if(person!=null)names.put(id,person.getString("name"));}
                work.put("participantNames",names);
            }
            JSONObject assignments=history(siteId,r);
            state.put("assignments",assignments.get("rows"));state.put("assignmentHistory",assignments.get("history"));
            return state;
        }
    }
    @GetMapping("/home") public JSONObject home(@RequestParam String siteId,HttpServletRequest r){
        JSONObject state=siteSnapshot(r,siteId);long pending=rows(state,"events").stream().filter(e->!"已核验".equals(((JSONObject)e).getString("status"))).count();
        return object("siteId",siteId,"counts",object("pendingEvents",pending,"works",rows(state,"works").size(),"devices",rows(state,"devices").size()),"works",state.get("works"),"events",state.get("events"),"devices",state.get("devices"),"bindings",state.get("bindings"),"identity",state.get("operator"));
    }
    @GetMapping("/{resource:people|devices|works}") public JSONObject list(@PathVariable String resource,@RequestParam String siteId,HttpServletRequest r){JSONObject state=siteSnapshot(r,siteId);JSONArray result=rows(state,resource);return object("rows",result,"total",result.size());}
    @GetMapping("/{resource:people|devices|works}/{id}") public JSONObject detail(@PathVariable String resource,@PathVariable String id,@RequestParam String siteId,HttpServletRequest r){JSONObject state=siteSnapshot(r,siteId),row=find(state,resource,id);if(row==null)throw AdminQueryService.fail(404,"NOT_FOUND","资料不存在或不在授权范围");return row;}
    @GetMapping("/assignments") public JSONObject history(@RequestParam String siteId,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));String site=WearableModel.siteId(ctx.data,siteId);if(!ctx.site(site))throw AdminQueryService.fail(403,"PERMISSION_DENIED","厂站不在授权范围");
        JSONArray result=new JSONArray();for(Object raw:rows(ctx.data,"assignments")){JSONObject row=(JSONObject)raw;JSONObject p=find(ctx.data,"people",row.getString("personId"));if(site.equals(row.getString("siteId"))&&p!=null&&(ctx.can("assets:read",site,p.getString("areaId"))||ctx.person!=null&&ctx.person.getString("id").equals(p.getString("id"))&&ctx.can("self:read",site,p.getString("areaId"))))result.add(copy(row));}
        JSONArray history=new JSONArray();for(Object raw:rows(ctx.data,"history")){JSONObject row=(JSONObject)raw,p=find(ctx.data,"people",row.getString("personId"));if(site.equals(row.getString("siteId"))&&p!=null&&(ctx.can("assets:read",site,p.getString("areaId"))||ctx.person!=null&&ctx.person.getString("id").equals(p.getString("id"))&&ctx.can("self:read",site,p.getString("areaId"))))history.add(copy(row));}
        return object("rows",result,"history",history);
    }
    @PostMapping("/assignments/{action:issue|return}") public JSONObject assignment(@PathVariable String action,@RequestBody JSONObject input,HttpServletRequest r){
        synchronized(ledger){
            GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));
            JSONObject person=find(ctx.data,"people",input.getString("personId"));String site=input.getString("siteId");
            if(person==null||!Objects.equals(site,person.getString("siteId"))||!ctx.can("assets:write",site,person.getString("areaId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","无权办理此人员装备");
            JSONArray items=input.getJSONArray("items");if(items==null||items.isEmpty()||items.size()>3)throw AdminQueryService.fail(400,"INVALID_ITEMS","请选择1至3件装备");
            for(int i=0;i<items.size();i++){JSONObject device=find(ctx.data,"devices",items.getJSONObject(i).getString("deviceId"));
                if(device==null||!Objects.equals(site,device.getString("siteId"))||!ctx.can("assets:write",site,device.getString("areaId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","无权办理此设备");
            }
            return assignments.execute(ctx.id(),"assignments."+action,input);
        }
    }

    private JSONObject siteSnapshot(HttpServletRequest r,String requested){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));String id=WearableModel.siteId(ctx.data,requested);if(!ctx.site(id))throw AdminQueryService.fail(403,"PERMISSION_DENIED","厂站不在授权范围");
        String station=find(ctx.data,"sites",id).getString("portalStation");JSONObject state=events.snapshot(WearableSessions.actor(r));
        for(String key:Arrays.asList("people","devices","works","events")){JSONArray list=new JSONArray();for(Object raw:rows(state,key))if(station.equals(((JSONObject)raw).getString("station")))list.add(raw);state.put(key,list);}
        return state;
    }
}
