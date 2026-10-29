package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.AdminLedgerStore;
import com.ruoyi.guardian.GuardianStore;
import com.ruoyi.guardian.DirectBeltAccess;
import com.ruoyi.helmet.service.DirectHelmetAccess;
import com.ruoyi.guardian.FudaAlarmJournal;
import com.ruoyi.melhat.direct.DirectHelmetProperties;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import java.time.Clock;
import java.util.*;
import static com.ruoyi.fuda.FudaMapping.*;

@Service
public class FudaQueryService {
    private final FudaProperties properties;private final AdminLedgerStore ledger;private final GuardianStore guardian;
    private final FudaAlarmJournal alarms;private final DirectHelmetProperties helmet;private final DirectBeltProperties belt;private final Clock clock;
    private final DirectHelmetAccess helmetAccess;private final DirectBeltAccess beltAccess;
    public FudaQueryService(FudaProperties properties,AdminLedgerStore ledger,GuardianStore guardian,FudaAlarmJournal alarms,
            DirectHelmetProperties helmet,DirectBeltProperties belt,DirectHelmetAccess helmetAccess,DirectBeltAccess beltAccess,@Qualifier("fudaClock") Clock clock){
        this.properties=properties;this.ledger=ledger;this.guardian=guardian;this.alarms=alarms;this.helmet=helmet;this.belt=belt;this.clock=clock;
        this.helmetAccess=helmetAccess;this.beltAccess=beltAccess;
    }
    public JSONObject query(String kind,FudaAuth.Principal principal,JSONObject request){
        Map<String,JSONObject> scope=authorized(principal);
        if("alarms".equals(kind))return alarmPage(principal,request,scope.keySet());
        if(!request.keySet().equals(Collections.singleton("devices")))throw FudaException.bad("Expected devices only");
        Object rawDevices=request.get("devices");if(!(rawDevices instanceof JSONArray))throw FudaException.bad("devices must be an array");
        JSONArray requested=(JSONArray)rawDevices;if(requested.isEmpty()||requested.size()>100)throw FudaException.bad("devices must contain 1 to 100 items");
        List<JSONObject> rows=new ArrayList<>();Set<String> unique=new HashSet<>();
        // Validate the complete batch before reading telemetry or returning any item.
        for(Object item:requested){
            if(!(item instanceof JSONObject))throw FudaException.bad("Invalid device reference");JSONObject ref=(JSONObject)item;
            if(!ref.keySet().equals(new HashSet<>(Arrays.asList("deviceType","deviceId")))||!(ref.get("deviceType") instanceof String)||!(ref.get("deviceId") instanceof String))throw FudaException.bad("Expected deviceType and deviceId strings");
            String type=ref.getString("deviceType"),id=ref.getString("deviceId");
            if(!Arrays.asList("HELMET","SAFETY_BELT").contains(type)||!id.matches("[A-Za-z0-9._-]{1,64}"))throw FudaException.bad("Invalid deviceType or deviceId");
            String key=type+":"+id;if(!unique.add(key))throw FudaException.bad("Duplicate device reference");
            if(!scope.containsKey(key))throw new FudaException(403,40301,"Device outside authorized scope");rows.add(scope.get(key));
        }
        JSONObject snapshot=guardian.snapshot();Map<String,JSONObject> telemetry=new HashMap<>();
        JSONArray devices=snapshot.getJSONArray("devices");if(devices!=null)for(Object raw:devices){JSONObject d=(JSONObject)raw;telemetry.put(d.getString("id"),d);}
        List<JSONObject> items=new ArrayList<>();
        for(JSONObject row:rows){
            String type=deviceType(row),id=row.getString("deviceNumber");JSONObject d=telemetry.get(row.getString("portalDeviceId"));
            if(d==null||simulated(d)||!Objects.equals(row.getString("source"),d.getString("source")))d=object("online",false);
            else d=new JSONObject(d);
            // Maintenance pauses projections, not physical disconnection. Never export cached online=true.
            JSONObject live="HELMET".equals(type)?helmetAccess.status(id):beltAccess.status(id);
            boolean enabled=!Arrays.asList("DISABLED","SCRAPPED").contains(row.getString("lifecycle"))&&(!d.containsKey("active")||d.getBooleanValue("active"));
            d.put("online",enabled&&live!=null&&live.getBooleanValue("online"));
            if(live!=null&&time(live.get("lastSeenAt"))!=null)d.put("lastSeenAt",live.get("lastSeenAt"));
            applyLocationProfile(d,properties.getLocationProfiles().get(row.getString("id")));
            JSONObject base=common(properties.getSourcePlatform(),type,id,model(row));int timeout="HELMET".equals(type)?helmet.getHeartbeatTimeoutSeconds():belt.getHeartbeatTimeoutSeconds();
            items.add("positions".equals(kind)?positionItem(base,d,timeout,clock):statusItem(base,d,timeout,belt,clock));
        }
        return object("items",items);
    }
    private JSONObject alarmPage(FudaAuth.Principal p,JSONObject request,Set<String> scope){
        if(!request.containsKey("cursor")||!new HashSet<>(Arrays.asList("cursor","limit")).containsAll(request.keySet())||request.get("cursor")!=null&&!(request.get("cursor") instanceof String))throw FudaException.bad("Expected cursor and optional integer limit");
        Object limitValue=request.containsKey("limit")?request.get("limit"):100;if(!(limitValue instanceof Integer)||((Integer)limitValue)<1||((Integer)limitValue)>500)throw FudaException.bad("limit must be an integer from 1 to 500");
        long after=FudaCursor.decode(p,scope,request.getString("cursor"));
        if(after<alarms.retainedFloor())throw new FudaException(410,41001,"Cursor expired; historical recovery required");
        if(after>alarms.highWatermark())throw new FudaException(409,40903,"Cursor is ahead of durable history; recovery required");
        FudaAlarmJournal.AlarmPage page=alarms.scan(after,(Integer)limitValue,scope);List<JSONObject> items=new ArrayList<>();
        for(JSONObject row:page.items)items.add(alarm(properties.getSourcePlatform(),row));
        return object("items",items,"nextCursor",FudaCursor.encode(p,scope,page.nextSequence),"hasMore",page.hasMore);
    }
    private Map<String,JSONObject> authorized(FudaAuth.Principal principal){
        JSONObject state=ledger.read();if(state==null)throw new FudaException(503,50304,"Device registry unavailable");
        Map<String,JSONObject> result=new LinkedHashMap<>();JSONArray devices=state.getJSONArray("devices");
        if(devices!=null)for(Object raw:devices){JSONObject d=(JSONObject)raw;
            // Asset lifecycle changes do not revoke historical export scope. Only the explicit
            // application allowlist revokes sharing; disabled assets are always reported offline.
            if(!principal.application.getAllowedLedgerDeviceIds().contains(d.getString("id"))||simulated(d))continue;
            String type=deviceType(d),id=d.getString("deviceNumber");
            if(type==null||id==null||!id.matches("[A-Za-z0-9._-]{1,64}")||!id.equals(d.getString("portalDeviceId")))continue;
            if(result.put(type+":"+id,d)!=null)throw new FudaException(503,50304,"Ambiguous device registry");
        }
        if(result.isEmpty())throw new FudaException(403,40301,"No authorized real devices");return result;
    }
    private static String deviceType(JSONObject d){return "DIRECT_HELMET".equals(d.getString("source"))&&"HELMET".equals(d.getString("type"))?"HELMET":"DIRECT_BELT".equals(d.getString("source"))&&"BELT".equals(d.getString("type"))?"SAFETY_BELT":null;}
    private static String model(JSONObject d){String m=text(d,"deviceModel");if(m==null)m=text(d,"model");if(m==null)m=text(d,"modelName");return m;}
}
