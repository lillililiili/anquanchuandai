package com.ruoyi.fuda;

import com.ruoyi.guardian.GuardianStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import javax.annotation.PreDestroy;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Network work never executes on a device thread, a transaction callback, or Spring's scheduler. */
@Component
public class FudaPushDispatcher {
    private static final Logger LOG=LoggerFactory.getLogger(FudaPushDispatcher.class);
    private final FudaPushOutbox outbox;
    private final FudaPushCapture capture;
    private final FudaPushHttpSender sender;
    private final FudaPushProperties properties;
    private final Clock clock;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterWorkCoordinator coordinator;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterDatabase clusterDb;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterIdentity clusterIdentity;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.guardian.WearableMaintenance maintenance;
    private long now(){return clusterIdentity!=null&&clusterIdentity.enabled()?clusterDb.now():clock.millis();}
    private final ObjectProvider<GuardianStore> guardian;
    private final AtomicBoolean queued=new AtomicBoolean();
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->{
        Thread t=new Thread(r,"fuda-push-sender"); t.setDaemon(true); return t;
    });

    public FudaPushDispatcher(FudaPushOutbox outbox,FudaPushCapture capture,FudaPushHttpSender sender,
            FudaPushProperties properties,@Qualifier("fudaClock") Clock clock,ObjectProvider<GuardianStore> guardian) {
        this.outbox=outbox; this.capture=capture; this.sender=sender; this.properties=properties; this.clock=clock; this.guardian=guardian;
        outbox.onCommit(this::wakeup);
    }

    @Scheduled(fixedDelay=1000,initialDelay=1000)
    public void wakeup() {
        if(!properties.isEnabled()||worker.isShutdown()||!queued.compareAndSet(false,true))return;
        try {
            worker.execute(()->{
                try { drain(); }
                catch(RuntimeException error) { LOG.warn("福大推送工作等待恢复，errorType={}",error.getClass().getSimpleName()); }
                finally { queued.set(false); }
            });
        } catch(RejectedExecutionException stopped) { queued.set(false); }
    }

    /** Reconcile stale/offline presence after restart even when no human opens a page. No network send here. */
    @Scheduled(fixedDelay=5000,initialDelay=5000)
    public void reconcilePresence() {
        if(!properties.isEnabled())return;
        try { GuardianStore store=guardian.getIfAvailable(); if(store!=null)store.snapshot(); }
        catch(RuntimeException error) { LOG.warn("福大在线状态投影等待恢复，errorType={}",error.getClass().getSimpleName()); }
    }

    /** Package-visible deterministic entry for isolated end-to-end tests. */
    synchronized int drain() {
        if(maintenance!=null&&!maintenance.tryBeginWrite())return 0;
        try{return drainActive();}finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private int drainActive() {
        int completed=0;
        for(int i=0;i<properties.getBatchSize()&&properties.isEnabled()&&!Thread.currentThread().isInterrupted();i++) {
            FudaPushOutbox.Delivery row=outbox.claim(properties.getDestinationId(),now(),properties.getLeaseMillis());
            if(row==null)break;
            if(!properties.isEnabled()) {
                outbox.releaseUnsent(row,"NOT_SENT_PAUSED",now()); break;
            }
            if(!capture.maySend(row)) {
                outbox.finish(row,"CANCELLED","AUTHORIZATION_REVOKED",0,now(),0); continue;
            }
            try {
                if(maintenance!=null&&maintenance.paused()) {
                    outbox.releaseUnsent(row,"NOT_SENT_PAUSED",now());break;
                }
                if(coordinator!=null)coordinator.beforeEffect();
            } catch(RuntimeException notSent) {
                // Conditional claim-token finish: this live invocation has not called the sender.
                outbox.releaseUnsent(row,"NOT_SENT_FENCED",now());throw notSent;
            }
            FudaPushHttpSender.Result result=sender.send(row.eventType,row.body.getBytes(StandardCharsets.UTF_8));
            long now=now();
            long retry=now+Math.max(backoff(row.attempts),result.retryAfterMillis);
            boolean recorded=outbox.finish(row,result.success?"DELIVERED":"PENDING",result.outcome,result.httpStatus,now,retry);
            if(recorded&&result.success)completed++;
            if(!result.success)LOG.warn("福大事件等待补发，eventId={},attempt={},outcome={},httpStatus={}",row.eventId,row.attempts,result.outcome,result.httpStatus);
            try { TimeUnit.MILLISECONDS.sleep(properties.getMinSendIntervalMillis()); }
            catch(InterruptedException stopped) { Thread.currentThread().interrupt(); break; }
        }
        return completed;
    }

    private long backoff(int attempts) {
        long delay=properties.getRetryBaseMillis(), maximum=properties.getRetryMaxMillis();
        for(int i=1;i<attempts&&delay<maximum;i++)delay=delay>maximum/2?maximum:delay*2;
        return Math.min(delay,maximum);
    }

    @PreDestroy public void close() { worker.shutdownNow(); }
}
