package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

@Service
public class GuardianLocations {
    private final GuardianAccess access;
    private final GuardianStore store;
    private final HelmetBusinessJournal journal;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableBusinessStore business;
    public GuardianLocations(GuardianAccess access,GuardianStore store,HelmetBusinessJournal journal) {
        this.access=access;this.store=store;this.journal=journal;
    }
    public JSONObject current(JSONObject actor,String personId) {
        GuardianAccess.Context ctx=access.context(actor);
        JSONObject master=WearableModel.person(ctx.data,personId);
        if(!ctx.person(master)) throw fail();
        JSONObject person=find(store.snapshot(),"people",personId);
        JSONObject result=object("personId",personId,"locationQuality","unknown","locationFreshness","UNKNOWN","coordinateSystem","UNKNOWN");
        if(person!=null) {
            for(String key:new String[]{"latitude","longitude","coordinateSystem","locationSource","accuracyMeters","locationQuality","locationFreshness","fenceEvaluation","locationTimeBasis","locationAssignmentId","locationAssignmentVersion","lastKnownLocation"})
                if(person.containsKey(key)) result.put(key,person.get(key));
            result.put("deviceId",person.get("locationDeviceId"));result.put("reportedAt",person.get("locationReportedAt"));
            result.put("locationReportedAt",person.get("locationReportedAt"));
            if(!person.getBooleanValue("locationValid")) result.put("locationQuality","unknown");
        }
        return result;
    }
    public JSONObject history(JSONObject actor,String personId,String deviceId,String from,String to,String cursor,int limit) {
        if((personId==null)==(deviceId==null) || limit<1 || limit>1000) throw new IllegalArgumentException("请选择人员或设备，查询数量为1至1000");
        long start=parse(from),end=parse(to);
        if(end<=start || end-start>31L*86400000) throw new IllegalArgumentException("轨迹查询范围须在31天内");
        GuardianAccess.Context ctx=access.context(actor);
        if(personId!=null) {
            if(!ctx.person(WearableModel.person(ctx.data,personId))) throw fail();
        } else {
            JSONObject device=null;
            for(Object raw:rows(ctx.data,"devices")) {
                JSONObject candidate=(JSONObject)raw;
                if(deviceId.equals(candidate.getString("portalDeviceId"))) device=candidate;
            }
            if(device==null || !ctx.can("assets:read",device.getString("siteId"),device.getString("areaId"))) throw fail();
        }
        long cursorTime=start-1;String cursorId="";
        if(cursor!=null && !cursor.isEmpty()) {
            try {
                if(cursor.length()>200) throw new IllegalArgumentException();
                String[] fields=new String(Base64.getUrlDecoder().decode(cursor),StandardCharsets.UTF_8).split("\\|",-1);
                if(fields.length!=2 || !fields[1].matches("[A-Za-z0-9._:-]{1,128}")) throw new IllegalArgumentException();
                cursorTime=Long.parseLong(fields[0]);cursorId=fields[1];
                if(cursorTime<start || cursorTime>=end) throw new IllegalArgumentException();
            } catch(RuntimeException error) { throw new IllegalArgumentException("轨迹游标无效"); }
        }
        JSONArray output=new JSONArray();JSONObject last=null;boolean more=true;
        // Filter every observation using its captured site/person, not today's binding.
        int scanned=0;
        while(output.size()<limit && more && scanned<10000) {
            List<JSONObject> batch=locations(personId,deviceId,start,end,cursorTime,cursorId,500);
            more=!batch.isEmpty();
            if(batch.isEmpty()) break;
            for(JSONObject row:batch) {
                if(visible(ctx,row,personId==null)) {
                    if(output.size()==limit) { more=true;break; }
                    JSONObject publicPoint=safe(row);
                    publicPoint.put("locationTimeBasis",PersonLocationProjection.timeBasis(row));
                    for(String key:new String[]{"device","person","work","receivedMillis","collectedMillis","queryMillis","timestamp","firmware"}) publicPoint.remove(key);
                    output.add(publicPoint);
                }
                last=row;cursorTime=row.getLongValue("queryMillis");cursorId=row.getString("id");scanned++;
                if(output.size()==limit) break;
            }
            if(batch.size()<500 && output.size()<limit) more=false;
        }
        // A cursor may produce one final empty page; it never skips an authorized observation.
        String next=more&&last!=null?Base64.getUrlEncoder().withoutPadding().encodeToString((last.getLongValue("queryMillis")+"|"+last.getString("id")).getBytes(StandardCharsets.UTF_8)):null;
        return object("rows",output,"nextCursor",next,"from",from,"to",to);
    }
    private List<JSONObject> locations(String personId,String deviceId,long from,long to,long cursorTime,String cursorId,int limit) {
        List<JSONObject> legacy=journal.locations(personId,deviceId,from,to,cursorTime,cursorId,limit);
        if(business==null)return legacy;
        Map<String,JSONObject> unique=new HashMap<String,JSONObject>();
        for(JSONObject row:business.locations(personId,deviceId,from,to,cursorTime,cursorId,limit))unique.put(row.getString("id"),row);
        // The original helmet SQL journal retains full historical context beyond the old snapshot window.
        for(JSONObject row:legacy)unique.put(row.getString("id"),row);
        List<JSONObject> merged=new ArrayList<JSONObject>(unique.values());
        merged.sort(Comparator.comparingLong((JSONObject row)->row.getLongValue("queryMillis")).thenComparing(row->row.getString("id")));
        return merged.size()>limit?new ArrayList<JSONObject>(merged.subList(0,limit)):merged;
    }
    static boolean visible(GuardianAccess.Context ctx,JSONObject row,boolean byDevice) {
        String site=row.getString("siteId");
        if(site==null||site.isEmpty())return byDevice&&"demo-system".equals(ctx.id());
        return ctx.site(site) && (ctx.can(byDevice?"assets:read":"people:read",site,null)
                || !byDevice && Objects.equals(ctx.personId(),row.getString("personId")) && ctx.personId()!=null && ctx.can("self:read",site,null));
    }
    private static long parse(String value) {
        try { return Instant.parse(value).toEpochMilli(); } catch(RuntimeException e) { throw new IllegalArgumentException("时间须使用含时区的ISO8601格式"); }
    }
    private static AdminQueryService.QueryFailed fail() { return AdminQueryService.fail(404,"LOCATION_NOT_FOUND","人员或设备不存在或不在授权范围"); }
}
