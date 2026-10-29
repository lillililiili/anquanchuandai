package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.util.*;
import java.util.function.Function;
import java.util.function.BiPredicate;
import java.util.function.Consumer;
import static com.ruoyi.guardian.WearableModel.*;

/** Current assignments are the authority for person-initiated device operations. */
@Service
public class PersonEquipmentContext {
    private final AdminLedgerStore ledger;
    private final GuardianAccess access;
    private final GuardianStore store;
    private final WearableBusinessPolicy policy;
    public PersonEquipmentContext(AdminLedgerStore ledger,GuardianAccess access,GuardianStore store,WearableBusinessPolicy policy) {
        this.ledger=ledger;this.access=access;this.store=store;this.policy=policy;
    }
    /** Uses the same monitor as the two assignment HTTP entry points. */
    public <T> T execute(JSONObject actor,Function<GuardianAccess.Context,T> operation) {
        synchronized(ledger){return operation.apply(access.context(actor));}
    }
    /** Ledger is always acquired before the media monitor; the predicate performs no I/O. */
    public void withSessionAuthority(Consumer<BiPredicate<String,JSONObject>> operation) {
        synchronized(ledger) {
            JSONObject data=ledger.read();
            operation.accept((actorId,captured)->sessionAuthorized(data,actorId,captured));
        }
    }
    private boolean sessionAuthorized(JSONObject data,String actorId,JSONObject captured) {
        try {
            GuardianAccess.Context ctx=access.new Context(data,actorId);
            JSONObject device=masterDevice(ctx,captured.getString("deviceId")),person=person(data,captured.getString("personId"));
            if(device==null||person==null||!Arrays.asList("DIRECT_HELMET","DIRECT_BELT").contains(device.getString("source")))return false;
            JSONObject assigned=assignment(ctx,device,person);
            return assigned!=null&&Objects.equals(captured.getString("siteId"),device.getString("siteId"))
                    &&Objects.equals(captured.getString("assignmentId"),assigned.getString("id"))
                    &&captured.containsKey("assignmentVersion")&&captured.getIntValue("assignmentVersion")==assigned.getIntValue("version")
                    &&ctx.can("communications:voice",captured.getString("siteId"),captured.getString("areaId"));
        }catch(AdminQueryService.QueryFailed error){return false;}
    }
    public void decorate(GuardianAccess.Context ctx,JSONObject state) {
        JSONObject contexts=new JSONObject();
        for(Object raw:rows(state,"people")) {
            JSONObject person=(JSONObject)raw, master=person(ctx.data,person.getString("id"));
            if(master==null)continue;
            JSONArray devices=new JSONArray();JSONObject features=new JSONObject();
            for(Object entry:rows(state,"devices")) {
                JSONObject observed=(JSONObject)entry,device=find(ctx.data,"devices",observed.getString("ledgerId"));
                if(device==null)device=masterDevice(ctx,observed.getString("id"));
                JSONObject assignment=device==null?null:assignment(ctx,device,master);
                if(assignment==null)continue;
                JSONObject target=target(device,master,assignment);target.put("source",device.get("source"));target.put("type",device.get("type"));
                target.put("online",observed.getBooleanValue("online"));target.put("name",device.get("name"));
                JSONObject states=policy.features(observed);target.put("featureStates",states);devices.add(target);
                for(String key:states.keySet()) {
                    JSONObject feature=copy(states.getJSONObject(key));feature.putAll(target(device,master,assignment));
                    String permission=permission(key);
                    if(permission!=null&&!ctx.can(permission,device.getString("siteId"),null)){feature.put("available",false);feature.put("reason","无操作权限");}
                    JSONObject previous=features.getJSONObject(key);
                    if(previous==null||rank(feature)>rank(previous))features.put(key,feature);
                }
            }
            JSONObject location=new JSONObject();
            for(String key:Arrays.asList("longitude","latitude","coordinateSystem","locationDeviceId","locationReportedAt","locationTimeBasis","locationAssignmentId","locationAssignmentVersion","locationFreshness","locationQuality","locationValid","locationSource","accuracyMeters","lastKnownLocation"))if(person.containsKey(key))location.put(key,person.get(key));
            contexts.put(person.getString("id"),object("personId",person.getString("id"),"devices",devices,"features",features,"location",location));
        }
        state.put("personEquipmentContext",contexts);
    }
    public JSONObject require(GuardianAccess.Context ctx,String deviceId,JSONObject input,String feature,String permission) {
        JSONObject device=masterDevice(ctx,deviceId);
        if(device==null)throw AdminQueryService.fail(404,"DEVICE_NOT_FOUND","设备不存在或不在授权范围");
        if(!ctx.can(permission,device.getString("siteId"),null))throw AdminQueryService.fail(403,"PERMISSION_DENIED","设备不在操作授权范围");
        if(!Arrays.asList("DIRECT_HELMET","DIRECT_BELT").contains(device.getString("source")))throw AdminQueryService.fail(409,"DEVICE_UNAVAILABLE","此设备没有真实设备操作能力");
        JSONObject person=person(ctx.data,text(input,"personId"));
        JSONObject assignment=person==null?null:assignment(ctx,device,person);
        if(assignment==null)throw AdminQueryService.fail(409,"ASSIGNMENT_REQUIRED","请先为人员领用此设备");
        if(!Objects.equals(person.getString("portalId"),input.getString("personId"))
                ||!Objects.equals(assignment.getString("id"),input.getString("assignmentId"))
                ||!input.containsKey("assignmentVersion")||assignment.getIntValue("version")!=input.getIntValue("assignmentVersion"))
            throw AdminQueryService.fail(409,"ASSIGNMENT_CHANGED","人员领用关系已变化，请刷新后重试");
        JSONObject observed=find(store.snapshot(),"devices",deviceId);
        if(observed==null)throw AdminQueryService.fail(409,"DEVICE_OFFLINE","设备离线，未下发操作");
        if(feature!=null)policy.require(observed,feature,input.getBooleanValue("acceptanceTest"),ctx);
        else if(!observed.getBooleanValue("online"))throw AdminQueryService.fail(409,"DEVICE_OFFLINE","设备离线，未下发操作");
        JSONObject result=target(device,person,assignment);result.put("siteId",device.get("siteId"));result.put("areaId",device.get("areaId"));result.put("name",person.get("name"));
        return result;
    }
    public static void sameContext(JSONObject captured,JSONObject input) {
        for(String key:Arrays.asList("personId","assignmentId","assignmentVersion"))
            if(!captured.containsKey(key)||!Objects.equals(String.valueOf(captured.get(key)),String.valueOf(input.get(key))))
                throw AdminQueryService.fail(409,"SESSION_CONTEXT_CHANGED","操作上下文与原会话不一致");
    }
    private static JSONObject masterDevice(GuardianAccess.Context ctx,String id) {
        for(Object raw:rows(ctx.data,"devices")){JSONObject d=(JSONObject)raw;if(Objects.equals(id,d.getString("portalDeviceId")))return d;}return null;
    }
    private static JSONObject assignment(GuardianAccess.Context ctx,JSONObject device,JSONObject person) {
        if(!person.getBooleanValue("enabled")||!"IN_USE".equals(device.getString("lifecycle"))||!Objects.equals(person.getString("siteId"),device.getString("siteId"))||!ctx.site(device.getString("siteId")))return null;
        JSONObject result=null;int count=0;
        for(Object raw:rows(ctx.data,"assignments")){JSONObject a=(JSONObject)raw;if(a.getBooleanValue("active")&&device.getString("id").equals(a.getString("deviceId"))){count++;result=a;}}
        return count==1&&person.getString("id").equals(result.getString("personId"))?result:null;
    }
    private static JSONObject target(JSONObject device,JSONObject person,JSONObject assignment){return object("personId",person.get("portalId"),"deviceId",device.get("portalDeviceId"),"ledgerDeviceId",device.get("id"),"assignmentId",assignment.get("id"),"assignmentVersion",assignment.get("version"));}
    private static int rank(JSONObject f){return (f.getBooleanValue("available")?8:0)+(f.getBooleanValue("verified")?4:0)+(f.getBooleanValue("supported")?2:0);}
    private static String permission(String key){return "broadcast".equals(key)?"communications:broadcast":Arrays.asList("voice","videoCall","video","photo","recording").contains(key)?"communications:voice":null;}
}
