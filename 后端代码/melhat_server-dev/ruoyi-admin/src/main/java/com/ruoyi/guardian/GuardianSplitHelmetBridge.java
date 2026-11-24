package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.split.SplitHelmetBridge;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;

/** Converts only registered split-helmet observations into the existing business model. */
@Component
public class GuardianSplitHelmetBridge implements SplitHelmetBridge {
    private final AdminLedgerStore ledger;
    private final GuardianIngest ingest;
    private final GuardianStore store;
    private final HelmetBusinessJournal journal;
    private final HelmetEventDelivery delivery;
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    public GuardianSplitHelmetBridge(AdminLedgerStore ledger,GuardianIngest ingest,GuardianStore store,
            HelmetBusinessJournal journal,HelmetEventDelivery delivery,JdbcTemplate jdbc) {
        this.ledger=ledger;this.ingest=ingest;this.store=store;this.journal=journal;this.delivery=delivery;this.jdbc=jdbc;
        transaction=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
    }
    public List<String> registered() {
        JSONObject state=ledger.read();List<String> result=new ArrayList<>();
        for(Object raw:rows(state,"devices")) {
            JSONObject device=(JSONObject)raw,site=find(state,"sites",device.getString("siteId"));
            if("SPLIT_HELMET".equals(device.getString("source"))&&"HELMET".equals(device.getString("type"))
                    &&!Arrays.asList("DISABLED","SCRAPPED").contains(device.getString("lifecycle"))
                    &&site!=null&&site.getBooleanValue("enabled"))result.add(device.getString("deviceNumber"));
        }
        return result;
    }
    public boolean isRegistered(String sn) {return sn!=null&&registered().contains(sn);}
    public boolean ownsIdentity(String sn) {
        if(sn==null)return false;
        for(Object raw:rows(ledger.read(),"devices")){JSONObject device=(JSONObject)raw;
            if("SPLIT_HELMET".equals(device.getString("source"))&&sn.equals(device.getString("deviceNumber")))return true;}
        return false;
    }
    public JSONObject captureFile(String sn,String observedAt) {
        return historicalContext(ledger.read(),sn,observedAt);
    }
    /** A directory timestamp is evidence of a file's interval, never proof of who operated its camera. */
    static JSONObject historicalContext(JSONObject state,String sn,String observedAt) {
        final Instant at;
        try {at=Instant.parse(observedAt);if(at.isAfter(Instant.now()))return null;}catch(RuntimeException invalid){return null;}
        JSONObject device=null;
        for(Object raw:rows(state,"devices")) {JSONObject d=(JSONObject)raw;
            if("SPLIT_HELMET".equals(d.getString("source"))&&Objects.equals(sn,d.getString("deviceNumber"))){if(device!=null)return null;device=d;}}
        if(device==null)return null;
        JSONObject matched=null;
        for(Object raw:rows(state,"assignments")) {JSONObject a=(JSONObject)raw;
            if(!Objects.equals(device.getString("id"),a.getString("deviceId")))continue;
            try {
                if(at.isBefore(Instant.parse(a.getString("startedAt")))||a.get("endedAt")!=null&&!at.isBefore(Instant.parse(a.getString("endedAt"))))continue;
                if(a.get("endedAt")==null&&!a.getBooleanValue("active"))continue;
                if(matched!=null)return null;matched=a;
            }catch(RuntimeException invalid){return null;}
        }
        if(matched==null)return null;
        JSONObject issue=null;
        for(Object raw:rows(state,"history")) {JSONObject h=(JSONObject)raw;
            if("ISSUE".equals(h.getString("action"))&&Objects.equals(matched.getString("id"),h.getString("assignmentId"))){if(issue!=null)return null;issue=h;}}
        if(issue==null||issue.getString("siteId")==null)return null;
        String personId=issue.getString("personPortalId");
        if(personId==null){JSONObject p=find(state,"people",issue.getString("personId"));if(p!=null)personId=p.getString("portalId");}
        if(personId==null)return null;
        int version=issue.getIntValue("assignmentVersion");if(version<1)version=1;
        return object("siteId",issue.get("siteId"),"areaId",issue.get("personAreaId"),"personId",personId,
                "personName",issue.get("personName"),"assignmentId",matched.get("id"),"assignmentVersion",version,
                "ledgerDeviceId",device.get("id"),"bindingId","BIND-"+matched.getString("id")+"-"+version,
                "bindingStart",matched.get("startedAt"),"bindingEnd",matched.get("endedAt"),"timeBasis","FILE_LAST_MODIFIED");
    }
    public JSONObject capture(String sn,String receivedAt) {
        synchronized(ledger) {
            if(!isRegistered(sn))throw new IllegalArgumentException("分体帽未登记或已停用");
            JSONObject captured=ingest.captureSplit(sn);captured.put("capturedAt",receivedAt);return captured;
        }
    }
    public void ingest(JSONObject envelope) {
        String kind=envelope.getString("kind");JSONObject payload=envelope.getJSONObject("payload");
        JSONObject captured=copy(envelope.getJSONObject("captured"));
        if(captured==null||captured.getJSONObject("device")==null||!"SPLIT_HELMET".equals(captured.getJSONObject("device").getString("source")))
            throw new IllegalArgumentException("分体帽上报缺少原始归属");
        String observed=envelope.getString("observedAt");if(observed==null)observed=envelope.getString("receivedAt");
        // A delayed pre-issue sample must never be attributed to the new wearer.
        if(outsideBinding(captured,observed)) {
            captured.put("personId","");captured.put("personName","归属待核对");captured.put("person",null);captured.put("work",null);
            captured.put("bindingId",null);captured.put("bindingStart",null);captured.put("bindingEnd",null);
            JSONObject historical=captureFile(envelope.getString("deviceId"),observed);
            if(historical!=null) {
                captured.putAll(historical);captured.remove("timeBasis");
                captured.put("person",object("id",historical.get("personId"),"name",historical.get("personName"),"siteId",historical.get("siteId"),"areaId",historical.get("areaId")));
            }
        }
        if("gnss".equals(kind))location(envelope,captured,payload,observed);
        else if("sosCall".equals(kind)||"sos".equals(kind))event(envelope,captured,payload,observed);
        else if("sosCallEnd".equals(kind))ended(envelope);
        // Current telemetry is persisted by SplitTelemetry. It is read through SplitHelmetProjection.
    }
    private static boolean outsideBinding(JSONObject captured,String at) {
        try {
            Instant observed=Instant.parse(at);
            return captured.get("bindingStart")!=null&&observed.isBefore(Instant.parse(captured.getString("bindingStart")))
                    ||captured.get("bindingEnd")!=null&&!observed.isBefore(Instant.parse(captured.getString("bindingEnd")));
        }catch(RuntimeException error){return true;}
    }
    private void location(JSONObject envelope,JSONObject captured,JSONObject payload,String observed) {
        JSONObject point=copy(captured);
        String id="SL-"+UUID.nameUUIDFromBytes(envelope.getString("ingressId").getBytes(java.nio.charset.StandardCharsets.UTF_8));
        point.putAll(object("id",id,"deviceId",envelope.getString("deviceId"),"source","split-helmet",
                "longitude",payload.get("longitude"),"latitude",payload.get("latitude"),"speed",payload.get("speed"),"altitude",payload.get("altitude"),
                "receivedAt",envelope.get("receivedAt"),"receivedMillis",envelope.get("receivedMillis"),
                "collectedAt",observed,"collectedMillis",Instant.parse(observed).toEpochMilli(),"locationReportedAt",observed,
                "deviceReportedAt",payload.get("timestamp"),"coordinateSystem","WGS84","locationSource","GNSS",
                "locationQuality","valid","locationTimeBasis",payload.get("timestamp")==null||envelope.get("timeAnomaly")!=null?"RECEIVED_AT":"DEVICE_COLLECTED_AT",
                "clockAnomaly",envelope.get("timeAnomaly")));
        if(!PersonLocationProjection.coordinates(point))throw new IllegalArgumentException("定位坐标无效");
        journal.offlineLocation(point);
        ingest.directLocation(point);
    }
    private void event(JSONObject envelope,JSONObject captured,JSONObject payload,String observed) {
        HelmetEventLifecycle.coordinate(()->{
            delivery.reconcileVerifiedBeforeAdmission();
            JSONObject report=copy(captured);String type="sosCall".equals(envelope.getString("kind"))?"sos":payload.getString("type");
            report.putAll(object("protocol","split-helmet","deviceId",envelope.getString("deviceId"),
                    "act","sos".equals(type)?"split_sos":"split_alarm","rawType",type,"payload",copy(payload),
                    "observedAt",observed,"deviceReportedAt",payload.get("timestamp"),
                    "receivedAt",envelope.get("receivedAt"),"receivedMillis",envelope.get("receivedMillis"),"sourceRecordType","split_helmet_event"));
            JSONObject device=captured.getJSONObject("device");
            for(String field:Arrays.asList("longitude","latitude","coordinateSystem","locationQuality","locationReportedAt","locationSource","accuracyMeters"))report.put(field,device.get(field));
            transaction.execute(tx->{
                String ingressId=envelope.getString("ingressId");
                jdbc.update("INSERT INTO split_helmet_event (ingress_id,body,handled) VALUES (?,?,0) ON DUPLICATE KEY UPDATE ingress_id=ingress_id",ingressId,report.toJSONString());
                Long rawId=jdbc.queryForObject("SELECT id FROM split_helmet_event WHERE ingress_id=?",Long.class,ingressId);
                report.put("sourceRecordId",rawId);journal.event(report);return null;
            });
            ingest.projectDirectEvent(report);journal.projected(report);return null;
        });
    }
    private void ended(JSONObject envelope) {
        store.update(state->{
            boolean changed=false;
            for(Object raw:rows(state,"events")) {
                JSONObject event=(JSONObject)raw;
                if(!"split-helmet".equals(event.getString("protocol"))||!"sos".equals(event.getString("rawAlarmType"))
                        ||!Objects.equals(event.getString("deviceId"),envelope.getString("deviceId"))||"已核验".equals(event.getString("status")))continue;
                try {if(event.getString("observedAt")!=null&&Instant.parse(envelope.getString("observedAt")).isBefore(Instant.parse(event.getString("observedAt"))))continue;}
                catch(RuntimeException invalid){continue;}
                if(event.get("deviceCallEndedAt")!=null)continue;
                event.put("deviceCallEndedAt",envelope.get("receivedAt"));
                rows(event,"timeline").add(object("time",envelope.get("receivedAt"),"text","设备报告结束呼叫；告警仍需单独核验"));
                event.put("version",event.getIntValue("version")+1);changed=true;
            }
            if(changed)state.put("seq",state.getIntValue("seq")+1);return changed;
        });
    }
}
