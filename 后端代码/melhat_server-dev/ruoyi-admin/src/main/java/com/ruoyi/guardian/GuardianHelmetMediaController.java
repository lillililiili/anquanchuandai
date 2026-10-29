package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.alibaba.fastjson2.JSONArray;
import com.ruoyi.melhat.direct.HelmetMediaService;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

@RestController
@RequestMapping("/api/guardian/v1")
public class GuardianHelmetMediaController {
    private final GuardianAccess access;
    private final HelmetMediaService media;
    @org.springframework.beans.factory.annotation.Autowired private PersonEquipmentContext equipment;
    public GuardianHelmetMediaController(GuardianAccess access,HelmetMediaService media){this.access=access;this.media=media;}
    @ModelAttribute public void privateResponses(HttpServletResponse response){
        response.setHeader("Cache-Control","no-store, private");response.setHeader("Pragma","no-cache");
    }
    @GetMapping("/helmet/media") public JSONObject allMedia(@RequestParam(required=false)String deviceId,@RequestParam(required=false)String personId,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONArray items=new JSONArray();
        if(deviceId!=null){historicalDevice(ctx,deviceId);items.addAll(media.assets(deviceId));}
        else for(Object raw:rows(ctx.data,"devices")){JSONObject d=(JSONObject)raw;
            if("DIRECT_HELMET".equals(d.getString("source")))items.addAll(media.assets(d.getString("portalDeviceId")));}
        JSONArray visible=historical(ctx,items);if(personId!=null)visible.removeIf(raw->!personId.equals(((JSONObject)raw).getString("personId")));
        return object("items",visible);
    }
    @GetMapping("/devices/{id}/media") public JSONObject media(@PathVariable String id,HttpServletRequest request){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(request));JSONObject device=historicalDevice(ctx,id), result=media.media(id);
        result.remove("live");result.put("actions",new JSONArray());result.remove("capabilities");
        result.put("items",historical(ctx,result.getJSONArray("items")));
        JSONArray commands=historical(ctx,result.getJSONArray("commands"));result.put("commands",commands);
        // A cached file list belongs to the query's original scope, not the device's current scope.
        JSONArray recordings=new JSONArray();
        for(Object raw:commands){JSONObject command=(JSONObject)raw;if("list_recordings".equals(command.getString("action"))&&command.getJSONArray("result")!=null){
            for(Object item:command.getJSONArray("result")){JSONObject file=item instanceof JSONObject?(JSONObject)item:object("fileName",String.valueOf(item));
                String name=text(file,"fileName");if(name.isEmpty())name=text(file,"file_name");if(name.isEmpty())name=text(file,"name");
                if(!name.isEmpty())recordings.add(object("fileName",name,"name",name,"createdAt",file.get("createdAt")));}break;}}
        result.put("recordings",recordings);
        if(!ctx.can("assets:read",device.getString("siteId"),null)&&commands.isEmpty()&&result.getJSONArray("items").isEmpty())throw AdminQueryService.fail(403,"PERMISSION_DENIED","没有可查看的媒体历史");
        return result;
    }
    @GetMapping("/devices/{id}/live") public JSONObject live(@PathVariable String id,@RequestParam String personId,@RequestParam String assignmentId,
            @RequestParam int assignmentVersion,@RequestParam String viewerSessionId,@RequestParam(defaultValue="false")boolean acceptanceTest,HttpServletRequest request){
        JSONObject input=object("personId",personId,"assignmentId",assignmentId,"assignmentVersion",assignmentVersion,"viewerSessionId",viewerSessionId,"acceptanceTest",acceptanceTest);
        return equipment.execute(WearableSessions.actor(request),ctx->{equipment.require(ctx,id,input,"video","communications:voice");return media.live(ctx.id(),id,input);});
    }
    @PostMapping("/devices/{id}/commands") public JSONObject command(@PathVariable String id,@RequestBody JSONObject input,HttpServletRequest request){
        return equipment.execute(WearableSessions.actor(request),ctx->{String action=text(input,"action");
        if(Arrays.asList("stop_video","stop_recording").contains(action)) {
            JSONObject captured=media.requireCleanup(ctx.id(),id,input);
            if(!ctx.can("communications:voice",captured.getString("siteId"),null))throw AdminQueryService.fail(403,"PERMISSION_DENIED","无权结束此媒体会话");
            JSONObject authority=copy(input);for(String key:Arrays.asList("siteId","areaId","personId","assignmentId","assignmentVersion"))authority.put(key,captured.get(key));
            return media.command(ctx.id(),id,authority);
        }
        String op=Arrays.asList("set_config","configure_sip").contains(action)?"assets:write":"broadcast".equals(action)?"communications:broadcast":"communications:voice";
        boolean setup=Arrays.asList("set_config","configure_sip").contains(action);
        if(setup&&!("demo-system".equals(ctx.id())&&input.getBooleanValue("acceptanceTest")))throw AdminQueryService.fail(403,"ACCEPTANCE_REQUIRED","设备配置仅供系统管理员显式联调使用");
        String feature=setup?null:"take_photo".equals(action)?"photo":"broadcast".equals(action)?"broadcast":"start_video".equals(action)?"video":"recording";
        device(ctx,id,op);JSONObject target=equipment.require(ctx,id,input,feature,op);JSONObject authority=copy(input);authority.putAll(target);
        return media.command(ctx.id(),id,authority);});
    }
    @GetMapping("/helmet/calls/{id}") public JSONObject call(@PathVariable String id,HttpServletRequest r){
        owned(id,r);JSONObject state=media.callState(id);state.put("serverConnected","connected".equals(state.getString("status")));return state;
    }
    @GetMapping("/helmet/calls/{id}/credentials") public JSONObject credentials(@PathVariable String id,HttpServletRequest r){
        owned(id,r);throw AdminQueryService.fail(410,"PERSON_CONTEXT_REQUIRED","请使用人员通讯会话的凭据接口");
    }
    private GuardianAccess.Context owned(String id,HttpServletRequest r){
        GuardianAccess.Context ctx=access.context(WearableSessions.actor(r));JSONObject row=media.callState(id);
        if(row==null||!ctx.id().equals(row.getString("actorId")))throw AdminQueryService.fail(404,"CALL_NOT_FOUND","通话不存在或不属于当前账号");
        for(Object device:row.getJSONArray("deviceIds"))device(ctx,String.valueOf(device),"communications:voice");return ctx;
    }
    static JSONArray historical(GuardianAccess.Context ctx,JSONArray rows){
        JSONArray result=new JSONArray();if(rows==null)return result;
        for(Object raw:rows){JSONObject row=(JSONObject)raw;String site=text(row,"siteId");
            if(site.isEmpty()){
                if("demo-system".equals(ctx.id())){JSONObject item=copy(row);item.put("unassigned",true);result.add(item);}
            }else if(ctx.can("assets:read",site,row.getString("areaId")))result.add(copy(row));
        }return result;
    }
    private JSONObject device(GuardianAccess.Context ctx,String id,String permission){
        for(Object raw:rows(ctx.data,"devices")){JSONObject d=(JSONObject)raw;if(Objects.equals(id,d.getString("portalDeviceId"))){
            if(!ctx.can(permission,d.getString("siteId"),d.getString("areaId")))throw AdminQueryService.fail(403,"PERMISSION_DENIED","设备不在授权范围");
            if(!"DIRECT_HELMET".equals(d.getString("source"))||!"HELMET".equals(d.getString("type"))||Arrays.asList("DISABLED","SCRAPPED").contains(d.getString("lifecycle")))throw AdminQueryService.fail(409,"DEVICE_UNAVAILABLE","设备未启用直连安全帽能力");return d;}}
        throw AdminQueryService.fail(404,"DEVICE_NOT_FOUND","设备不存在或不在授权范围");
    }
    private JSONObject historicalDevice(GuardianAccess.Context ctx,String id){for(Object raw:rows(ctx.data,"devices")){JSONObject d=(JSONObject)raw;if(Objects.equals(id,d.getString("portalDeviceId"))&&"DIRECT_HELMET".equals(d.getString("source")))return d;}throw AdminQueryService.fail(404,"DEVICE_NOT_FOUND","设备不存在");}
}
