package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Rebuild only a read projection from the existing authoritative ledger. */
final class GuardianMasterProjection {
    static void apply(JSONObject snapshot,JSONObject admin) {
        WearableModel.migrate(admin);
        for(Object raw:rows(admin,"sites")) { JSONObject s=(JSONObject)raw;JSONObject target=find(snapshot,"stations",s.getString("portalStation"));
            if(target==null){target=object("id",s.getString("portalStation"));rows(snapshot,"stations").add(target);} target.put("name",s.getString("name"));target.put("siteId",s.getString("id"));target.put("enabled",s.getBooleanValue("enabled")); }
        for(Object raw:rows(admin,"people")) { JSONObject p=(JSONObject)raw,s=find(admin,"sites",p.getString("siteId"));if(s==null)continue;
            JSONObject target=find(snapshot,"people",p.getString("portalId"));
            if(target==null){target=object("id",p.getString("portalId"),"phone","","locationValid",false,"updated",null);rows(snapshot,"people").add(target);}
            JSONObject area=find(admin,"areas",p.getString("areaId")),org=find(admin,"organizations",p.getString("organizationId"));
            target.put("name",p.getString("name"));target.put("ledgerId",p.getString("id"));target.put("siteId",s.getString("id"));target.put("station",s.getString("portalStation"));target.put("active",p.getBooleanValue("enabled"));target.put("areaId",p.get("areaId"));target.put("area",area==null?"未关联区域":area.getString("name"));target.put("team",org==null?"":org.getString("name"));
        }
        for(Object raw:rows(admin,"devices")) {JSONObject d=(JSONObject)raw,s=find(admin,"sites",d.getString("siteId"));if(s==null)continue;
            String type="HELMET".equals(d.getString("type"))?"H":"BELT".equals(d.getString("type"))?"B":"WATCH".equals(d.getString("type"))?"W":null;if(type==null)continue;
            String id=d.getString("portalDeviceId");JSONObject target=find(snapshot,"devices",id);
            if(target==null){target=object("id",id,"online",null,"battery",null,"video","unavailable","updated",null);rows(snapshot,"devices").add(target);}
            boolean active=!Arrays.asList("DISABLED","SCRAPPED").contains(d.getString("lifecycle"));
            target.put("areaId",d.getString("areaId"));target.put("type",type);target.put("station",s.getString("portalStation"));target.put("siteId",s.getString("id"));target.put("ledgerId",d.getString("id"));target.put("active",active);target.put("name",d.getString("name"));
            JSONObject assignment=null;for(Object a:rows(admin,"assignments")) {JSONObject row=(JSONObject)a;if(row.getBooleanValue("active")&&d.getString("id").equals(row.getString("deviceId"))) assignment=row;}
            JSONObject person=assignment==null?null:find(admin,"people",assignment.getString("personId"));
            String held=active&&"IN_USE".equals(d.getString("lifecycle"))&&person!=null&&person.getBooleanValue("enabled")?person.getString("portalId"):null;
            JSONObject kept=null;
            for(Object b:rows(snapshot,"bindings")) {JSONObject binding=(JSONObject)b;if(!id.equals(binding.getString("deviceId"))||binding.get("end")!=null)continue;
                if(held!=null&&held.equals(binding.getString("personId"))&&kept==null)kept=binding;
                else binding.put("end",java.time.Instant.now().toString()); }
            if(held!=null&&kept==null) rows(snapshot,"bindings").add(object("id","BIND-"+assignment.getString("id")+"-"+assignment.getIntValue("version"),"deviceId",id,"personId",held,"start",assignment.getString("startedAt"),"end",null,"operator","后台领用台账"));
        }
    }
}
