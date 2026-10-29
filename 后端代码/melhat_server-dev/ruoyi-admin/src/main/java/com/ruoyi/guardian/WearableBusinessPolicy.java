package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** One persisted visibility policy and explicit physical acceptance evidence for all clients. */
@Service
public class WearableBusinessPolicy {
    public static final String DATA_VERSION = "wearable-person-v2";
    private final JdbcTemplate jdbc;
    public WearableBusinessPolicy(JdbcTemplate jdbc) {
        this.jdbc=jdbc;
        jdbc.execute("CREATE TABLE IF NOT EXISTS wearable_business_config (id INT PRIMARY KEY, version INT NOT NULL, body LONGTEXT NOT NULL)");
        jdbc.execute("CREATE TABLE IF NOT EXISTS wearable_feature_acceptance (device_id VARCHAR(100) NOT NULL, feature_key VARCHAR(40) NOT NULL, evidence VARCHAR(500) NOT NULL, PRIMARY KEY(device_id,feature_key))");
        if(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_config WHERE id=1",Integer.class)==0) {
            // These are acceptance records of the existing physical units, never generated assets or telemetry.
            accept("866652021714127", "output/device-ready/helmet-media-acceptance-20261026/cloud-findings.json", "battery","wear","location","alarm","sos","video");
            accept("866652023095053", "output/device-ready/belt-acceptance-20261025/physical-stage-record.json; belt-sos-20261026/4g-sos-success.json", "battery","hooks","location","alarm","sos");
            jdbc.update("INSERT INTO wearable_business_config(id,version,body) VALUES(1,1,?)", defaults().toJSONString());
        }
    }
    private void accept(String device,String evidence,String... features) {
        for(String feature:features) if(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_feature_acceptance WHERE device_id=? AND feature_key=?",Integer.class,device,feature)==0)
            jdbc.update("INSERT INTO wearable_feature_acceptance(device_id,feature_key,evidence) VALUES(?,?,?)",device,feature,evidence);
    }
    public static JSONObject defaults(){return object("dataVersion",DATA_VERSION,"simulatedWatchVisible",true,"version",1);}
    public JSONObject config(){JSONObject result=JSONObject.parseObject(jdbc.queryForObject("SELECT body FROM wearable_business_config WHERE id=1",String.class));result.put("dataVersion",DATA_VERSION);return result;}
    public synchronized JSONObject configure(JSONObject input,GuardianAccess.Context ctx) {
        if(!"demo-system".equals(ctx.id()))throw AdminQueryService.fail(403,"PERMISSION_DENIED","仅系统管理员可修改全局业务配置");
        if(input==null||!(input.get("simulatedWatchVisible") instanceof Boolean))throw AdminQueryService.fail(400,"INVALID_CONFIG","模拟手表显示设置必须为布尔值");
        JSONObject before=config();
        if(input.containsKey("expectedVersion")&&input.getIntValue("expectedVersion")!=before.getIntValue("version"))throw AdminQueryService.fail(409,"VERSION_CONFLICT","配置已变化，请刷新后重试");
        JSONObject next=copy(before);next.put("simulatedWatchVisible",input.getBooleanValue("simulatedWatchVisible"));next.put("version",before.getIntValue("version")+1);
        next.put("updatedBy",ctx.id());next.put("updatedAt",java.time.Instant.now().toString());
        jdbc.update("UPDATE wearable_business_config SET version=?,body=? WHERE id=1",next.getIntValue("version"),next.toJSONString());return next;
    }
    public JSONObject features(JSONObject device) {
        String source=text(device,"source"),id=text(device,"portalDeviceId");if(id.isEmpty())id=text(device,"deviceNumber");if(id.isEmpty())id=text(device,"id");
        boolean hat="DIRECT_HELMET".equals(source),belt="DIRECT_BELT".equals(source),watch="DEMO_WATCH".equals(source);
        boolean online=device.getBooleanValue("online")||"ONLINE".equals(device.getString("communication"));
        Set<String> verified=new HashSet<>(jdbc.query("SELECT feature_key FROM wearable_feature_acceptance WHERE device_id=?",(rs,n)->rs.getString(1),id));
        JSONObject result=new JSONObject();
        for(String key:Arrays.asList("battery","wear","hooks","height","location","alarm","sos","video","videoCall","photo","recording","voice","broadcast","vitals","doubleRelease","lowHook","proximity","temperature","rtk","indoorLocation")) {
            boolean base=Arrays.asList("battery","wear","location","alarm","sos").contains(key);
            boolean supported=(hat||belt)&&base || hat&&Arrays.asList("video","videoCall","photo","recording","voice","broadcast").contains(key)
                    || belt&&Arrays.asList("hooks","height","voice").contains(key) || watch&&Arrays.asList("battery","vitals").contains(key);
            boolean optional=belt&&Arrays.asList("doubleRelease","lowHook","proximity","temperature","rtk","indoorLocation").contains(key);
            boolean accepted=watch&&supported||verified.contains(key);
            if(belt&&"wear".equals(key))accepted=device.getBooleanValue("wearMappingConfirmed");
            if(belt&&"hooks".equals(key))accepted=accepted&&device.getBooleanValue("hookMappingConfirmed");
            boolean media=Arrays.asList("video","photo","recording").contains(key);
            boolean integrated=hat||belt||watch;
            if(media)integrated=hat&&device.getBooleanValue("mediaAvailable");
            if("voice".equals(key))integrated=hat&&device.getBooleanValue("voiceAvailable");
            if("videoCall".equals(key))integrated=hat&&device.getBooleanValue("voiceAvailable")&&device.getBooleanValue("mediaAvailable");
            if("broadcast".equals(key))integrated=hat&&device.getBooleanValue("broadcastAvailable");
            boolean fresh=online;
            if(belt&&Arrays.asList("wear","hooks","height").contains(key))fresh=online&&"CURRENT".equals(device.getString("telemetryFreshness"));
            boolean available=supported&&accepted&&integrated&&(watch||fresh);
            String reason=!supported?(optional?"选配未确认":"设备不支持") : belt&&"voice".equals(key)?"待接入" : !accepted?"待联调" : !integrated?"接入服务未就绪" : !watch&&!online?"设备离线" : !watch&&!fresh?"数据已过期或尚未上报" : watch?"模拟数据":"";
            result.put(key,object("supported",supported,"verified",accepted,"available",available,"reason",reason,"optional",optional,
                    "integrationStatus",integrated?"CONNECTED":"NOT_CONNECTED","verificationStatus",accepted?"VERIFIED":"PENDING"));
        }
        return result;
    }
    public void decorateDevice(JSONObject device){device.put("featureStates",features(device));device.put("simulated","DEMO_WATCH".equals(device.getString("source")));}
    /** Filtering affects only the read model; visibility changes never delete a simulation's history. */
    public JSONObject decorate(JSONObject state,boolean ledger) {
        JSONObject cfg=config();state.put("businessConfig",cfg);
        Set<String> hidden=new HashSet<>();JSONArray kept=new JSONArray();
        for(Object raw:rows(state,"devices")){JSONObject d=(JSONObject)raw;decorateDevice(d);if(!cfg.getBooleanValue("simulatedWatchVisible")&&d.getBooleanValue("simulated")){if(d.getString("id")!=null)hidden.add(d.getString("id"));if(d.getString("portalDeviceId")!=null)hidden.add(d.getString("portalDeviceId"));}else kept.add(d);}
        state.put("devices",kept);
        for(String key:Arrays.asList("bindings","assignments","assignmentHistory","history","vitals","events","locations")) {
            if(!(state.get(key) instanceof JSONArray))continue;
            JSONArray selected=new JSONArray();for(Object raw:rows(state,key)){JSONObject r=(JSONObject)raw;if(!hidden.contains(r.getString("deviceId"))&&!("events".equals(key)&&("DEMO_WATCH".equals(r.getString("source"))||r.getBooleanValue("demo"))))selected.add(r);}state.put(key,selected);
        }
        if(!cfg.getBooleanValue("simulatedWatchVisible")){JSONArray people=new JSONArray();for(Object raw:rows(state,"people")){JSONObject p=(JSONObject)raw;if(!"DEMO_WATCH".equals(p.getString("source")))people.add(p);}state.put("people",people);}
        return state;
    }
    public void require(JSONObject device,String feature,boolean acceptanceTest,GuardianAccess.Context ctx) {
        JSONObject state=features(device).getJSONObject(feature);
        if(state==null||!state.getBooleanValue("supported"))throw AdminQueryService.fail(409,"FEATURE_UNSUPPORTED","设备不支持此功能");
        if(!state.getBooleanValue("verified")&&!(acceptanceTest&&"demo-system".equals(ctx.id())))throw AdminQueryService.fail(409,"FEATURE_PENDING_ACCEPTANCE","此功能待联调验收，不能作为正式业务操作");
        if(!device.getBooleanValue("online")&&!"ONLINE".equals(device.getString("communication")))throw AdminQueryService.fail(409,"DEVICE_OFFLINE","设备离线，未下发操作");
        if(!"CONNECTED".equals(state.getString("integrationStatus")))throw AdminQueryService.fail(409,"FEATURE_NOT_CONNECTED","接入服务未就绪，未下发操作");
    }
}
