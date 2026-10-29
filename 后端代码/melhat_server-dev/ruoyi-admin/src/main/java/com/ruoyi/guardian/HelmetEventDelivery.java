package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/** Recovery across the SQL/file-store boundary. Never nests GuardianStore under an SQL transaction. */
@Service
public class HelmetEventDelivery {
    private final HelmetBusinessJournal journal;
    private final GuardianIngest ingest;
    private final GuardianStore store;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableMaintenance maintenance;
    public HelmetEventDelivery(HelmetBusinessJournal journal,GuardianIngest ingest,GuardianStore store) {
        this.journal=journal;this.ingest=ingest;this.store=store;
    }
    @Scheduled(fixedDelay=10000,initialDelay=15000)
    public void retry() {
        if(maintenance!=null && !maintenance.tryBeginWrite())return;
        try { HelmetEventLifecycle.coordinate(() -> { retryOrdered();return null; }); }
        finally { if(maintenance!=null)maintenance.endWrite(); }
    }
    private void retryOrdered() {
        try {
            for(JSONObject envelope:journal.pending()) {
                try { ingest.projectDirectEvent(envelope);journal.projected(envelope); }
                catch(RuntimeException error) { warn(); }
            }
            for(Object raw:WearableModel.rows(store.snapshot(),"events")) {
                JSONObject event=(JSONObject)raw;
                if("direct-helmet".equals(event.getString("protocol"))) synchronize(event);
            }
        } catch(RuntimeException error) { warn(); }
    }
    public void synchronize(JSONObject event) {
        try { journal.close(event); } catch(RuntimeException error) { warn(); }
    }
    /** Called under the lifecycle lock before accepting a new alarm. Fail closed on sync failure. */
    public void reconcileVerifiedBeforeAdmission() {
        java.util.List<String> open=journal.openEventIds();
        if(open.isEmpty()) return;
        JSONObject state=store.snapshot();
        for(String id:open) {
            JSONObject event=WearableModel.find(state,"events",id);
            if(event!=null) journal.close(event);
        }
    }
    private void warn() { org.slf4j.LoggerFactory.getLogger(getClass()).warn("安全帽事件同步暂未完成，将自动重试"); }
}
