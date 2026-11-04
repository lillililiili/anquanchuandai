package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.time.*;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;
import static com.ruoyi.guardian.AdminQueryService.fail;

@Service
public class AdminWorks {
    private final GuardianStore store;
    private final GuardianAccess access;
    private final WearableBusinessPolicy policy;
    private final AdminLedgerStore ledger;
    public AdminWorks(GuardianStore store,GuardianAccess access,WearableBusinessPolicy policy,AdminLedgerStore ledger) {
        this.store=store;this.access=access;this.policy=policy;this.ledger=ledger;
    }
    private GuardianAccess.Context admin(JSONObject actor) {
        GuardianAccess.Context ctx=access.context(actor);
        if(!"demo-system".equals(ctx.id()))throw fail(403,"PERMISSION_DENIED","仅系统管理员可维护作业登记");
        return ctx;
    }
    public JSONObject options(JSONObject actor,String siteId) {
        GuardianAccess.Context ctx=admin(actor);JSONArray sites=new JSONArray(),people=new JSONArray();
        for(Object raw:rows(ctx.data,"sites")){JSONObject site=(JSONObject)raw;if(ctx.site(site.getString("id")))sites.add(object("id",site.getString("id"),"name",site.getString("name")));}
        for(Object raw:rows(ctx.data,"people")){JSONObject person=(JSONObject)raw;
            if(!person.getBooleanValue("enabled")||!ctx.site(person.getString("siteId"))||siteId!=null&&!siteId.isEmpty()&&!siteId.equals(person.getString("siteId")))continue;
            String id=person.getString("portalId");if(id==null||id.isEmpty())continue;
            people.add(object("id",id,"name",person.getString("name"),"siteId",person.getString("siteId")));
        }
        return object("sites",sites,"people",people,"businessConfig",policy.config());
    }
    public JSONObject list(JSONObject actor,String siteId,String keyword,String date,String status,int pageNum,int pageSize) {
        admin(actor);if(pageNum<1||pageSize<1||pageSize>100)throw fail(400,"INVALID_PAGE","分页参数无效");
        if(date!=null&&!date.isEmpty())try{LocalDate.parse(date);}catch(RuntimeException e){throw fail(400,"INVALID_DATE","日期格式无效");}
        JSONObject state=store.snapshot();List<JSONObject> matching=new ArrayList<>();int activeCount=0;
        for(Object raw:rows(state,"works")){JSONObject work=(JSONObject)raw;if(!store.isOperational(work))continue;
            if(WorkBusiness.running(work))activeCount++;
            if(siteId!=null&&!siteId.isEmpty()&&!siteId.equals(workSite(state,work)))continue;
            if(keyword!=null&&!keyword.isEmpty()&&!(text(work,"name")+" "+text(work,"id")).toLowerCase().contains(keyword.trim().toLowerCase()))continue;
            if(status!=null&&!status.isEmpty()&&!status.equals(WorkBusiness.status(work)))continue;
            if(date!=null&&!date.isEmpty()) {Instant from=WorkBusiness.start(work),to=WorkBusiness.end(work),day=LocalDate.parse(date).atStartOfDay(WorkBusiness.ZONE).toInstant();
                if(from==null||to==null||!from.isBefore(day.plusSeconds(86400))||!to.isAfter(day))continue;}
            matching.add(WorkBusiness.present(work));
        }
        matching.sort(Comparator.comparing((JSONObject w)->text(w,"createdAt")).reversed().thenComparing(w->text(w,"id")));
        long start=(long)(pageNum-1)*pageSize;
        return object("rows",start>=matching.size()?Collections.emptyList():matching.subList((int)start,Math.min((int)start+pageSize,matching.size())),"total",matching.size(),"pageNum",pageNum,"pageSize",pageSize,"activeCount",activeCount,"businessConfig",policy.config());
    }
    private String workSite(JSONObject state,JSONObject work) {
        if(work.getString("siteId")!=null)return work.getString("siteId");
        JSONObject data=ledger.read();return siteId(data,work.getString("station"));
    }
    public JSONObject detail(JSONObject actor,String id) {admin(actor);JSONObject work=find(store.snapshot(),"works",id);if(work==null||!store.isOperational(work))throw fail(404,"WORK_NOT_FOUND","作业不存在");return WorkBusiness.present(work);}
    public JSONObject write(JSONObject actor,String id,String action,JSONObject input) {
      synchronized(ledger) { synchronized(WearableBusinessStore.transactionLock()) {
        GuardianAccess.Context ctx=admin(actor);
        String requestId=required(input,"requestId",120),key="work:"+ctx.id()+":"+requestId;
        String fingerprint=org.apache.commons.codec.digest.DigestUtils.sha256Hex(action+"\n"+id+"\n"+JSONObject.toJSONString(new TreeMap<String,Object>(input)));
        final JSONObject[] result={null};
        store.update(state->{
            JSONObject operations=state.getJSONObject("businessOperations");if(operations==null){operations=new JSONObject();state.put("businessOperations",operations);}
            JSONObject old=operations.getJSONObject(key);
            if(old!=null){if(!fingerprint.equals(old.getString("fingerprint")))throw fail(409,"REQUEST_REUSED","请求编号已用于其他操作");result[0]=copy(old.getJSONObject("result"));return false;}
            if(!policy.config().getBooleanValue("workBusinessEnabled"))throw fail(409,"WORK_BUSINESS_DISABLED","作业业务已关闭，历史记录只读");
            JSONObject before=id==null?null:find(state,"works",id);
            if(id!=null&&(before==null||!store.isOperational(before)))throw fail(404,"WORK_NOT_FOUND","作业不存在");
            if(before!=null&&(!input.containsKey("expectedVersion")||input.getIntValue("expectedVersion")!=before.getIntValue("version")))throw fail(409,"VERSION_CONFLICT","作业已变化，请刷新后重试");
            if(before!=null&&!"LOCAL".equals(before.getString("source")))throw fail(409,"WORK_SOURCE_READ_ONLY","来源作业只读，请新建本地登记");
            if(before!=null&&Arrays.asList("已结束","已取消").contains(WorkBusiness.status(before)))throw fail(409,"WORK_READ_ONLY","已结束或取消的作业只读");
            JSONObject work=before==null?new JSONObject():copy(before);String now=Instant.now().toString();
            if(before==null) {work.put("id","LOCAL-"+UUID.randomUUID());work.put("status","待开始");work.put("createdAt",now);work.put("createdBy",ctx.id());work.put("createdByName",ctx.name());work.put("timeline",new JSONArray());}
            if("create".equals(action)||"update".equals(action))applyFields(state,work,input,ctx);
            else if("start".equals(action)){
                if(!"待开始".equals(WorkBusiness.status(work)))throw fail(409,"INVALID_WORK_STATE","仅待开始作业可以开始");
                validatePeople(state,work);
                Instant time=Instant.now();if(time.isBefore(WorkBusiness.start(work))||!time.isBefore(WorkBusiness.end(work)))throw fail(409,"WORK_OUTSIDE_TIME","请先调整计划时间，作业须在计划时段内开始");
                work.put("status","进行中");work.put("startedAt",now);
            } else if("finish".equals(action)){
                if(!WorkBusiness.running(work))throw fail(409,"INVALID_WORK_STATE","仅进行中作业可以结束");work.put("status","已结束");work.put("endedAt",now);
            } else if("cancel".equals(action)){work.put("status","已取消");work.put("cancelledAt",now);}
            else throw fail(400,"UNKNOWN_ACTION","未知作业操作");
            if(WorkBusiness.running(work))checkConflicts(state,work);
            work.put("version",before==null?1:before.getIntValue("version")+1);work.put("updatedAt",now);work.put("updatedBy",ctx.id());work.put("updatedByName",ctx.name());
            String label="create".equals(action)?"登记作业":"update".equals(action)?"修改作业":"start".equals(action)?"开始作业":"finish".equals(action)?"结束作业":"取消作业";
            rows(work,"timeline").add(object("time",now,"text",label,"actorId",ctx.id(),"actorName",ctx.name()));
            if(before==null)rows(state,"works").add(work);else {before.clear();before.putAll(work);}
            rows(state,"audit").add(object("id","WA-"+UUID.randomUUID(),"siteId",work.getString("siteId"),"actorId",ctx.id(),"actorName",ctx.name(),"action","works."+action,"objectId",work.getString("id"),"objectName",work.getString("name"),"time",now,"occurredAt",now,"result","SUCCESS","requestId",requestId,"text",label,"after",copy(work)));
            result[0]=WorkBusiness.present(work);operations.put(key,object("fingerprint",fingerprint,"result",copy(result[0])));state.put("seq",state.getIntValue("seq")+1);return true;
        });
        return result[0];
      }}
    }
    private void applyFields(JSONObject state,JSONObject work,JSONObject input,GuardianAccess.Context ctx) {
        for(String key:Arrays.asList("siteId","name","area","plannedStartAt","plannedEndAt","leader","supervisor","members","remarks"))if(input.containsKey(key))work.put(key,input.get(key));
        String site=required(work,"siteId",100);JSONObject siteRecord=find(ctx.data,"sites",site);if(siteRecord==null||!ctx.site(site))throw fail(400,"INVALID_SITE","请选择有效厂站");
        work.put("station",siteRecord.getString("portalStation"));work.put("name",required(work,"name",100));work.put("area",required(work,"area",200));
        work.put("leader",required(work,"leader",100));work.put("supervisor",required(work,"supervisor",100));
        Instant from=WorkBusiness.instant(work.getString("plannedStartAt")),to=WorkBusiness.instant(work.getString("plannedEndAt"));
        if(from==null||to==null||!from.isBefore(to))throw fail(400,"INVALID_TIME","请填写有效起止日期时间，结束须晚于开始");
        work.put("plannedStartAt",from.toString());work.put("plannedEndAt",to.toString());
        work.put("date",from.atZone(WorkBusiness.ZONE).toLocalDate().toString());work.put("start",from.atZone(WorkBusiness.ZONE).toLocalTime().withSecond(0).withNano(0).toString());work.put("end",to.atZone(WorkBusiness.ZONE).toLocalTime().withSecond(0).withNano(0).toString());
        Object suppliedMembers=work.get("members");
        if(!(suppliedMembers instanceof Collection))throw fail(400,"INVALID_MEMBERS","请选择参加人员");
        LinkedHashSet<String> unique=new LinkedHashSet<>();for(Object raw:(Collection<?>)suppliedMembers){if(!(raw instanceof String))throw fail(400,"INVALID_MEMBERS","人员编号无效");unique.add((String)raw);}
        unique.add(work.getString("leader"));unique.add(work.getString("supervisor"));work.put("members",new JSONArray(unique));validatePeople(state,work);
        String remarks=text(work,"remarks");if(remarks.length()>1000)throw fail(400,"INVALID_REMARKS","备注最多1000字");work.put("remarks",remarks);
        work.put("source","LOCAL");work.put("externalId","");work.remove("externalStatus");
        JSONObject names=new JSONObject();for(String person:unique)names.put(person,find(state,"people",person).getString("name"));work.put("participantNames",names);
    }
    private void validatePeople(JSONObject state,JSONObject work) {if(!WorkBusiness.validPeople(state,work))throw fail(400,"INVALID_MEMBERS","负责人、监护人及参加人员须为同厂站有效人员");}
    private void checkConflicts(JSONObject state,JSONObject work) {
        validatePeople(state,work);
        for(Object raw:rows(state,"works")){JSONObject other=(JSONObject)raw;
            if(Objects.equals(other.getString("id"),work.getString("id"))||!store.isOperational(other)||!WorkBusiness.running(other)||!WorkBusiness.overlaps(work,other)||!WorkBusiness.validPeople(state,other))continue;
            for(Object person:rows(work,"members"))if(has(other.getJSONArray("members"),String.valueOf(person)))throw fail(409,"WORK_CONFLICT","参加人员在该时段已有进行中的作业："+other.getString("name"));
        }
    }
    private String required(JSONObject input,String key,int max) {Object raw=input==null?null:input.get(key);String value=raw instanceof String?((String)raw).trim():"";if(value.isEmpty()||value.length()>max)throw fail(400,"INVALID_FIELD","请填写有效的 "+key);return value;}
}
