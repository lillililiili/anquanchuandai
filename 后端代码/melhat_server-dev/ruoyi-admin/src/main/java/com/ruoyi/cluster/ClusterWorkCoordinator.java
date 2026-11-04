package com.ruoyi.cluster;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.guardian.AdminQueryService;
import org.springframework.stereotype.Component;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Supplier;

/** DB-time leases coordinate work; SQL fencing and durable effect claims provide the safety boundary.
 * Lock order: cluster control -> work/permit -> receipt/business meta -> ledger meta -> related SQL.
 * Never keep this transaction open while calling a device, cloud service or another JVM. */
@Component
public class ClusterWorkCoordinator {
    private final ClusterDatabase db; private final ClusterIdentity identity;
    private final ThreadLocal<Boolean> recovery=ThreadLocal.withInitial(()->false);
    private final ThreadLocal<WorkToken> current=new ThreadLocal<>();
    private final ThreadLocal<List<WorkToken>> heldWork=ThreadLocal.withInitial(ArrayList::new);
    private final ThreadLocal<Deque<OperationPermit>> operations=ThreadLocal.withInitial(ArrayDeque::new);
    private final Map<String,OperationPermit> local=new ConcurrentHashMap<>();
    private final Map<String,WorkToken> localWork=new ConcurrentHashMap<>();
    private final ScheduledExecutorService heartbeat=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"cluster-work-heartbeat");t.setDaemon(true);return t;});
    private static final long TTL=30000;
    public ClusterWorkCoordinator(ClusterDatabase db,ClusterIdentity identity){this.db=db;this.identity=identity;}
    public boolean enabled(){return identity.enabled();}
    @PostConstruct public void start(){if(!enabled())return;
        new SchemaLifecycle(db.jdbc).validate(Arrays.asList(SchemaLifecycle.resource(db.dialect,"20261103_cluster_coordination"),SchemaLifecycle.resource(db.dialect,"20261103_cluster_recovery")));
        heartbeat.scheduleWithFixedDelay(this::renewLocal,1000,1000,TimeUnit.MILLISECONDS);
    }
    @PreDestroy public void stop(){heartbeat.shutdownNow();}
    public static final class WorkToken {
        public final String resourceKey,nodeId,generation,token;public final long epoch,ttl;
        WorkToken(String key,String node,String gen,String token,long epoch,long ttl){this.resourceKey=key;this.nodeId=node;this.generation=gen;this.token=token;this.epoch=epoch;this.ttl=ttl;}
    }
    public WorkToken tryAcquire(String key,long ttl){
        if(!enabled())return new WorkToken(key,"local","local",UUID.randomUUID().toString(),1,ttl);
        if(key==null||key.length()>160||ttl<1000||ttl>120000)throw new IllegalArgumentException("Invalid work lease");
        return db.locked(()->{if(recovery.get())identity.requireActive();else identity.requireAdmission();requireActiveMode();long now=db.now();
            db.dialect.insertIfAbsent(db.jdbc,"wearable_cluster_work",Arrays.asList("resource_key","epoch","lease_until"),Arrays.asList("resource_key"),key,0,0);
            Map<String,Object> row=db.jdbc.queryForMap("SELECT epoch,lease_until,node_id,generation FROM wearable_cluster_work WHERE resource_key=? FOR UPDATE",key);
            if(((Number)row.get("lease_until")).longValue()>now&&db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_node WHERE node_id=? AND generation=? AND lease_until>?",Integer.class,row.get("node_id"),row.get("generation"),now)>0)return null;
            WorkToken t=new WorkToken(key,identity.nodeId(),identity.generation(),UUID.randomUUID().toString(),((Number)row.get("epoch")).longValue()+1,ttl);
            db.jdbc.update("UPDATE wearable_cluster_work SET node_id=?,generation=?,token=?,epoch=?,lease_until=? WHERE resource_key=?",t.nodeId,t.generation,t.token,t.epoch,now+ttl,key);
            localWork.put(t.token,t);return t;});
    }
    public boolean renew(WorkToken t){if(!enabled())return true;return db.locked(()->{
        identity.requireActive();long now=db.now();return db.jdbc.update("UPDATE wearable_cluster_work SET lease_until=? WHERE resource_key=? AND node_id=? AND generation=? AND token=? AND epoch=? AND lease_until>?",now+t.ttl,t.resourceKey,t.nodeId,t.generation,t.token,t.epoch,now)==1;});}
    public void release(WorkToken t){localWork.remove(t.token);if(enabled())db.locked(()->{db.jdbc.update("UPDATE wearable_cluster_work SET lease_until=0 WHERE resource_key=? AND node_id=? AND generation=? AND token=? AND epoch=?",t.resourceKey,t.nodeId,t.generation,t.token,t.epoch);return null;});}
    private void checkWork(WorkToken t){
        if(db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_work WHERE resource_key=? AND node_id=? AND generation=? AND token=? AND epoch=? AND lease_until>?",Integer.class,t.resourceKey,t.nodeId,t.generation,t.token,t.epoch,db.now())!=1)throw unavailable("WORK_FENCED","工作租约已失效，旧执行者不能继续写入或发送");
    }
    public <T>T withFencedWrite(WorkToken t,Supplier<T> write){if(!enabled())return write.get();return db.locked(()->{identity.requireActive();checkWork(t);checkPermits();return write.get();});}
    public <T>T fenced(Supplier<T> write){if(!enabled())return write.get();synchronized(com.ruoyi.guardian.WearableBusinessStore.transactionLock()){return db.locked(()->{
        identity.requireActive();for(WorkToken t:heldWork.get())checkWork(t);checkPermits();return write.get();});}}
    public void beforeEffect(){if(!enabled())return;fenced(()->{identity.requireAdmission();requireActiveMode();return null;});}
    /** Durable DB-time cadence prevents staggered JVM timers repeating the same polling interval. */
    public <T>T runPeriodic(String resource,String schedule,long interval,Supplier<T> action){
        if(!enabled())return action.get();
        if(interval<1000||interval>86400000||schedule.length()>120)throw new IllegalArgumentException("Invalid schedule");
        return run(resource,true,()->{
            boolean due=fenced(()->{String key="schedule:"+schedule;long now=db.now();
                db.dialect.insertIfAbsent(db.jdbc,"wearable_cluster_work",Arrays.asList("resource_key","epoch","lease_until"),Arrays.asList("resource_key"),key,0,0);
                long next=db.jdbc.queryForObject("SELECT lease_until FROM wearable_cluster_work WHERE resource_key=? FOR UPDATE",Long.class,key);if(next>now)return false;
                db.jdbc.update("UPDATE wearable_cluster_work SET lease_until=?,epoch=epoch+1 WHERE resource_key=?",now+interval,key);return true;});
            return due?action.get():null;
        });
    }
    public <T>T runRecovery(String resource,boolean background,Supplier<T> action){boolean previous=recovery.get();recovery.set(true);try{return run(resource,background,action);}finally{recovery.set(previous);}}
    public <T>T run(String resource,boolean background,Supplier<T> work){
        if(!enabled())return work.get();
        if(current.get()!=null){for(WorkToken held:heldWork.get())if(resource.equals(held.resourceKey))return work.get();
            if(!current.get().resourceKey.startsWith("quartz:")&&!("platform".equals(current.get().resourceKey)&&"media".equals(resource)))throw new IllegalStateException("Nested cluster resource order violation");}
        WorkToken token=null;long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(background?0:5);
        do {token=tryAcquire(resource,TTL);if(token!=null)break;if(background)return null;
            if(System.nanoTime()>=until)throw unavailable("WORK_BUSY","同类操作正在另一节点处理，请使用原操作标识重试");
            try{Thread.sleep(25);}catch(InterruptedException e){Thread.currentThread().interrupt();throw unavailable("WORK_INTERRUPTED","操作等待已中断");}
        }while(true);
        WorkToken previous=current.get();current.set(token);heldWork.get().add(token);
        try(OperationPermit permit=begin("BUSINESS")){return work.get();}
        finally{heldWork.get().remove(token);if(previous==null)current.remove();else current.set(previous);release(token);}
    }
    public final class OperationPermit implements AutoCloseable {
        public final String id,kind;private boolean closed;
        OperationPermit(String id,String kind){this.id=id;this.kind=kind;}
        public void close(){if(closed)return;closed=true;operations.get().remove(this);local.remove(id);
            if(enabled())db.locked(()->{db.jdbc.update("UPDATE wearable_cluster_operation SET state='FINISHED',finished_at=? WHERE operation_id=? AND node_id=? AND generation=? AND state='ACTIVE'",db.now(),id,identity.nodeId(),identity.generation());return null;});}
    }
    public OperationPermit begin(String kind){
        OperationPermit p=new OperationPermit(UUID.randomUUID().toString(),kind);
        if(enabled())db.locked(()->{if(recovery.get())identity.requireActive();else identity.requireAdmission();requireActiveMode();long now=db.now();
            db.jdbc.update("INSERT INTO wearable_cluster_operation(operation_id,node_id,generation,operation_kind,state,lease_until,created_at) VALUES(?,?,?,?, 'ACTIVE',?,?)",p.id,identity.nodeId(),identity.generation(),kind,now+TTL,now);return null;});
        operations.get().push(p);local.put(p.id,p);return p;
    }
    public void end(){Deque<OperationPermit> stack=operations.get();if(stack.isEmpty())throw new IllegalStateException("No operation permit belongs to this thread");stack.peek().close();}
    private void checkPermits(){
        for(OperationPermit p:operations.get())if(db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_operation WHERE operation_id=? AND node_id=? AND generation=? AND state='ACTIVE' AND lease_until>?",Integer.class,p.id,identity.nodeId(),identity.generation(),db.now())!=1)
            throw unavailable("OPERATION_FENCED","操作许可已失效，禁止继续写入");
        if(operations.get().isEmpty())requireActiveMode();
    }
    public void requireActiveMode(){if(!"ACTIVE".equals(db.jdbc.queryForObject("SELECT mode FROM wearable_runtime_control WHERE control_key='global'",String.class)))throw unavailable("MAINTENANCE_PAUSED","系统正在维护，业务写入暂时停止");}
    private void renewLocal(){try{
        for(WorkToken t:localWork.values())if(!renew(t))localWork.remove(t.token);
        if(!local.isEmpty())db.locked(()->{identity.requireActive();long now=db.now();for(OperationPermit p:local.values())db.jdbc.update("UPDATE wearable_cluster_operation SET lease_until=? WHERE operation_id=? AND node_id=? AND generation=? AND state='ACTIVE' AND lease_until>?",now+TTL,p.id,identity.nodeId(),identity.generation(),now);return null;});
    }catch(RuntimeException ignored){/* Each SQL/effect independently fences on failure. */}}
    /** Only monotone evidence/accounting changes, never a business write or permission to send. */
    public <T>T evidenceWrite(Supplier<T> evidence){return db.locked(()->{identity.requireActive();return evidence.get();});}
    public JSONObject recoverAbandoned(String actor,String reason){
        if(reason==null||reason.trim().length()<10||reason.length()>500)throw AdminQueryService.fail(400,"RECOVERY_REASON_REQUIRED","请填写至少10字且不超过500字的核对依据");
        JSONObject result=evidenceWrite(()->{
            if(!"PAUSED".equals(db.jdbc.queryForObject("SELECT mode FROM wearable_runtime_control WHERE control_key='global'",String.class)))throw unavailable("RECOVERY_REQUIRES_PAUSE","先暂停全局业务，再核对失联操作");
            JSONObject status=status(false);
            boolean blocked=status.getIntValue("uncertainEffects")+status.getIntValue("uncertainTransport")+status.getIntValue("uncertainPush")>0;
            long now=db.now();
            int recovered=blocked?0:db.jdbc.update("UPDATE wearable_cluster_operation SET state='RECOVERED',finished_at=? WHERE state='ACTIVE' AND NOT EXISTS (SELECT 1 FROM wearable_cluster_node n WHERE n.node_id=wearable_cluster_operation.node_id AND n.generation=wearable_cluster_operation.generation AND n.lease_until>?)",now,now);
            JSONObject summary=status(false);summary.put("recoveredOperations",recovered);summary.put("recoveryBlocked",blocked);
            db.jdbc.update("INSERT INTO wearable_cluster_recovery(recovery_id,node_id,generation,actor_id,reason,summary_json,created_at) VALUES(?,?,?,?,?,?,?)",UUID.randomUUID().toString(),identity.nodeId(),identity.generation(),actor,reason.trim(),summary.toJSONString(),now);return summary;
        });
        if(result.getBooleanValue("recoveryBlocked"))throw unavailable("RECOVERY_UNCONFIRMED","仍有外部执行结果未确认，不能清理失联操作或假报排空；本次核对已记录");
        return result;
    }
    public JSONObject status(boolean nodeOnly){return db.locked(()->{
        long now=db.now();String where=nodeOnly?" AND node_id=? AND generation=?":"";Object[] args=nodeOnly?new Object[]{identity.nodeId(),identity.generation()}:new Object[]{};
        int active=db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_operation WHERE state='ACTIVE'"+where,Integer.class,args);
        int effects=db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_media_effect WHERE state IN ('IN_FLIGHT','UNKNOWN')"+where,Integer.class,args);
        List<Long> leases=db.jdbc.query("SELECT lease_until FROM wearable_cluster_operation WHERE state='ACTIVE'"+where,(r,n)->r.getLong(1),args);
        int transport=db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE delivery_status IN ('DISPATCHING','UNKNOWN')"+where,Integer.class,args);
        int push=nodeOnly?0:db.jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox WHERE status='IN_FLIGHT'",Integer.class);
        long unknown=leases.stream().filter(v->v<=now).count()+effects+transport+push;
        JSONObject out=new JSONObject();out.put("activeWrites",active);out.put("unknown",unknown);out.put("quiescent",active==0&&effects==0&&transport==0&&push==0);out.put("draining",active>0||effects>0||transport>0||push>0);out.put("uncertainEffects",effects);out.put("uncertainTransport",transport);out.put("uncertainPush",push);return out;});}
    private static RuntimeException unavailable(String code,String message){return AdminQueryService.fail(503,code,message);}
}
