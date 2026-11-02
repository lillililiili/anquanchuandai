package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.belt.DirectBeltMessage;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import com.ruoyi.melhat.direct.DirectHelmetMessage;
import com.ruoyi.melhat.direct.DirectHelmetProperties;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import java.time.*;
import java.util.*;
import static com.ruoyi.fuda.FudaMapping.*;

/** Capture an immutable public projection while the source SQL transaction is still open. */
@Component
public class FudaPushCapture {
    private final JdbcTemplate jdbc;
    private final FudaPushOutbox outbox;
    private final FudaPushProperties push;
    private final FudaProperties query;
    private final DirectHelmetProperties helmets;
    private final DirectBeltProperties belts;
    private final Clock clock;
    private final ThreadLocal<String> applyingReceiptDevice=new ThreadLocal<>();

    public FudaPushCapture(JdbcTemplate jdbc, FudaPushOutbox outbox, FudaPushProperties push, FudaProperties query,
            DirectHelmetProperties helmets, DirectBeltProperties belts, @Qualifier("fudaClock") Clock clock) {
        this.jdbc=jdbc; this.outbox=outbox; this.push=push; this.query=query; this.helmets=helmets; this.belts=belts; this.clock=clock;
    }

    public boolean enabled() { return push.isEnabled(); }

    /** Restoring receipt telemetry must not masquerade as a new physical socket connection. */
    public void duringReceipt(String deviceId,Runnable apply) {
        String previous=applyingReceiptDevice.get();
        try { applyingReceiptDevice.set(deviceId); apply.run(); }
        finally { if(previous==null)applyingReceiptDevice.remove();else applyingReceiptDevice.set(previous); }
    }

    /** Direct SQL avoids calling the mutable ledger reader while holding the business transaction lock. */
    private JSONObject authorized(String type, String id) {
        Set<String> allowed=push.getAllowedLedgerDeviceIds();
        if (!push.isEnabled() || allowed==null || allowed.isEmpty() || id==null) return null;
        List<JSONObject> rows=jdbc.query("SELECT body FROM wearable_device WHERE id IN ("
                +String.join(",",Collections.nCopies(allowed.size(),"?"))+")", (rs,n)->JSONObject.parseObject(rs.getString(1)), allowed.toArray());
        JSONObject found=null;
        for(JSONObject row:rows) {
            String mapped="DIRECT_HELMET".equals(row.getString("source"))&&"HELMET".equals(row.getString("type"))?"HELMET"
                    :"DIRECT_BELT".equals(row.getString("source"))&&"BELT".equals(row.getString("type"))?"SAFETY_BELT":null;
            if (!type.equals(mapped)||simulated(row)||!allowed.contains(row.getString("id"))
                    ||!id.equals(row.getString("deviceNumber"))||!id.equals(row.getString("portalDeviceId"))) continue;
            if(found!=null) return null;
            found=row;
        }
        return found;
    }

    public boolean maySend(FudaPushOutbox.Delivery delivery) {
        JSONObject row=authorized(delivery.deviceType,delivery.deviceId);
        return row!=null && delivery.ledgerId.equals(row.getString("id"));
    }

    public Map<String,JSONObject> previousDevices() {
        Map<String,JSONObject> result=new HashMap<>();
        if(enabled()) jdbc.query("SELECT record_key,body FROM wearable_device_state WHERE namespace='guardian' AND collection_key='devices'",
                rs->{result.put(rs.getString(1),JSONObject.parseObject(rs.getString(2)));});
        return result;
    }

    /** A successfully applied receipt produces exactly one status and, if newly observed, one position. */
    public void receipt(String receiptId, JSONObject receipt) {
        if(!enabled())return;
        String protocol=receipt.getString("protocol"), id=receipt.getString("deviceId");
        String type="direct-helmet".equals(protocol)?"HELMET":"direct-belt".equals(protocol)?"SAFETY_BELT":null;
        if(type==null)return; // Media receipts are internal and must never leak into the public contract.
        JSONObject ledger=authorized(type,id); if(ledger==null)return;
        JSONObject payload=receipt.getJSONObject("payload"), context=payload.getJSONObject("context");
        JSONObject device=context==null?null:context.getJSONObject("device");
        if(device==null||simulated(device)||!id.equals(device.getString("id"))
                ||!ledger.getString("source").equals(device.getString("source")))return;
        JSONObject telemetry=JSONObject.parseObject(device.toJSONString());
        String at=context==null?null:time(context.get("receivedAt"));
        if(at==null)at=Instant.ofEpochMilli(receipt.getLongValue("receivedMillis")).toString();
        JSONObject raw=payload.getJSONObject("raw"); if(raw==null)return;
        boolean newLocation;
        if("HELMET".equals(type)) {
            DirectHelmetMessage message=DirectHelmetMessage.parse(raw.toJSONString());
            if(!Arrays.asList("ca_report_location","ca_sos","ca_sip_sos").contains(message.act))return;
            if("ca_report_location".equals(message.act)) {
                observed(telemetry,"battery",message.battery,at); observed(telemetry,"isWeared",message.isWeared,at);
                observed(telemetry,"networkType",message.networkType,at); observed(telemetry,"networkStrength",message.networkStrength,at);
                if(message.firmware!=null)telemetry.put("firmware",message.firmware);
            }
            newLocation="ca_report_location".equals(message.act)&&message.hasLocation();
            if(newLocation) {
                telemetry.put("longitude",message.longitude); telemetry.put("latitude",message.latitude);
                telemetry.put("coordinateSystem","UNKNOWN"); telemetry.put("locationQuality","unknown");
                telemetry.put("locationSource",message.locationSource); telemetry.put("accuracyMeters",message.accuracyMeters);
                telemetry.put("locationReportedAt",at); telemetry.put("locationFreshness","CURRENT");
            }
        } else {
            DirectBeltMessage message=DirectBeltMessage.parse(raw.toJSONString());
            JSONObject status=payload.getJSONObject("status"); if(status==null)return;
            telemetry.putAll(status);
            if(time(status.get("lastSeenAt"))!=null)at=time(status.get("lastSeenAt"));
            newLocation="ca_report_location".equals(message.act)&&message.hasLocation();
        }
        // This is the state observed at reception, not a claim that a replayed socket is online now.
        telemetry.put("online",true); telemetry.put("lastSeenAt",at);
        applyLocationProfile(telemetry,query.getLocationProfiles().get(ledger.getString("id")));
        Clock observedClock=Clock.fixed(Instant.parse(at),ZoneOffset.UTC);
        emit(ledger,type,id,"STATUS","REPORT",receiptId,at,
                statusItem(base(ledger,type,id),telemetry,timeout(type),belts,observedClock));
        if(newLocation)emit(ledger,type,id,"POSITION","REPORT",receiptId,at,
                positionItem(base(ledger,type,id),telemetry,timeout(type),observedClock));
    }

    public void saved(JSONObject state, Map<String,JSONObject> previous, Set<String> previousEventIds, boolean historical) {
        if(!enabled()||historical)return; // No implicit historical bulk push when first importing a database.
        JSONArray devices=state.getJSONArray("devices");
        if(devices!=null)for(Object raw:devices) {
            JSONObject device=(JSONObject)raw; if(simulated(device))continue;
            String type="DIRECT_HELMET".equals(device.getString("source"))?"HELMET":"DIRECT_BELT".equals(device.getString("source"))?"SAFETY_BELT":null;
            if(type==null)continue;
            String id=device.getString("id"); JSONObject prior=previous.get(id);
            boolean online=device.getBooleanValue("online");
            // A replay can restore captured online=true. Offline projections still reflect the
            // live session and must be exported, including the first reconciliation after restart.
            if(online&&Objects.equals(applyingReceiptDevice.get(),id))continue;
            if(prior!=null&&prior.getBooleanValue("online")==online || prior==null&&!online)continue;
            JSONObject ledger=authorized(type,id); if(ledger==null)continue;
            JSONObject value=new JSONObject(device);
            if(Arrays.asList("DISABLED","SCRAPPED").contains(ledger.getString("lifecycle"))||device.containsKey("active")&&!device.getBooleanValue("active"))value.put("online",false);
            String trigger=value.getBooleanValue("online")?"ONLINE":"OFFLINE";
            emit(ledger,type,id,"STATUS",trigger,"presence:"+UUID.randomUUID(),now(clock),
                    statusItem(base(ledger,type,id),value,timeout(type),belts,clock));
        }
        JSONArray events=state.getJSONArray("events");
        if(events!=null)for(Object raw:events) {
            JSONObject event=(JSONObject)raw; String id=event.getString("id");
            if(id==null||previousEventIds.contains(id))continue;
            // The journal decides what is a real, immutable first alarm. Do not reimplement alarm classification.
            List<JSONObject> rows=jdbc.query("SELECT body FROM fuda_alarm_journal WHERE event_hash=?",(rs,n)->JSONObject.parseObject(rs.getString(1)),FudaPushOutbox.hash(id));
            if(rows.size()!=1||!id.equals(rows.get(0).getString("eventId")))continue;
            JSONObject row=rows.get(0); String type=row.getString("deviceType"),deviceId=row.getString("deviceId");
            JSONObject ledger=authorized(type,deviceId); if(ledger==null)continue;
            emit(ledger,type,deviceId,"ALARM","ALARM",id,time(row.get("occurredAt")),alarm(query.getSourcePlatform(),row));
        }
    }

    private JSONObject base(JSONObject ledger,String type,String id) {
        String model=text(ledger,"deviceModel"); if(model==null)model=text(ledger,"model"); if(model==null)model=text(ledger,"modelName");
        return common(query.getSourcePlatform(),type,id,model);
    }
    private int timeout(String type) { return "HELMET".equals(type)?helmets.getHeartbeatTimeoutSeconds():belts.getHeartbeatTimeoutSeconds(); }
    private static void observed(JSONObject target,String field,Object value,String at) {
        if(value!=null) { target.put(field,value); target.put(field+"ReportedAt",at); target.put(field+"Freshness","CURRENT"); }
    }
    private void emit(JSONObject ledger,String type,String id,String kind,String trigger,String sourceId,String occurred,JSONObject data) {
        String eventId="FP-"+FudaPushOutbox.hash(push.getDestinationId()+"\n"+kind+"\n"+sourceId);
        JSONObject envelope=object("schemaVersion","1.0","eventId",eventId,"eventType",kind,"trigger",trigger,
                "occurredAt",time(occurred),"createdAt",now(clock),"data",data);
        outbox.enqueue(push.getDestinationId(),ledger.getString("id"),type,id,envelope,clock.millis());
    }
}
