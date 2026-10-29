package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.GuardianIngest;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.springframework.stereotype.Service;
import java.util.List;

/** Commit database records before publishing to the separately locked guardian snapshot. */
@Service
public class DirectHelmetTelemetryService {
    private final SafetyHatInfoMapper hats;
    private final DirectHelmetPersistence persistence;
    private final GuardianIngest ingest;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private com.ruoyi.guardian.HelmetBusinessJournal journal;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private DirectHelmetLocationProfiles profiles;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private com.ruoyi.guardian.HelmetEventDelivery eventDelivery;

    public DirectHelmetTelemetryService(SafetyHatInfoMapper hats, DirectHelmetPersistence persistence,
            GuardianIngest ingest) {
        this.hats = hats; this.persistence = persistence; this.ingest = ingest;
    }

    public SafetyHatInfo registered(String deviceId) {
        if (deviceId == null || deviceId.isEmpty()) return null;
        List<SafetyHatInfo> records = hats.findIncludingDeleted(deviceId);
        if (records == null || records.size() != 1) return null;
        SafetyHatInfo hat = records.get(0);
        return hat != null && "0".equals(hat.getDelFlag()) && "direct-helmet".equals(hat.getCreateBy()) ? hat : null;
    }

    public void connection(SafetyHatInfo hat, boolean online) { persistence.connection(hat, online); }

    public void receive(SafetyHatInfo hat, DirectHelmetMessage message) {
        receiveCaptured(hat,message,null);
    }
    public void receiveCaptured(SafetyHatInfo hat,DirectHelmetMessage message,JSONObject context){
        if("ca_sos".equals(message.act) || "ca_sip_sos".equals(message.act)) {
            com.ruoyi.guardian.HelmetEventLifecycle.coordinate(() -> {
                if(eventDelivery!=null) eventDelivery.reconcileVerifiedBeforeAdmission();
                receiveCommitted(hat,message,context);return null;
            });
        } else receiveCommitted(hat,message,context);
    }

    private void receiveCommitted(SafetyHatInfo hat, DirectHelmetMessage message,JSONObject context) {
        // The injected persistence service is a transactional proxy. Returning means commit completed.
        JSONObject result = persistence.receive(hat, message, context==null?ingest.captureDirect(hat.getHatNumber()):context);
        if ("ca_report_location".equals(message.act) && message.hasLocation()) {
            ingest.directLocation(result);
        } else if (result.getString("eventId") != null) {
            // The durable journal will retry if the separately persisted projection fails.
            try {
                ingest.projectDirectEvent(result);
                if(journal!=null) journal.projected(result);
            } catch(RuntimeException error) {
                if(journal==null) throw error;
                org.slf4j.LoggerFactory.getLogger(getClass()).warn("安全帽告警已保存，等待业务事件重试");
            }
        }
    }

    public JSONObject enrichStatus(String deviceId, JSONObject status) {
        if(profiles!=null) profiles.apply(deviceId,status);
        return status;
    }
    public void snapshot(String deviceId, JSONObject status) { ingest.directTelemetry(deviceId, enrichStatus(deviceId,status)); }
}
