package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import static com.ruoyi.guardian.WearableModel.object;

/** Persistent maintenance gate. Raw device journal reception is deliberately outside this gate. */
@Service
public class WearableMaintenance {
    private final JdbcTemplate jdbc;
    private final com.ruoyi.common.database.DatabaseDialect dialect;
    private int activeWrites;
    private final ThreadLocal<Integer> localDepth=ThreadLocal.withInitial(()->0);
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterWorkCoordinator coordinator;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterDatabase clusterDb;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.MediaOperationJournal journal;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.melhat.direct.HelmetCloudClient cloud;
    public JSONObject reconcile(String reason,JSONObject actor){requireSystem(actor);
        if(reason==null||reason.trim().length()<10||reason.length()>500)throw AdminQueryService.fail(400,"RECOVERY_REASON_REQUIRED","请填写至少10字且不超过500字的核对依据");
        if(!clustered())return status();
        if(!paused())throw AdminQueryService.fail(409,"RECOVERY_REQUIRES_PAUSE","先暂停全局业务，再核对失联操作");
        if(journal!=null&&cloud!=null&&cloud.configured())journal.reconcile(hash->cloud.request("GET","/operations/"+hash,null));
        coordinator.recoverAbandoned(actor.getString("id"),reason);return status();
    }
    private boolean clustered(){return coordinator!=null&&coordinator.enabled();}
    public WearableMaintenance(JdbcTemplate jdbc) {
        this.jdbc=jdbc;
        this.dialect = com.ruoyi.common.database.DatabaseDialect.of(jdbc);
        com.ruoyi.database.SchemaLifecycle.ensure(jdbc,"20261026_wearable_business");
        if(com.ruoyi.database.SchemaLifecycle.validateOnly(jdbc)) {
            if(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_runtime_control WHERE control_key='global'",Integer.class)!=1)
                throw new IllegalStateException("Maintenance control requires explicit initialization before validate-only startup");
            return;
        }
        dialect.insertIfAbsent(jdbc,"wearable_runtime_control",java.util.Arrays.asList("control_key","mode","updated_at","updated_by"),java.util.Arrays.asList("control_key"),"global","ACTIVE",System.currentTimeMillis(),null);
    }
    public boolean paused() { return !"ACTIVE".equals(jdbc.queryForObject("SELECT mode FROM wearable_runtime_control WHERE control_key='global'",String.class)); }
    public JSONObject status() {
        synchronized(WearableBusinessStore.transactionLock()) {
            boolean held=paused();
            JSONObject reports=jdbc.queryForObject("SELECT COALESCE(SUM(CASE WHEN processed_at IS NULL THEN 1 ELSE 0 END),0),COALESCE(MAX(sequence),0) FROM wearable_device_report",
                    (rs,n)->object("pendingReports",rs.getLong(1),"lastSequence",rs.getLong(2)));
            reports.put("mode",held?"PAUSED":"ACTIVE");reports.put("paused",held);
            if(clustered()) { reports.putAll(coordinator.status(false));reports.put("quiescent",held&&reports.getBooleanValue("quiescent")); }
            else {reports.put("activeWrites",activeWrites);reports.put("quiescent",held&&activeWrites==0);reports.put("draining",held&&activeWrites>0);}
            return reports;
        }
    }
    public static void requireSystem(JSONObject actor) {
        if(actor==null || !"demo-system".equals(actor.getString("id")))
            throw AdminQueryService.fail(403,"PERMISSION_DENIED","仅系统管理员可以管理维护模式");
    }
    public synchronized JSONObject setPaused(boolean held,JSONObject actor) {
        requireSystem(actor);
        if(clustered()) {clusterDb.locked(()->{jdbc.update("UPDATE wearable_runtime_control SET mode=?,updated_at=?,updated_by=? WHERE control_key='global'",held?"PAUSED":"ACTIVE",clusterDb.now(),actor.getString("id"));return null;});return status();}
        synchronized(WearableBusinessStore.transactionLock()) {
            jdbc.update("UPDATE wearable_runtime_control SET mode=?,updated_at=?,updated_by=? WHERE control_key='global'",held?"PAUSED":"ACTIVE",System.currentTimeMillis(),actor.getString("id"));
            if(held) {
                long deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(30);
                while(activeWrites>0) {
                    long remaining=deadline-System.nanoTime();
                    if(remaining<=0)throw AdminQueryService.fail(503,"MAINTENANCE_DRAINING","维护模式已开启，仍在等待当前操作结束，请查询维护状态");
                    try { java.util.concurrent.TimeUnit.NANOSECONDS.timedWait(WearableBusinessStore.transactionLock(),remaining); }
                    catch(InterruptedException error){Thread.currentThread().interrupt();throw AdminQueryService.fail(503,"MAINTENANCE_DRAINING","维护模式已开启，请查询维护状态");}
                }
            }
            return status();
        }
    }
    /** A lease covers the whole existing operation without introducing lock-order inversions. */
    public boolean tryBeginWrite() {
        if(clustered()) {try{coordinator.begin("BUSINESS");return true;}catch(AdminQueryService.QueryFailed e){if("MAINTENANCE_PAUSED".equals(e.errorCode))return false;throw e;}}
        synchronized(WearableBusinessStore.transactionLock()) { if(paused())return false;activeWrites++;localDepth.set(localDepth.get()+1);return true; }
    }
    public void beginWrite() { if(!tryBeginWrite())throw AdminQueryService.fail(503,"MAINTENANCE_PAUSED","系统正在维护，业务写入暂时停止，请稍后重试"); }
    public void endWrite() {
        if(clustered()){coordinator.end();return;}
        synchronized(WearableBusinessStore.transactionLock()) { if(localDepth.get()<=0)throw new IllegalStateException("No write permit belongs to this thread");localDepth.set(localDepth.get()-1);activeWrites--;WearableBusinessStore.transactionLock().notifyAll(); }
    }
    public static boolean isBusinessWrite(String method,String path) {
        if("GET".equals(method)||"HEAD".equals(method)||"OPTIONS".equals(method))return false;
        if("/api/admin/v1/maintenance".equals(path)||"/api/admin/v1/maintenance/reconcile".equals(path))return false;
        if("POST".equals(method)) {
            if("/api/admin/v1/query".equals(path))return false;
            for(String prefix:new String[]{"/api/admin/v1/","/api/guardian/v1/","/api/guardian/v1/mobile/"})
                if((prefix+"login").equals(path)||(prefix+"logout").equals(path))return false;
        }
        return true;
    }
}
