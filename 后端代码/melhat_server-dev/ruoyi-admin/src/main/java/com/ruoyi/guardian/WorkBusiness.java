package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.time.*;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Shared work matching and read projection. Never changes archived evidence. */
public final class WorkBusiness {
    private WorkBusiness() {}
    public static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    public static boolean enabled(JSONObject state) {
        JSONObject config=state==null?null:state.getJSONObject("businessConfig");
        return config==null || !Boolean.FALSE.equals(config.get("workBusinessEnabled"));
    }
    public static Instant instant(String value) {
        if(value==null || value.trim().isEmpty()) return null;
        try { return Instant.parse(value); } catch(RuntimeException ignored) {}
        try { return OffsetDateTime.parse(value).toInstant(); } catch(RuntimeException ignored) {}
        try { return LocalDateTime.parse(value.replace(' ','T')).atZone(ZONE).toInstant(); } catch(RuntimeException ignored) { return null; }
    }
    public static Instant start(JSONObject work) { return boundary(work,"plannedStartAt","start"); }
    public static Instant end(JSONObject work) { return boundary(work,"plannedEndAt","end"); }
    private static Instant boundary(JSONObject work,String full,String clock) {
        Instant value=instant(work.getString(full));
        return value!=null?value:instant(work.getString("date")+"T"+work.getString(clock));
    }
    public static String status(JSONObject work) { return "监护中".equals(work.getString("status"))?"进行中":work.getString("status"); }
    public static boolean running(JSONObject work) { return "进行中".equals(status(work)); }
    public static boolean current(JSONObject work,Instant at) {
        Instant from=start(work),to=end(work);
        return running(work)&&from!=null&&to!=null&&!at.isBefore(from)&&at.isBefore(to);
    }
    public static boolean validPeople(JSONObject state,JSONObject work) {
        JSONArray members=work.getJSONArray("members");
        if(members==null||members.isEmpty())return false;
        for(Object id:members) { JSONObject p=find(state,"people",String.valueOf(id));
            if(p==null||!p.getBooleanValue("active")||!Objects.equals(p.getString("station"),work.getString("station")))return false;
        }
        return members.contains(work.getString("leader"))&&members.contains(work.getString("supervisor"));
    }
    public static JSONObject match(JSONObject state,String personId,String station,Instant at) {
        if(!enabled(state)||personId==null||personId.isEmpty()||at==null)return null;
        JSONObject match=null;
        for(Object raw:rows(state,"works")){JSONObject work=(JSONObject)raw;
            if(GuardianDemoData.confirmed(work)||!Objects.equals(station,work.getString("station"))||!has(work.getJSONArray("members"),personId)||!current(work,at)||!validPeople(state,work))continue;
            if(match!=null)return null;
            match=work;
        }
        if(match==null)return null;
        JSONObject captured=copy(match),names=new JSONObject();
        for(Object id:rows(match,"members")){JSONObject p=find(state,"people",String.valueOf(id));if(p!=null)names.put(String.valueOf(id),p.getString("name"));}
        captured.put("participantNames",names);return captured;
    }
    public static void capture(JSONObject state,JSONObject event,JSONObject work) {
        event.put("workId",work==null?"":work.getString("id"));
        JSONObject snapshot=event.getJSONObject("snapshot");if(snapshot==null){snapshot=new JSONObject();event.put("snapshot",snapshot);}
        for(String key:Arrays.asList("workName","workId","leaderId","leaderName","supervisorId","supervisorName"))snapshot.remove(key);
        if(work==null)return;
        snapshot.put("workId",work.getString("id"));snapshot.put("workName",work.getString("name"));
        for(String role:Arrays.asList("leader","supervisor")){String id=work.getString(role);JSONObject person=find(state,"people",id);
            JSONObject names=work.getJSONObject("participantNames");
            snapshot.put(role+"Id",id);snapshot.put(role+"Name",names!=null&&names.containsKey(id)?names.getString(id):person==null?"":person.getString("name"));}
    }
    public static boolean overlaps(JSONObject first,JSONObject second) {
        Instant a=start(first),b=end(first),c=start(second),d=end(second);
        return a!=null&&b!=null&&c!=null&&d!=null&&a.isBefore(d)&&c.isBefore(b);
    }
    public static JSONObject present(JSONObject work) {
        JSONObject out=copy(work);out.put("status",status(work));
        Instant from=start(work),to=end(work);if(from!=null)out.put("plannedStartAt",from.toString());if(to!=null)out.put("plannedEndAt",to.toString());
        out.put("overdue",running(work)&&to!=null&&!Instant.now().isBefore(to));
        return out;
    }
    public static void stripRecord(JSONObject record) {
        if(record==null)return;
        for(String key:Arrays.asList("workId","taskId","currentWork","workName","work","task","ticketNo","ticketStatus","ticketRequired","externalId","externalRecordId","externalSource","externalSystem","externalStatus","externalPending","sourceStatus"))record.remove(key);
        JSONObject snapshot=record.getJSONObject("snapshot");
        if(snapshot!=null)for(String key:Arrays.asList("workId","workName","leaderId","leaderName","supervisorId","supervisorName","externalId","externalStatus"))snapshot.remove(key);
    }
    public static JSONObject project(JSONObject state) {
        if(enabled(state)) {JSONArray works=new JSONArray();for(Object raw:rows(state,"works"))works.add(present((JSONObject)raw));state.put("works",works);return state;}
        state.put("works",new JSONArray());
        for(String key:Arrays.asList("people","events","media","locations","fenceRecords"))for(Object raw:rows(state,key))stripRecord((JSONObject)raw);
        stripRecord(state.getJSONObject("sos"));
        return state;
    }
}
