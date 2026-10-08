package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.time.*;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** The single write path for PC and mobile event/assistance workflows. */
@Service
public class GuardianEvents {
    private final GuardianStore store;
    private final GuardianAccess access;
    private final GuardianFiles files;
    public GuardianEvents(GuardianStore store,GuardianAccess access,GuardianFiles files) { this.store=store;this.access=access;this.files=files; }

    static boolean normalize(JSONObject state) {
        String before=state.toJSONString();
        JSONObject assistance=state.getJSONObject("assistance");
        if(assistance==null) { assistance=new JSONObject();state.put("assistance",assistance); }
        for(Object raw:rows(state,"events")) { JSONObject event=(JSONObject)raw;
            if(!event.containsKey("version")) event.put("version",1);
            if(!event.containsKey("source")) event.put("source","device");
            rows(event,"observations");
            if("人员求助".equals(event.getString("type")) && !assistance.containsKey(event.getString("id"))) {
                JSONObject old=state.getJSONObject("sos");
                JSONObject a=old!=null && event.getString("id").equals(old.getString("eventId")) ? copy(old) : object("eventId",event.getString("id"),"status","waiting","members",new JSONArray(),"timeline",new JSONArray());
                a.put("eventId",event.getString("id"));assistance.put(event.getString("id"),a);
            }
        }
        return !before.equals(state.toJSONString());
    }
    public JSONObject snapshot(JSONObject actor) { return access.context(actor).snapshot(store.snapshot()); }
    public JSONObject detail(JSONObject actor,String id) {
        GuardianAccess.Context ctx=access.context(actor);JSONObject state=store.snapshot();JSONObject event=find(state,"events",id);ctx.requireEvent(event,null);
        return present(state,event,ctx);
    }
    public JSONObject list(JSONObject actor,String site,String status,String type,int page,int size) {
        if(page<1||size<1||size>100) throw fail(400,"INVALID_PAGE","分页参数无效");
        GuardianAccess.Context ctx=access.context(actor);JSONObject state=store.snapshot();List<JSONObject> result=new ArrayList<>();
        if(site!=null&&!site.isEmpty()&&!ctx.site(siteId(ctx.data,site))) throw fail(403,"PERMISSION_DENIED","厂站不在授权范围");
        for(Object raw:rows(state,"events")) {JSONObject e=(JSONObject)raw;
            if(!ctx.event(e) || site!=null&&!site.isEmpty()&&!site.equals(e.getString("station"))&&!site.equals(ctx.eventSite(e))) continue;
            if(status!=null&&!status.isEmpty()&&!status.equals(e.getString("status"))) continue;
            if(type!=null&&!type.isEmpty()&&!type.equals(e.getString("type"))) continue;
            result.add(present(state,e,ctx)); }
        result.sort(Comparator.comparingInt((JSONObject e)->"人员求助".equals(e.getString("type"))&&!"已核验".equals(e.getString("status"))?0:1).thenComparing(e->e.getString("date")+e.getString("time"),Comparator.reverseOrder()));
        long from=(long)(page-1)*size;
        return object("rows",from>=result.size()?Collections.emptyList():result.subList((int)from,Math.min((int)from+size,result.size())),"total",result.size(),"pageNum",page,"pageSize",size);
    }
    public JSONObject createSos(JSONObject actor,JSONObject input) {
        GuardianAccess.Context ctx=access.context(actor);
        String site=siteId(ctx.data,input.getString("siteId"));
        if(ctx.person==null || !Objects.equals(site,ctx.person.getString("siteId")) || !ctx.can("sos:create",site,ctx.person.getString("areaId")))
            throw fail(403,"PERMISSION_DENIED","此账号未关联授权人员或没有手机求助权限");
        String key=operation(ctx,"sos.create",input); final JSONObject[] result={null};
        store.update(state->{
            JSONObject prior=replay(state,key,input); if(prior!=null) { ctx.requireEvent(prior,null);result[0]=present(state,prior,ctx);return false; }
            String description=bounded(input,"description",500,false), location=bounded(input,"locationDescription",200,false);
            String id="SOS-"+UUID.randomUUID();LocalDateTime now=LocalDateTime.now(ZoneId.of("Asia/Shanghai"));
            JSONObject event=object("id",id,"personId",ctx.personId(),"deviceId","","workId","","siteId",site,"areaId",ctx.person.getString("areaId"),"station",find(ctx.data,"sites",site).getString("portalStation"),"title","手机发起 SOS","type","人员求助","status","待认领","source","manual_sos","description",description,"locationDescription",location,"date",now.toLocalDate().toString(),"time",now.toLocalTime().withNano(0).toString(),"createdAt",Instant.now().toString(),"createdBy",ctx.id(),"version",1,"externalId","","externalStatus","未接入外部系统","snapshot",object("personName",ctx.person.getString("name"),"deviceId","","workName","未关联作业"),"observations",new JSONArray(),"timeline",new JSONArray());
            rows(state,"events").add(0,event);normalize(state);line(event,ctx,"手机发起求助");
            remember(state,key,input,id);bump(state);result[0]=present(state,event,ctx);return true;
        });
        return result[0];
    }
    public JSONObject command(JSONObject actor,String id,String action,JSONObject input) {
        GuardianAccess.Context ctx=access.context(actor); String op=permission(action),key=operation(ctx,id+":"+action,input);final JSONObject[] result={null};
        store.update(state->{
            JSONObject event=find(state,"events",id);ctx.requireEvent(event,op);
            JSONObject previous=replay(state,key,input);if(previous!=null) {result[0]=present(state,event,ctx);return false;}
            if(event.getJSONObject("verification")!=null||"已核验".equals(event.getString("status"))) throw fail(409,"EVENT_READ_ONLY","已核验记录只读");
            if(!input.containsKey("expectedVersion")||input.getIntValue("expectedVersion")!=event.getIntValue("version")) throw fail(409,"VERSION_CONFLICT","事件已被其他终端更新，请刷新后重试");
            if("claim".equals(action)) {
                if(!Arrays.asList("待认领","待现场核验").contains(event.getString("status"))) throw fail(409,"ALREADY_CLAIMED","事件已被认领");
                event.put("status","处理中");event.put("claimedBy",ctx.id());event.put("claimedByName",ctx.name());line(event,ctx,"认领事件");
                if("人员求助".equals(event.getString("type"))) {JSONObject a=assistance(state,id);if("waiting".equals(a.getString("status"))) a.put("status","accepted");assistLine(a,ctx,"接警");}
            } else if("observations".equals(action)) {
                String situation=bounded(input,"situation",500,true);JSONArray photos=attach(state,event,ctx,input.getJSONArray("photoIds"),"observation");
                JSONObject row=object("id","OBS-"+UUID.randomUUID(),"situation",situation,"photoIds",photos,"actorId",ctx.id(),"actorName",ctx.name(),"createdAt",Instant.now().toString());
                rows(event,"observations").add(row);line(event,ctx,"补充现场情况");
                if("人员求助".equals(event.getString("type"))) assistLine(assistance(state,id),ctx,"补充现场情况");
            } else if("verification-draft".equals(action)||"verification".equals(action)) {
                boolean submit="verification".equals(action);String conclusion=bounded(input,"conclusion",100,submit);
                if(!conclusion.isEmpty()&&!Arrays.asList("设备通信异常","需现场处理","暂无法确认").contains(conclusion)) throw fail(400,"INVALID_CONCLUSION","核验结论无效");
                String situation=bounded(input,"situation",500,submit),measures=bounded(input,"measures",500,false);
                JSONArray photos=input.containsKey("photoIds")?attach(state,event,ctx,input.getJSONArray("photoIds"),"verification"):verificationPhotos(state,id);
                JSONObject form=object("conclusion",conclusion,"situation",situation,"measures",measures,"photoIds",photos,"actorId",ctx.id(),"actorName",ctx.name(),"submittedAt",Instant.now().toString());
                if(submit) {event.put("verification",form);event.put("draft",null);event.put("status","已核验");} else event.put("draft",form);
                line(event,ctx,submit?"提交最终核验 · "+conclusion:"保存核验草稿");
            } else if("photos".equals(action)) {
                JSONArray ids=new JSONArray();ids.add(input.getString("blobId"));attach(state,event,ctx,ids,"verification");line(event,ctx,"添加核验照片");
            } else {
                if(!"人员求助".equals(event.getString("type"))) throw fail(400,"NOT_SOS","此事件不是人员求助");
                JSONObject a=assistance(state,id);
                if("ended".equals(a.getString("status"))) throw fail(409,"ASSISTANCE_ENDED","此事件的协助已结束");
                if("assist-join".equals(action)) {
                    if(has(a.getJSONArray("members"),ctx.id())) throw fail(409,"ALREADY_JOINED","已加入此事件协助");
                    rows(a,"members").add(ctx.id());a.put("status","active");assistLine(a,ctx,"加入协助");line(event,ctx,"加入协助");
                } else {
                    a.put("status","ended");a.put("endedAt",Instant.now().toString());assistLine(a,ctx,"结束协助（核验独立办理）");line(event,ctx,"结束协助，尚需单独核验");
                }
            }
            event.put("version",event.getIntValue("version")+1);event.put("updatedAt",Instant.now().toString());remember(state,key,input,id);bump(state);result[0]=present(state,event,ctx);return true;
        });return result[0];
    }
    public void upload(JSONObject actor,String id,String contentType,java.io.InputStream bytes) {
        GuardianAccess.Context ctx=access.context(actor);
        // Serialize ownership registration and file creation with event writes; IDs are immutable after first save.
        store.update(state->{
            JSONObject uploads=state.getJSONObject("uploads");if(uploads==null){uploads=new JSONObject();state.put("uploads",uploads);}
            if(uploads.containsKey(id)||files.read(id)!=null) throw fail(409,"FILE_EXISTS","照片编号已使用，请使用新编号");
            boolean allowed=false;for(Object raw:rows(ctx.data,"sites")){JSONObject s=(JSONObject)raw;String area=ctx.person==null?null:ctx.person.getString("areaId");if(ctx.anyArea("events:observe",s.getString("id"))||ctx.anyArea("events:verify",s.getString("id"))) allowed=true;}
            if(!allowed) throw fail(403,"PERMISSION_DENIED","没有照片上传权限");
            files.save(id,contentType,bytes);uploads.put(id,object("ownerId",ctx.id(),"createdAt",Instant.now().toString()));bump(state);return true;
        });
    }
    public GuardianFiles.Stored file(JSONObject actor,String id) {
        GuardianAccess.Context ctx=access.context(actor);JSONObject state=store.snapshot();
        JSONObject uploads=state.getJSONObject("uploads"), upload=uploads==null?null:uploads.getJSONObject(id);
        if(upload!=null && upload.getString("eventId")==null && ctx.id().equals(upload.getString("ownerId"))) return files.read(id);
        for(Object raw:rows(ctx.snapshot(state),"media")) if(id.equals(((JSONObject)raw).getString("blobId"))) return files.read(id);
        throw fail(404,"FILE_NOT_FOUND","照片不存在或不在授权范围");
    }
    private JSONArray attach(JSONObject state,JSONObject event,GuardianAccess.Context ctx,JSONArray ids,String purpose) {
        JSONArray result=new JSONArray();if(ids==null)return result;if(ids.size()>20) throw fail(400,"TOO_MANY_PHOTOS","一次最多20张照片");
        for(Object raw:ids) {String id=String.valueOf(raw);if(result.contains(id))continue;
            JSONObject uploads=state.getJSONObject("uploads"),u=uploads==null?null:uploads.getJSONObject(id);
            JSONObject existing=null;for(Object m:rows(state,"media"))if(id.equals(((JSONObject)m).getString("blobId")))existing=(JSONObject)m;
            if(existing!=null) {
                if(!event.getString("id").equals(existing.getString("eventId")) || !purpose.equals(existing.getString("purpose"))) throw fail(403,"PHOTO_SCOPE","照片不属于此事件和记录类型");
            } else {
                if(u==null||!ctx.id().equals(u.getString("ownerId"))||u.getString("eventId")!=null||files.read(id)==null) throw fail(403,"PHOTO_SCOPE","照片未上传或不属于当前账号");
                u.put("eventId",event.getString("id"));
                rows(state,"media").add(object("id",id,"blobId",id,"eventId",event.getString("id"),"personId",event.getString("personId"),"deviceId",event.getString("deviceId"),"workId",event.getString("workId"),"station",event.getString("station"),"snapshot",copy(event.getJSONObject("snapshot")),"kind","photo","title","现场照片","source","verification".equals(purpose)?"核验上传":"现场补充","purpose",purpose,"created",Instant.now().toString(),"actorId",ctx.id(),"actorName",ctx.name()));
            }
            result.add(id);
        }return result;
    }
    private JSONArray verificationPhotos(JSONObject state,String id) {JSONArray ids=new JSONArray();for(Object raw:rows(state,"media")){JSONObject m=(JSONObject)raw;if(id.equals(m.getString("eventId"))&&"核验上传".equals(m.getString("source")))ids.add(m.getString("blobId"));}return ids;}
    private static JSONObject assistance(JSONObject state,String id) {normalize(state);return state.getJSONObject("assistance").getJSONObject(id);}
    private JSONObject present(JSONObject state,JSONObject event,GuardianAccess.Context ctx) {
        JSONObject out=copy(event);out.put("permissions",ctx.permissions(event));
        if("人员求助".equals(event.getString("type"))) out.put("assistance",copy(assistance(state,event.getString("id"))));return out;
    }
    private static String permission(String action) {
        switch(action){case "claim":return "events:claim";case "observations":return "events:observe";case "verification-draft":case "verification":case "photos":return "events:verify";case "assist-join":case "assist-end":return "sos:assist";default:throw fail(404,"UNKNOWN_ACTION","未开放此操作");}
    }
    private static void line(JSONObject event,GuardianAccess.Context ctx,String text){rows(event,"timeline").add(object("time",Instant.now().toString(),"text",text,"actorId",ctx.id(),"actorName",ctx.name()));}
    private static void assistLine(JSONObject a,GuardianAccess.Context ctx,String text){rows(a,"timeline").add(object("time",Instant.now().toString(),"text",text,"actorId",ctx.id(),"actorName",ctx.name()));}
    private static String bounded(JSONObject body,String key,int max,boolean required){String s=text(body,key);if(s.length()>max || required&&s.isEmpty())throw fail(400,"VALIDATION_ERROR",key+" 内容为空或超过长度限制");return s;}
    private static String operation(GuardianAccess.Context ctx,String action,JSONObject body){String id=text(body,"requestId");if(!id.matches("[A-Za-z0-9_-]{8,100}"))throw fail(400,"REQUEST_ID_REQUIRED","请提供稳定的请求编号用于防止重复提交");return ctx.id()+":"+action+":"+id;}
    private static JSONObject replay(JSONObject state,String key,JSONObject input) {
        JSONObject memory=state.getJSONObject("eventOperations"),row=memory==null?null:memory.getJSONObject(key);if(row==null)return null;
        if(!org.apache.commons.codec.digest.DigestUtils.sha256Hex(input.toJSONString()).equals(row.getString("hash")))throw fail(409,"IDEMPOTENCY_CONFLICT","相同请求编号不能用于不同内容");
        return find(state,"events",row.getString("eventId"));
    }
    private static void remember(JSONObject state,String key,JSONObject input,String eventId){JSONObject memory=state.getJSONObject("eventOperations");if(memory==null){memory=new JSONObject();state.put("eventOperations",memory);}memory.put(key,object("hash",org.apache.commons.codec.digest.DigestUtils.sha256Hex(input.toJSONString()),"eventId",eventId));}
    private static void bump(JSONObject state){state.put("seq",state.getIntValue("seq")+1);}
    private static AdminQueryService.QueryFailed fail(int code,String key,String message){return AdminQueryService.fail(code,key,message);}
}
