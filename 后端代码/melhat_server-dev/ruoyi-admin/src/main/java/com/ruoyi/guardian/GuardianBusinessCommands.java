package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Narrow user-authored commands. Device observations and server outcomes are never client writable. */
@Service
public class GuardianBusinessCommands {
    private final GuardianStore store;private final GuardianAccess access;
    public GuardianBusinessCommands(GuardianStore store,GuardianAccess access){this.store=store;this.access=access;}
    public JSONObject execute(JSONObject actor,JSONObject command){
        GuardianAccess.Context ctx=access.context(actor);String type=text(command,"type"),operation=text(command,"operationId");
        if(!Arrays.asList("fences.save","fences.toggle","fences.archive","groups.save").contains(type))throw AdminQueryService.fail(400,"UNKNOWN_COMMAND","此业务须使用对应服务端接口，不能修改设备数据或执行结果");
        if(!operation.matches("[A-Za-z0-9_-]{8,100}"))throw AdminQueryService.fail(400,"OPERATION_REQUIRED","请提供稳定的操作编号");
        JSONObject payload=command.getJSONObject("payload");if(payload==null)throw AdminQueryService.fail(400,"INVALID_COMMAND","缺少操作内容");
        String key=ctx.id()+":"+operation,fingerprint=org.apache.commons.codec.digest.DigestUtils.sha256Hex(type+"\n"+payload.toJSONString());
        JSONObject[] result={null};
        store.update(state->{
            String collection=type.startsWith("fences.")?"fences":"groups",id=text(payload,"id");JSONObject prior=id.isEmpty()?null:find(state,collection,id);
            if(!id.isEmpty()&&prior==null)throw AdminQueryService.fail(404,"NOT_FOUND","记录不存在");
            JSONObject fields=type.equals("fences.save")?payload.getJSONObject("fields"):payload;
            if(fields==null)throw AdminQueryService.fail(400,"INVALID_COMMAND","缺少围栏内容");
            String station=prior==null?text(fields,"station"):text(prior,"station"),site=siteId(ctx.data,station);
            String permission="groups".equals(collection)?"groups:write":"assets:write";
            if(!ctx.can(permission,site,null))throw AdminQueryService.fail(403,"PERMISSION_DENIED","没有该厂区的业务维护权限");
            if(prior!=null&&fields.containsKey("station")&&!station.equals(fields.getString("station")))throw AdminQueryService.fail(400,"SITE_MISMATCH","不能通过此操作变更厂区");
            JSONObject memory=state.getJSONObject("businessOperations");if(memory==null){memory=new JSONObject();state.put("businessOperations",memory);}JSONObject previous=memory.getJSONObject(key);
            if(previous!=null){if(!fingerprint.equals(previous.getString("fingerprint")))throw AdminQueryService.fail(409,"IDEMPOTENCY_CONFLICT","相同操作编号不能用于不同内容");result[0]=previous.getJSONObject("result");return false;}
            if(!command.containsKey("expectedSeq")||command.getIntValue("expectedSeq")!=state.getIntValue("seq"))throw AdminQueryService.fail(409,"VERSION_CONFLICT","数据已变化，请刷新后重试");
            JSONObject row=prior==null?object("id",("fences".equals(collection)?"F-":"G-")+UUID.randomUUID(),"station",station,"source","PLATFORM","createdAt",java.time.Instant.now().toString()):prior;
            if(type.endsWith(".save")){
                String name=text(fields,"name");if(name.isEmpty()||name.length()>100)throw AdminQueryService.fail(400,"INVALID_NAME","名称为1至100字");row.put("name",name);
                JSONArray members=fields.getJSONArray("members");if(members==null)members=new JSONArray();Set<String> unique=new HashSet<>();
                for(Object raw:members){String personId=String.valueOf(raw);JSONObject p=find(state,"people",personId),master=WearableModel.person(ctx.data,personId);if(!unique.add(personId)||p==null||!p.getBooleanValue("active")||!station.equals(p.getString("station"))||!ctx.person(master))throw AdminQueryService.fail(400,"INVALID_MEMBER","成员必须属于当前厂区且在授权范围内");}
                row.put("members",members);
                if("fences".equals(collection)){
                    if(!Arrays.asList("GCJ02","WGS84").contains(fields.getString("coordinateSystem")))throw AdminQueryService.fail(400,"INVALID_COORDINATES","正式围栏必须使用真实地理坐标");
                    for(String field:Arrays.asList("points","coordinateSystem","enter","leave","enabled","description"))if(fields.containsKey(field))row.put(field,fields.get(field));
                    if(!row.containsKey("enabled"))row.put("enabled",false);row.put("archived",false);
                }
            }else if(type.equals("fences.toggle")){
                if(!(payload.get("enabled") instanceof Boolean))throw AdminQueryService.fail(400,"INVALID_COMMAND","启停状态必须为布尔值");
                if(row.getBooleanValue("archived"))throw AdminQueryService.fail(409,"ARCHIVED","围栏已归档");
                if(payload.getBooleanValue("enabled")&&!Arrays.asList("GCJ02","WGS84").contains(row.getString("coordinateSystem")))
                    throw AdminQueryService.fail(409,"FENCE_REDRAW_REQUIRED","旧示意坐标围栏须按真实地理坐标重绘后才能启用");
                row.put("enabled",payload.getBooleanValue("enabled"));
            }
            else {row.put("archived",true);row.put("enabled",false);}
            row.put("version",row.getIntValue("version")+1);row.put("updatedBy",ctx.id());row.put("updatedAt",java.time.Instant.now().toString());if(prior==null)rows(state,collection).add(row);
            result[0]=copy(row);memory.put(key,object("fingerprint",fingerprint,"result",result[0]));state.put("seq",state.getIntValue("seq")+1);
            rows(state,"audit").add(object("id","A-"+UUID.randomUUID(),"actorId",ctx.id(),"actorName",ctx.name(),"text",type,"objectId",row.get("id"),"time",row.get("updatedAt")));return true;
        });
        return object("ok",true,"result",result[0],"state",ctx.snapshot(store.snapshot()));
    }
}
