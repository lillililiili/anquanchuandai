package com.ruoyi.cluster;
import com.alibaba.fastjson2.JSONObject;
import org.apache.commons.codec.digest.DigestUtils;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.beans.factory.annotation.Autowired;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
/** At-most-one durable attempt. A DISPATCHING record is NEVER requeued. */
@Component public class DeviceCommandRouter {
    public interface Sender {
        void send(OwnerToken owner,String wire,long timeoutMillis,Runnable validateAttempt) throws Exception;
    }
    public static final class Pending extends java.io.IOException {
        public final String commandId,status;
        public Pending(String id,String s) {
            super("设备命令"+s+"，请查询原请求，不要重复下发");
            commandId=id;
            status=s;
        }
    }
    private final ClusterDatabase db;
    private final ClusterIdentity identity;
    private final ClusterProperties properties;
    private final DeviceOwnership ownership;
    private final java.util.concurrent.ExecutorService worker=java.util.concurrent.Executors.newSingleThreadExecutor(r-> {
        Thread t=new Thread(r,"cluster-device-dispatch");
        t.setDaemon(true);
        return t;
    }
    );
    private final java.util.concurrent.atomic.AtomicBoolean working=new java.util.concurrent.atomic.AtomicBoolean();
    @javax.annotation.PreDestroy public void close() {
        worker.shutdownNow();
    }
    @Scheduled(fixedDelayString="${melhat.cluster.poll-millis:500}") public void poll() {
        if(enabled()&&working.compareAndSet(false,true))worker.execute(()-> {
            try {
                dispatchOwnedBatch();
            }
            catch(RuntimeException unavailable) {
                org.slf4j.LoggerFactory.getLogger(getClass()).warn("Cluster dispatch unavailable; errorType={}",unavailable.getClass().getSimpleName());
            }
            finally {
                working.set(false);
            }
        }
        );
    }
    private final Map<String,Sender> senders=new ConcurrentHashMap<>();
    @Autowired(required=false) private ClusterCommandGuard guard;
    public DeviceCommandRouter(ClusterDatabase db,ClusterIdentity identity,ClusterProperties properties,DeviceOwnership ownership) {
        this.db=db;
        this.identity=identity;
        this.properties=properties;
        this.ownership=ownership;
    }
    public java.time.Instant now() {return java.time.Instant.ofEpochMilli(db.now());}
    /** Durable successful logins also retain pending SIP provisioning after worker death. */
    public java.util.List<String> knownHelmetDevices(){return db.jdbc.query("SELECT device_id FROM wearable_device_owner WHERE device_type='helmet'",(r,n)->r.getString(1));}
    public boolean enabled() {
        return identity.enabled();
    }
    public void register(String type,Sender sender) {
        senders.put(type,sender);
    }
    public static String fingerprint(JSONObject value) {
        return DigestUtils.sha256Hex(canonical(value));
    }
    private static String canonical(Object value) {
        if(value instanceof Map) {
            Map<String,Object> sorted=new TreeMap<>();
            for(Map.Entry<?,?> e:((Map<?,?>)value).entrySet())sorted.put(String.valueOf(e.getKey()),e.getValue());
            StringBuilder s=new StringBuilder("{");
            for(Map.Entry<String,Object>e:sorted.entrySet())s.append(JSONObject.toJSONString(e.getKey())).append(':').append(canonical(e.getValue())).append(',');
            return s.append('}').toString();
        }
        if(value instanceof Collection) {
            StringBuilder s=new StringBuilder("[");
            for(Object v:(Collection<?>)value)s.append(canonical(v)).append(',');
            return s.append(']').toString();
        }
        return JSONObject.toJSONString(value);
    }
    public String scope(String actor,String device,String request) {
        return DigestUtils.sha256Hex(actor+"\n"+device+"\n"+request);
    }
    public JSONObject find(String scope,String fingerprint) {
        List<JSONObject> rows=db.jdbc.query("SELECT command_id,fingerprint FROM wearable_transport_command WHERE scope_key=?",(r,n)-> {
            JSONObject o=new JSONObject();
            o.put("id",r.getString(1));
            o.put("fingerprint",r.getString(2));
            return o;
        }
        ,scope);
        if(rows.isEmpty())return null;
        if(!fingerprint.equals(rows.get(0).getString("fingerprint")))throw new IllegalArgumentException("相同请求编号不能用于不同内容");
        return read(rows.get(0).getString("id"));
    }
    /** businessAdmission writes the business command on the same JDBC datasource; no external side effects. */
    public JSONObject admit(String id,String scope,String fingerprint,String type,String device,JSONObject context,JSONObject wire,boolean ready,Runnable businessAdmission) {
        synchronized(com.ruoyi.guardian.WearableBusinessStore.transactionLock()) {
            return db.locked(()-> {
                identity.requireAdmission();
                if(guard!=null)guard.admit(device);
                JSONObject old=find(scope,fingerprint);
                if(old!=null)return old;
                OwnerToken owner;
                try {
                    owner=ownership.target(type,device);
                }
                catch(IllegalStateException e) {
                    if(ready)throw e;
                    owner=new OwnerToken(type,device,identity.nodeId(),identity.generation(),"offline");
                }
                long now=db.now();
                db.jdbc.update("INSERT INTO wearable_transport_command(command_id,scope_key,fingerprint,device_type,device_id,node_id,generation,connection_token,wire_json,context_json,delivery_status,deadline,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",id,scope,fingerprint,type,device,owner.nodeId,owner.generation,owner.connectionToken,wire.toJSONString(),context.toJSONString(),ready?"QUEUED":"PREPARING",now+properties.getCommandTimeoutMillis(),now,now);
                businessAdmission.run();
                return read(id);
            }
            );
        }
    }
    public JSONObject submit(String id,String scope,String fingerprint,String type,String device,JSONObject context,JSONObject wire) {
        return admit(id,scope,fingerprint,type,device,context,wire,true,()-> {
        }
        );
    }
    public JSONObject activate(String id,JSONObject wire) {
        return db.locked(()-> {
            identity.requireAdmission();
            JSONObject row=read(id);
            if(row==null)throw new IllegalArgumentException("命令尚未持久接收");
            if("PREPARING".equals(row.getString("deliveryStatus")))db.jdbc.update("UPDATE wearable_transport_command SET wire_json=?,delivery_status='QUEUED',updated_at=? WHERE command_id=? AND delivery_status='PREPARING'",wire.toJSONString(),db.now(),id);
            return read(id);
        }
        );
    }
    public JSONObject read(String id) {
        List<JSONObject> list=db.jdbc.query("SELECT context_json,delivery_status,reason,created_at,updated_at FROM wearable_transport_command WHERE command_id=?",(r,n)-> {
            JSONObject out=JSONObject.parseObject(r.getString(1));
            out.put("id",id);
            out.put("deliveryStatus",r.getString(2));
            out.put("deliveryReason",r.getString(3));
            out.put("deliveryUpdatedAt",r.getLong(5));
            return out;
        }
        ,id);
        return list.isEmpty()?null:list.get(0);
    }
    public void acknowledge(String id,String device,boolean accepted) {
        db.jdbc.update("UPDATE wearable_transport_command SET delivery_status=?,reason=?,updated_at=? WHERE command_id=? AND device_id=? AND delivery_status IN ('QUEUED','DISPATCHING','SENT','UNKNOWN')",accepted?"ACKNOWLEDGED":"REJECTED",accepted?"设备已确认":"设备拒绝了此操作",db.now(),id,device);
    }
    public void completeWithoutSend(String id) {
        db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='CANCELLED',reason='此操作只更新平台配置或会话，无需向设备发送',updated_at=? WHERE command_id=? AND delivery_status='PREPARING'",db.now(),id);
    }
    public void failBeforeSend(String id,String reason) {
        db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='FAILED_BEFORE_SEND',reason=?,updated_at=? WHERE command_id=? AND delivery_status='PREPARING'",reason,db.now(),id);
    }
    public JSONObject send(String device,JSONObject wire,String purpose) throws java.io.IOException {
        String id=wire.getString("talkback_id");
        JSONObject existing=id==null?null:read(id);
        if(existing!=null)activate(id,wire);
        else {
            OwnerToken owner=ownership.target("helmet",device);
            String request=purpose+":"+owner.connectionToken+":"+fingerprint(wire);
            String scope=scope("internal",device,request);
            id="HT-"+scope.substring(0,40);
            JSONObject context=new JSONObject();
            context.put("deviceId",device);
            submit(id,scope,fingerprint(wire),"helmet",device,context,wire);
        }
        // The HTTP node does not block while holding the media service monitor. Owner poller advances it.
        JSONObject row=read(id);
        String status=row.getString("deliveryStatus");
        if(!Arrays.asList("SENT","ACKNOWLEDGED","REJECTED").contains(status))throw new Pending(id,status);
        return row;
    }
    public void dispatchOwnedBatch() {
        if(!enabled())return;
        recoverAttempts();
        identity.requireActive();
        List<String> ids=db.jdbc.query(db.dialect.limit("SELECT command_id FROM wearable_transport_command WHERE node_id=? AND generation=? AND delivery_status='QUEUED' ORDER BY created_at","32"),(r,n)->r.getString(1),identity.nodeId(),identity.generation());
        for(String id:ids)dispatch(id);
    }
    public void recoverAttempts() {
        if(!enabled())return;
        db.locked(()-> {
            long now=db.now();
            db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='UNKNOWN',reason='发送尝试已中断或超时，结果未确认，不会自动重复下发',updated_at=? WHERE delivery_status='DISPATCHING' AND attempt_until<=?",now,now);
            db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='EXPIRED',reason='发送前已过期',updated_at=? WHERE delivery_status IN ('QUEUED','PREPARING') AND deadline<=?",now,now);
            db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='CANCELLED',reason='目标连接已变化或失效，未发送',updated_at=? WHERE delivery_status='QUEUED' AND NOT EXISTS (SELECT 1 FROM wearable_device_owner o JOIN wearable_cluster_node n ON n.node_id=o.node_id AND n.generation=o.generation WHERE o.device_type=wearable_transport_command.device_type AND o.device_id=wearable_transport_command.device_id AND o.node_id=wearable_transport_command.node_id AND o.generation=wearable_transport_command.generation AND o.connection_token=wearable_transport_command.connection_token AND o.lease_until>? AND n.lease_until>?)",now,now,now);
            return null;
        }
        );
    }
    private void dispatch(String id) {
        JSONObject attempt=db.locked(()-> {
            identity.requireActive();
            List<JSONObject> rows=db.jdbc.query("SELECT device_type,device_id,node_id,generation,connection_token,wire_json,delivery_status,deadline FROM wearable_transport_command WHERE command_id=?",(r,n)-> {
                JSONObject a=new JSONObject();
                String[] keys= {
                    "type","device","node","generation","connection","wire","status"
                }
                ;
                for(int i=0;
                i<keys.length;
                i++)a.put(keys[i],r.getString(i+1));
                a.put("deadline",r.getLong(8));
                return a;
            }
            ,id);
            if(rows.isEmpty())return null;
            JSONObject a=rows.get(0);
            if(!"QUEUED".equals(a.getString("status")))return null;
            OwnerToken owner=owner(a);
            long now=db.now();
            if(!identity.nodeId().equals(owner.nodeId)||!identity.generation().equals(owner.generation))return null;
            if(a.getLongValue("deadline")<=now||!ownership.current(owner)) {
                db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='CANCELLED',reason='目标连接已变化，未发送',updated_at=? WHERE command_id=? AND delivery_status='QUEUED'",now,id);
                return null;
            }
            try{if(guard!=null)guard.dispatch(id);}catch(com.ruoyi.guardian.AdminQueryService.QueryFailed rejected){
                if(rejected.code!=403&&rejected.code!=401)throw rejected;
                db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='CANCELLED',reason='权限或领用关系已变化，未发送',updated_at=? WHERE command_id=? AND delivery_status='QUEUED'",now,id);return null;
            }
            String claim=UUID.randomUUID().toString();
            db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='DISPATCHING',claim_token=?,attempt_until=?,updated_at=? WHERE command_id=? AND delivery_status='QUEUED'",claim,now+properties.getSendTimeoutMillis(),now,id);
            a.put("claim",claim);
            return a;
        }
        );
        if(attempt==null)return;
        try {
            identity.requireActive();
            if(guard!=null)guard.dispatch(id);
            OwnerToken owner=owner(attempt);
            if(!ownership.current(owner))throw new IllegalStateException("Owner changed before send");
            Sender sender=senders.get(owner.deviceType);
            if(sender==null)throw new IllegalStateException("Local sender unavailable");
            Runnable fence=()-> {
                identity.requireActive();
                if(guard!=null)guard.dispatch(id);
                long now=db.now();
                if(!ownership.current(owner)||db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE command_id=? AND claim_token=? AND delivery_status='DISPATCHING' AND attempt_until>? AND deadline>?",Integer.class,id,attempt.getString("claim"),now,now)!=1)throw new IllegalStateException("发送授权已失效");
            }
            ;
            fence.run();
            sender.send(owner,attempt.getString("wire"),properties.getSendTimeoutMillis(),fence);
            finish(id,attempt.getString("claim"),"SENT","已交给设备连接，等待设备确认");
        }
        catch(Exception e) {
            finish(id,attempt.getString("claim"),"UNKNOWN","结果未确认，不会自动重复下发");
        }
    }
    private OwnerToken owner(JSONObject a) {
        return new OwnerToken(a.getString("type"),a.getString("device"),a.getString("node"),a.getString("generation"),a.getString("connection"));
    }
    private void finish(String id,String claim,String state,String reason) {
        db.jdbc.update("UPDATE wearable_transport_command SET delivery_status=?,reason=?,updated_at=? WHERE command_id=? AND claim_token=? AND delivery_status='DISPATCHING' AND attempt_until>?",state,reason,db.now(),id,claim,db.now());
    }
}
