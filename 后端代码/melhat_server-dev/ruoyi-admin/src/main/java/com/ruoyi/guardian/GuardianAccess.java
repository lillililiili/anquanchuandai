package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

@Service
public class GuardianAccess {
    private final AdminLedgerStore ledger;
    private final AdminQueryService queries;
    public GuardianAccess(AdminLedgerStore ledger,AdminQueryService queries) { this.ledger=ledger;this.queries=queries; }
    public Context context(JSONObject actor) { return new Context(ledger.read(),actor==null?null:actor.getString("id")); }
    public final class Context {
        final JSONObject data;
        final JSONObject actor;
        final JSONObject person;
        Context(JSONObject data,String accountId) {
            this.data=data; this.actor=find(data,"accounts",accountId);
            if(actor==null || !actor.getBooleanValue("enabled")) throw AdminQueryService.fail(401,"IDENTITY_INVALID","登录已失效");
            JSONObject linked=find(data,"people",actor.getString("personId"));
            this.person=linked!=null && linked.getBooleanValue("enabled") ? linked : null;
        }
        public String id() { return actor.getString("id"); }
        public String name() { return actor.getString("name"); }
        public String personId() { return person==null?null:person.getString("portalId"); }
        public boolean can(String op,String site,String area) {
            JSONObject s=find(data,"sites",site);
            if(s==null || !s.getBooleanValue("enabled")) return false;
            if("demo-system".equals(id())) return true;
            for(Object raw:rows(data,"roles")) { JSONObject role=(JSONObject)raw;
                if(!role.getBooleanValue("enabled") || !has(actor.getJSONArray("roleIds"),role.getString("id"))) continue;
                JSONObject scopes=actor.getJSONObject("roleScopes"), scope=scopes==null?null:scopes.getJSONObject(role.getString("id"));
                for(Object value:rows(role,"grants")) { JSONObject grant=(JSONObject)value;
                    if(!has(grant.getJSONArray("siteIds"),site) || !(has(grant.getJSONArray("operations"),op)||has(grant.getJSONArray("operations"),"*"))) continue;
                    if(scope!=null && scope.getJSONArray("siteIds")!=null && !has(scope.getJSONArray("siteIds"),site)) continue;
                    boolean allowed="*".equals(grant.get("areaIds")) || area!=null && has(grant.getJSONArray("areaIds"),area);
                    if(scope!=null && scope.get("areaIds")!=null && !"*".equals(scope.get("areaIds"))) allowed=allowed && area!=null && has(scope.getJSONArray("areaIds"),area);
                    if(allowed) return true;
                }
            }
            return false;
        }
        public boolean site(String id) {
            JSONObject s=find(data,"sites",id);
            if(s==null || !s.getBooleanValue("enabled")) return false;
            if("demo-system".equals(id())) return true;
            for(Object raw:rows(data,"roles")) { JSONObject role=(JSONObject)raw;
                if(!has(actor.getJSONArray("roleIds"),role.getString("id")) || !role.getBooleanValue("enabled")) continue;
                JSONObject scopes=actor.getJSONObject("roleScopes"); JSONObject scope=scopes==null?null:scopes.getJSONObject(role.getString("id"));
                for(Object g:rows(role,"grants")) {
                    JSONObject grant=(JSONObject)g;
                    if(has(grant.getJSONArray("siteIds"),id) && (scope==null || scope.getJSONArray("siteIds")==null || has(scope.getJSONArray("siteIds"),id))) return true;
                }
            }
            return false;
        }
        public boolean anyArea(String operation,String site) {
            if(can(operation,site,null)) return true;
            for(Object raw:rows(data,"areas")) {JSONObject area=(JSONObject)raw;if(site.equals(area.getString("siteId"))&&area.getBooleanValue("enabled")&&can(operation,site,area.getString("id")))return true;}
            return false;
        }
        String eventSite(JSONObject event) { String s=event.getString("siteId");return s==null?siteId(data,event.getString("station")):s; }
        String eventArea(JSONObject event) {
            if(event.getString("areaId")!=null) return event.getString("areaId");
            JSONObject p=WearableModel.person(data,event.getString("personId")); return p==null?null:p.getString("areaId");
        }
        boolean own(JSONObject event) { return personId()!=null && personId().equals(event.getString("personId")); }
        public boolean event(JSONObject event) {
            if(event==null) return false;
            String site=eventSite(event),area=eventArea(event);
            return site(site) && (can("events:read",site,area) || own(event) && can("self:read",site,area));
        }
        public void requireEvent(JSONObject event,String operation) {
            if(!event(event)) throw AdminQueryService.fail(404,"EVENT_NOT_FOUND","事件不存在或不在授权范围");
            if(operation!=null && !can(operation,eventSite(event),eventArea(event))) throw AdminQueryService.fail(403,"PERMISSION_DENIED","没有此事件的操作权限");
        }
        boolean person(JSONObject p) {
            return p!=null && site(p.getString("siteId")) && (can("people:read",p.getString("siteId"),p.getString("areaId")) || Objects.equals(p.getString("portalId"),personId()) && can("self:read",p.getString("siteId"),p.getString("areaId")));
        }
        public boolean work(JSONObject work) {
            String site=siteId(data,work.getString("station"));
            if(!site(site)) return false;
            boolean assigned=has(work.getJSONArray("members"),personId()) || Objects.equals(personId(),work.getString("leader")) && personId()!=null || Objects.equals(personId(),work.getString("supervisor")) && personId()!=null;
            if(assigned && can("works:read",site,person==null?null:person.getString("areaId"))) return true;
            // A restricted duty account may only see work containing an authorized participant.
            for(Object raw:rows(data,"people")) { JSONObject p=(JSONObject)raw;
                if(has(work.getJSONArray("members"),p.getString("portalId")) && can("events:read",site,p.getString("areaId")) && can("works:read",site,p.getString("areaId"))) return true; }
            return can("events:read",site,null) && can("works:read",site,null);
        }
        public JSONObject identity() {
            JSONArray sites=new JSONArray(); for(Object raw:rows(data,"sites")) { JSONObject s=(JSONObject)raw; if(site(s.getString("id"))) sites.add(copy(s)); }
            JSONObject permissions=new JSONObject();
            for(Object raw:sites) {JSONObject s=(JSONObject)raw;JSONArray granted=new JSONArray();for(String op:Arrays.asList("self:read","people:read","assets:read","assets:write","events:read","events:claim","events:observe","events:verify","sos:create","sos:assist","works:read","communications:voice","communications:broadcast"))if(anyArea(op,s.getString("id")))granted.add(op);permissions.put(s.getString("id"),granted);}
            JSONObject result=object("id",id(),"accountId",id(),"name",name(),"loginName",actor.getString("loginName"),"personId",personId(),"ledgerPersonId",person==null?null:person.getString("id"),"roleIds",actor.get("roleIds"),"sites",sites,"permissionsBySite",permissions);
            return result;
        }
        public JSONObject permissions(JSONObject event) {
            JSONObject result=new JSONObject();
            for(String op:Arrays.asList("events:claim","events:observe","events:verify","sos:assist")) result.put(op,event(event) && can(op,eventSite(event),eventArea(event)));
            return result;
        }
        public JSONObject snapshot(JSONObject source) {
            JSONObject out=safe(source);
            JSONArray events=new JSONArray(); Set<String> ids=new HashSet<>();
            for(Object raw:rows(out,"events")) { JSONObject e=(JSONObject)raw; if(event(e)) { e.put("permissions",permissions(e));events.add(e);ids.add(e.getString("id")); } }
            out.put("events",events);
            filter(out,"stations",p->site(siteId(data,p.getString("id"))));
            filter(out,"people",p->person(WearableModel.person(data,p.getString("id"))));
            filter(out,"works",this::work);
            Set<String> peopleIds=new HashSet<>(); for(Object raw:rows(out,"people")) peopleIds.add(((JSONObject)raw).getString("id"));
            filter(out,"devices",d->{
                String site=siteId(data,d.getString("station"));
                JSONObject master=null;for(Object raw:rows(data,"devices")) if(Objects.equals(((JSONObject)raw).getString("portalDeviceId"),d.getString("id"))) master=(JSONObject)raw;
                if(master!=null && can("assets:read",site,master.getString("areaId"))) return true;
                if(personId()==null || !can("self:read",site,person==null?null:person.getString("areaId"))) return false;
                for(Object raw:rows(source,"bindings")) { JSONObject b=(JSONObject)raw;if(b.get("end")==null && personId().equals(b.getString("personId")) && d.getString("id").equals(b.getString("deviceId"))) return true; }
                return false;
            });
            Set<String> devices=new HashSet<>();for(Object raw:rows(out,"devices")) devices.add(((JSONObject)raw).getString("id"));
            filter(out,"bindings",b->peopleIds.contains(b.getString("personId")) && devices.contains(b.getString("deviceId")));
            filter(out,"media",m->m.getString("eventId")!=null&&!m.getString("eventId").isEmpty()?ids.contains(m.getString("eventId")):peopleIds.contains(m.getString("personId")));
            for(String key:Arrays.asList("locations","fenceRecords","vitals")) filter(out,key,p->peopleIds.contains(p.getString("personId")));
            for(String key:Arrays.asList("fences","groups","calls","broadcasts","mapAreas")) filter(out,key,p->can("events:read",siteId(data,p.getString("station")),null));
            JSONObject assist=out.getJSONObject("assistance"); if(assist!=null) for(String id:new ArrayList<>(assist.keySet())) if(!ids.contains(id)) assist.remove(id);
            JSONObject legacy=out.getJSONObject("sos");if(legacy!=null && !ids.contains(legacy.getString("eventId"))) out.put("sos",null);
            out.put("audit",new JSONArray());
            out.put("operator",identity());
            JSONArray communications=new JSONArray();
            for(Object raw:rows(source,"sharedCommunications")){JSONObject row=(JSONObject)raw;if(GuardianMobileCommunications.visible(this,row))communications.add(GuardianMobileCommunications.publicRow(row));}
            out.put("communicationRecords",communications);
            return out;
        }
    }
    private static void filter(JSONObject state,String key,java.util.function.Predicate<JSONObject> keep) {
        JSONArray result=new JSONArray();for(Object raw:rows(state,key)) if(keep.test((JSONObject)raw)) result.add(raw);state.put(key,result);
    }
}
