package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.DirectHelmetMessage;
import com.ruoyi.melhat.direct.DirectHelmetTelemetryService;
import com.ruoyi.melhat.direct.HelmetMediaService;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.object;

/** Durable reception precedes acknowledgement. Recovery retains the received time and ownership. */
@Service
public class WearableReportDelivery {
    private final WearableBusinessStore journal;
    private final GuardianIngest ingest;
    private final ObjectProvider<DirectHelmetTelemetryService> helmets;
    private final ObjectProvider<DirectBeltTelemetryService> belts;
    private final Object recoveryLock=new Object();
    @org.springframework.beans.factory.annotation.Autowired(required=false) private ObjectProvider<HelmetMediaService> media;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableMaintenance maintenance;
    public WearableReportDelivery(WearableBusinessStore journal,GuardianIngest ingest,ObjectProvider<DirectHelmetTelemetryService> helmets,ObjectProvider<DirectBeltTelemetryService> belts){this.journal=journal;this.ingest=ingest;this.helmets=helmets;this.belts=belts;}
    public boolean helmet(String deviceId,String raw){return HelmetEventLifecycle.coordinate(()->{synchronized(WearableBusinessStore.transactionLock()){
        JSONObject context=ingest.captureDirect(deviceId);context.put("receivedAt",Instant.now().toString());
        SafetyHatInfo device=helmets.getObject().registered(deviceId);if(device==null)throw new IllegalStateException("设备登记已变化");context.put("rawUserId",device.getBindUserId());context.put("rawUserName",device.getBindUserName());
        return receive("direct-helmet",deviceId,object("raw",JSONObject.parseObject(raw),"context",context));
    }});}
    public boolean belt(String deviceId,String raw,JSONObject status,String rawType,String timestamp,boolean sos){synchronized(WearableBusinessStore.transactionLock()){
        return receive("direct-belt",deviceId,object("raw",JSONObject.parseObject(raw),"context",ingest.captureBelt(deviceId),"status",status,"rawType",rawType,"timestamp",timestamp,"sos",sos));
    }}
    public boolean paused(){return maintenance!=null&&maintenance.paused();}
    /** Media acknowledgements are durable even while maintenance or media processing is unavailable. */
    public void helmetMedia(String deviceId,String raw) {
        JSONObject message=JSONObject.parseObject(raw);
        if(!java.util.Arrays.asList("ca_upload_photo","upload_video_success","push_to_client").contains(message.getString("act")))
            throw new IllegalArgumentException("未知的设备媒体回执");
        synchronized(WearableBusinessStore.transactionLock()) {
            journal.appendDeviceReport("WR-"+UUID.randomUUID(),"direct-helmet-media",deviceId,
                    object("raw",message,"receivedAt",Instant.now().toString()));
        }
        // Never acquire the media service's monitor while holding the business or lifecycle lock.
        // The receiver acknowledges persistence; failures below stay pending for ordered recovery.
        recover();
    }
    private boolean receive(String protocol,String deviceId,JSONObject payload){String receipt="WR-"+UUID.randomUUID();journal.appendDeviceReport(receipt,protocol,deviceId,payload);if(paused())return false;deliver(object("receiptId",receipt,"protocol",protocol,"deviceId",deviceId,"payload",payload));return true;}
    void deliver(JSONObject report){
        String receipt=report.getString("receiptId"),deviceId=report.getString("deviceId"),protocol=report.getString("protocol");JSONObject payload=report.getJSONObject("payload");
        if("direct-helmet".equals(protocol))HelmetEventLifecycle.coordinate(()->{synchronized(WearableBusinessStore.transactionLock()){if(paused())return false;return journal.processReport(receipt,()->{
            DirectHelmetTelemetryService service=helmets.getObject();SafetyHatInfo device=service.registered(deviceId);
            if(device==null)throw new IllegalStateException("待恢复报文的设备登记需要核对");
            service.receiveCaptured(device,DirectHelmetMessage.parse(payload.getJSONObject("raw").toJSONString()),payload.getJSONObject("context"));
        });}});
        else if("direct-belt".equals(protocol)){synchronized(WearableBusinessStore.transactionLock()){if(!paused())journal.processReport(receipt,()->belts.getObject().receiveCaptured(deviceId,payload.getJSONObject("status"),payload.getString("rawType"),payload.getString("timestamp"),payload.getBooleanValue("sos"),payload.getJSONObject("context")));}}
        else if("direct-helmet-media".equals(protocol)) {
            if(media==null)throw new IllegalStateException("媒体回执处理服务尚未就绪");
            HelmetMediaService service=media.getObject();
            // All existing media commands acquire this monitor before the SQL/business lock.
            synchronized(service) { synchronized(WearableBusinessStore.transactionLock()) {
                if(paused())return;
                journal.processReport(receipt,()->{
                    if(!service.receipt(deviceId,payload.getJSONObject("raw"),payload.getString("receivedAt")))throw new IllegalArgumentException("媒体回执与设备指令不匹配");
                });
            }}
        } else throw new IllegalArgumentException("未知的设备接收协议");
    }
    @Scheduled(fixedDelay=10000,initialDelay=10000) public void recover(){
        synchronized(recoveryLock) {
            if(paused())return;
            boolean mediaBlocked=false;
            for(JSONObject report:journal.pendingReports(0,100)) {
                boolean mediaReport="direct-helmet-media".equals(report.getString("protocol"));
                if(mediaReport&&mediaBlocked)continue;
                try{deliver(report);}catch(RuntimeException error){
                    if(mediaReport)mediaBlocked=true;
                    org.slf4j.LoggerFactory.getLogger(getClass()).warn("设备接收记录等待恢复，receiptId={},errorType={}",report.getString("receiptId"),error.getClass().getSimpleName());
                }
            }
        }
    }
}
