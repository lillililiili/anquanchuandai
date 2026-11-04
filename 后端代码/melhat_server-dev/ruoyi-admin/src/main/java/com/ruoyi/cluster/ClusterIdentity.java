package com.ruoyi.cluster;
import com.ruoyi.database.SchemaLifecycle;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.util.*;
@Component public class ClusterIdentity {
    private final ClusterProperties properties;
    private final ClusterDatabase db;
    private final String generation=UUID.randomUUID().toString();
    private volatile boolean fenced,draining;
    public ClusterIdentity(ClusterProperties properties,ClusterDatabase db) {
        this.properties=properties;
        this.db=db;
    }
    public boolean enabled() {
        return properties.isEnabled();
    }
    public String nodeId() {
        return properties.getNodeId();
    }
    public String generation() {
        return generation;
    }
    @PostConstruct public void start() {
        properties.validate();
        if(!enabled())return;
        new SchemaLifecycle(db.jdbc).validate(Collections.singletonList(SchemaLifecycle.resource(db.dialect,"20261103_cluster_routing")));
        db.locked(()-> {
            long now=db.now();
            List<Long> existing=db.jdbc.query("SELECT lease_until FROM wearable_cluster_node WHERE node_id=?",(r,n)->r.getLong(1),nodeId());
            if(!existing.isEmpty()&&existing.get(0)>now)throw new IllegalStateException("Cluster node-id is already active: "+nodeId());
            db.dialect.upsert(db.jdbc,"wearable_cluster_node",Arrays.asList("node_id","generation","lease_until","draining"),Arrays.asList("node_id"),nodeId(),generation,now+properties.getLeaseMillis(),0);
            return null;
        }
        );
    }
    public boolean isDraining() {
        return draining;
    }
    public void beginDrain() {
        draining=true;
        if(enabled())db.jdbc.update("UPDATE wearable_cluster_node SET draining=1 WHERE node_id=? AND generation=?",nodeId(),generation);
    }
    public void requireAdmission() {
        requireActive();
        if(draining)throw new IllegalStateException("节点正在排空，暂不接受新操作");
    }
    public boolean isActive() {
        if(!enabled())return true;
        if(fenced)return false;
        long now=db.now();
        return db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_node WHERE node_id=? AND generation=? AND lease_until>?",Integer.class,nodeId(),generation,now)==1;
    }
    public void requireActive() {
        if(!isActive())throw new IllegalStateException("节点代次或租约已失效，请重新连接");
    }
    @Scheduled(fixedDelayString="${melhat.cluster.poll-millis:500}") public void renew() {
        if(!enabled()||fenced)return;
        try {
            db.locked(()-> {
                long now=db.now();
                if(db.jdbc.update("UPDATE wearable_cluster_node SET lease_until=? WHERE node_id=? AND generation=? AND lease_until>?",now+properties.getLeaseMillis(),nodeId(),generation,now)!=1)fenced=true;
                return null;
            }
            );
        }
        catch(RuntimeException e) {
            /* DB unavailable: all admissions and sends independently fail closed. */
        }
    }
    @PreDestroy public void stop() {
        if(enabled())db.jdbc.update("UPDATE wearable_cluster_node SET lease_until=0 WHERE node_id=? AND generation=?",nodeId(),generation);
    }
}
