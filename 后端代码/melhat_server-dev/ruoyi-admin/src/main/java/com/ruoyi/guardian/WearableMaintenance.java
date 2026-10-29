package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import static com.ruoyi.guardian.WearableModel.object;

/** Persistent maintenance gate. Raw device journal reception is deliberately outside this gate. */
@Service
public class WearableMaintenance {
    private final JdbcTemplate jdbc;
    private int activeWrites;
    public WearableMaintenance(JdbcTemplate jdbc) {
        this.jdbc=jdbc;
        jdbc.execute("CREATE TABLE IF NOT EXISTS wearable_runtime_control (control_key VARCHAR(32) PRIMARY KEY, mode VARCHAR(16) NOT NULL, updated_at BIGINT NOT NULL, updated_by VARCHAR(128))");
        jdbc.update("INSERT INTO wearable_runtime_control (control_key,mode,updated_at,updated_by) VALUES ('global','ACTIVE',?,NULL) ON DUPLICATE KEY UPDATE control_key=control_key",System.currentTimeMillis());
    }
    public boolean paused() { return !"ACTIVE".equals(jdbc.queryForObject("SELECT mode FROM wearable_runtime_control WHERE control_key='global'",String.class)); }
    public JSONObject status() {
        synchronized(WearableBusinessStore.transactionLock()) {
            boolean held=paused();
            JSONObject reports=jdbc.queryForObject("SELECT COALESCE(SUM(CASE WHEN processed_at IS NULL THEN 1 ELSE 0 END),0),COALESCE(MAX(sequence),0) FROM wearable_device_report",
                    (rs,n)->object("pendingReports",rs.getLong(1),"lastSequence",rs.getLong(2)));
            reports.put("mode",held?"PAUSED":"ACTIVE");reports.put("paused",held);
            reports.put("activeWrites",activeWrites);reports.put("quiescent",held&&activeWrites==0);
            return reports;
        }
    }
    public static void requireSystem(JSONObject actor) {
        if(actor==null || !"demo-system".equals(actor.getString("id")))
            throw AdminQueryService.fail(403,"PERMISSION_DENIED","仅系统管理员可以管理维护模式");
    }
    public synchronized JSONObject setPaused(boolean held,JSONObject actor) {
        requireSystem(actor);
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
        synchronized(WearableBusinessStore.transactionLock()) { if(paused())return false;activeWrites++;return true; }
    }
    public void beginWrite() { if(!tryBeginWrite())throw AdminQueryService.fail(503,"MAINTENANCE_PAUSED","系统正在维护，业务写入暂时停止，请稍后重试"); }
    public void endWrite() {
        synchronized(WearableBusinessStore.transactionLock()) { if(activeWrites>0)activeWrites--;WearableBusinessStore.transactionLock().notifyAll(); }
    }
    public static boolean isBusinessWrite(String method,String path) {
        if("GET".equals(method)||"HEAD".equals(method)||"OPTIONS".equals(method))return false;
        if("/api/admin/v1/maintenance".equals(path))return false;
        if("POST".equals(method)) {
            if("/api/admin/v1/query".equals(path))return false;
            for(String prefix:new String[]{"/api/admin/v1/","/api/guardian/v1/","/api/guardian/v1/mobile/"})
                if((prefix+"login").equals(path)||(prefix+"logout").equals(path))return false;
        }
        return true;
    }
}
