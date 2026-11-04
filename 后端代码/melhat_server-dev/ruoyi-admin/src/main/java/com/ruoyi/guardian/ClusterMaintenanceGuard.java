package com.ruoyi.guardian;
import com.ruoyi.cluster.*;
import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.*;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.ObjectProvider;
import java.util.*;
@Component
public class ClusterMaintenanceGuard implements ClusterCommandGuard {
    private final ClusterIdentity identity;private final ClusterWorkCoordinator work;private final ClusterDatabase db;
    private final ObjectProvider<GuardianAccess> access;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableBusinessStore business;
    public ClusterMaintenanceGuard(ClusterIdentity identity,ClusterWorkCoordinator work,ClusterDatabase db,ObjectProvider<GuardianAccess> access){this.identity=identity;this.work=work;this.db=db;this.access=access;}
    public void admit(String deviceId){if(identity.enabled()){identity.requireAdmission();work.requireActiveMode();}}
    public void dispatch(String commandId){if(!identity.enabled())return;identity.requireAdmission();work.requireActiveMode();
        JSONObject stored=db.jdbc.queryForObject("SELECT context_json,wire_json,device_id FROM wearable_transport_command WHERE command_id=?",(r,n)->{JSONObject row=JSON.parseObject(r.getString(1));row.put("_wire",JSON.parseObject(r.getString(2)));row.put("deviceId",r.getString(3));return row;},commandId);
        String cmd=stored.getJSONObject("_wire").getString("cmd");
        if("server_push_stop_rtsp".equals(cmd))return; // Revocation must never prohibit termination of an earlier session.
        String actor=stored.getString("actorId");
        if(actor==null){
            if(!"server_push_open_rtsp".equals(cmd))return;
            // Read durable demand BEFORE ledger authorization. No media/Guardian monitor is taken under SQL control.
            if(business==null)throw denied();JSONObject media=business.read("media").state;
            JSONObject streams=media.getJSONObject("streams"),stream=streams==null?null:streams.getJSONObject(stored.getString("deviceId"));
            if(stream==null)throw denied();
            JSONObject leases=media.getJSONObject("gbLeases");JSONArray ids=stream.getJSONArray("gbLeaseIds");
            if(ids!=null&&leases!=null)for(Object raw:ids){JSONObject lease=leases.getJSONObject(String.valueOf(raw));
                if(lease!=null&&!lease.getBooleanValue("released")&&java.time.Instant.parse(lease.getString("expiresAt")).toEpochMilli()>db.now()){JSONObject serviceDemand=new JSONObject();serviceDemand.put("actorId","demo-system");serviceDemand.put("deviceId",stored.get("deviceId"));requireAuthority(serviceDemand);return;}}
            JSONObject viewers=stream.getJSONObject("viewers");
            if(viewers!=null)for(Object raw:viewers.values()){JSONObject captured=(JSONObject)raw;
                if(java.time.Instant.parse(captured.getString("expiresAt")).toEpochMilli()<=db.now())continue;
                JSONObject demand=new JSONObject(captured);demand.put("deviceId",stored.get("deviceId"));
                if(authorizedDemand(demand))return;}
            JSONObject commands=media.getJSONObject("commands"),record=commands==null?null:commands.getJSONObject(stream.getString("recordRequestId"));
            if(stream.getBooleanValue("recordRequested")&&!stream.containsKey("sessionInvalidatedAt")&&record!=null&&authorizedDemand(record))return;
            throw denied();
        }
        requireAuthority(stored);
    }
    private boolean authorizedDemand(JSONObject captured){try{requireAuthority(captured);return true;}catch(AdminQueryService.QueryFailed denied){return false;}}
    private void requireAuthority(JSONObject stored){String actor=stored.getString("actorId");if(actor==null)throw denied();
        GuardianAccess.Context ctx=access.getObject().context(new JSONObject(Collections.singletonMap("id",actor)));
        JSONObject device=null;for(Object raw:ctx.data.getJSONArray("devices")){JSONObject d=(JSONObject)raw;if(stored.getString("deviceId").equals(d.getString("portalDeviceId"))){device=d;break;}}
        if(device==null||Arrays.asList("DISABLED","SCRAPPED").contains(device.getString("lifecycle")))throw denied();
        String permission="broadcast".equals(stored.getString("action"))?"communications:broadcast":"communications:voice";
        if(!ctx.can(permission,device.getString("siteId"),device.getString("areaId")))throw denied();
        if(stored.containsKey("assignmentId")){
            JSONObject assignment=null;for(Object raw:ctx.data.getJSONArray("assignments")){JSONObject a=(JSONObject)raw;if(a.getBooleanValue("active")&&device.getString("id").equals(a.getString("deviceId"))){if(assignment!=null)throw denied();assignment=a;}}
            if(assignment==null||!Objects.equals(stored.getString("assignmentId"),assignment.getString("id"))||stored.getLongValue("assignmentVersion")!=assignment.getLongValue("version"))throw denied();
        }
    }
    private RuntimeException denied(){return AdminQueryService.fail(403,"COMMAND_AUTHORITY_CHANGED","指令的权限或领用关系已变化，未发送");}
}
