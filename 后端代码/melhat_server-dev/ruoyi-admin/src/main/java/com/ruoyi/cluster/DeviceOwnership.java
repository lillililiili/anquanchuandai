package com.ruoyi.cluster;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Component;
import java.time.Instant;
import java.util.*;
@Component public class DeviceOwnership {
    private final ClusterDatabase db;
    private final ClusterIdentity identity;
    public DeviceOwnership(ClusterDatabase db,ClusterIdentity identity) {
        this.db=db;
        this.identity=identity;
    }
    public java.time.Clock clock() {
        return new java.time.Clock() {
            public java.time.ZoneId getZone() {
                return java.time.ZoneOffset.UTC;
            }
            public java.time.Clock withZone(java.time.ZoneId zone) {
                return this;
            }
            public java.time.Instant instant() {
                return java.time.Instant.ofEpochMilli(now());
            }
        }
        ;
    }
    public boolean enabled() {
        return identity.enabled();
    }
    public long now() {
        return db.now();
    }
    public OwnerToken claimLogin(String type,String id,String sessionId,long heartbeatMillis,JSONObject initial) {
        if(id==null||id.length()>128||heartbeatMillis<1000||heartbeatMillis>600000)throw new IllegalArgumentException("Invalid device ownership");
        return db.locked(()-> {
            identity.requireAdmission();
            long now=db.now();
            OwnerToken t=new OwnerToken(type,id,identity.nodeId(),identity.generation(),UUID.randomUUID().toString());
            JSONObject status=readPresence(type,id);
            for(String key:initial.keySet())if(!status.containsKey(key)||(initial.get(key)!=null&&!(key.endsWith("Freshness")&&"UNKNOWN".equals(initial.getString(key)))))status.put(key,initial.get(key));
            for(String key:new ArrayList<>(status.keySet()))if(key.endsWith("Freshness")&&"CURRENT".equals(status.getString(key)))status.put(key,"STALE");
            for(String key:Arrays.asList("worn","hookAEngaged","hookBEngaged"))if(status.containsKey(key))status.put(key,null);
            status.put("lastSeenAt",Instant.ofEpochMilli(now).toString());
            db.dialect.upsert(db.jdbc,"wearable_device_owner",Arrays.asList("device_type","device_id","node_id","generation","connection_token","session_id","lease_until","last_seen","heartbeat_millis","status_json"),Arrays.asList("device_type","device_id"),type,id,t.nodeId,t.generation,t.connectionToken,sessionId,now+heartbeatMillis,now,heartbeatMillis,status.toJSONString());
            return t;
        }
        );
    }
    public boolean current(OwnerToken t) {
        if(t==null)return false;
        long now=db.now();
        return db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_owner o JOIN wearable_cluster_node n ON n.node_id=o.node_id AND n.generation=o.generation WHERE o.device_type=? AND o.device_id=? AND o.connection_token=? AND o.generation=? AND o.node_id=? AND o.lease_until>? AND n.lease_until>?",Integer.class,t.deviceType,t.deviceId,t.connectionToken,t.generation,t.nodeId,now,now)==1;
    }
    public OwnerToken target(String type,String id) {
        List<OwnerToken> list=db.jdbc.query("SELECT node_id,generation,connection_token FROM wearable_device_owner WHERE device_type=? AND device_id=?",(r,n)->new OwnerToken(type,id,r.getString(1),r.getString(2),r.getString(3)),type,id);
        if(list.isEmpty()||!current(list.get(0)))throw new IllegalStateException("设备不在线，未下发命令");
        return list.get(0);
    }
    /** appendReceipt must only append raw/captured data on the SAME DataSource. Projection runs after return. */
    public void receiveUnderOwner(OwnerToken t,JSONObject status,Runnable appendReceipt) {
        db.locked(()-> {
            identity.requireActive();
            if(!current(t))throw new IllegalArgumentException("连接所有权已变化，请重新登录");
            long now=db.now();
            appendReceipt.run();
            JSONObject next=new JSONObject(status);
            if("helmet".equals(t.deviceType)) {
                JSONObject old=readPresence(t.deviceType,t.deviceId);
                for(String key:old.keySet())if(!next.containsKey(key)||next.get(key)==null||("UNKNOWN".equals(next.getString(key))&&key.endsWith("Freshness")))next.put(key,old.get(key));
            }
            next.put("lastSeenAt",Instant.ofEpochMilli(now).toString());
            long heartbeat=db.jdbc.queryForObject("SELECT heartbeat_millis FROM wearable_device_owner WHERE device_type=? AND device_id=?",Long.class,t.deviceType,t.deviceId);
            db.jdbc.update("UPDATE wearable_device_owner SET lease_until=?,last_seen=?,status_json=? WHERE device_type=? AND device_id=? AND connection_token=? AND generation=?",now+heartbeat,now,next.toJSONString(),t.deviceType,t.deviceId,t.connectionToken,t.generation);
            return null;
        }
        );
    }
    public boolean release(OwnerToken t) {
        if(t==null)return false;
        return db.locked(()->db.jdbc.update("UPDATE wearable_device_owner SET lease_until=0 WHERE device_type=? AND device_id=? AND node_id=? AND generation=? AND connection_token=?",t.deviceType,t.deviceId,t.nodeId,t.generation,t.connectionToken)==1);
    }
    public java.util.List<String> expiredDeviceIds(String type) {
        long now=db.now();
        return db.jdbc.query("SELECT o.device_id FROM wearable_device_owner o LEFT JOIN wearable_cluster_node n ON n.node_id=o.node_id AND n.generation=o.generation WHERE o.device_type=? AND (o.lease_until<=? OR n.lease_until IS NULL OR n.lease_until<=?)",(r,n)->r.getString(1),type,now,now);
    }
    public JSONObject readPresence(String type,String id) {
        long now=db.now();
        List<JSONObject> rows=db.jdbc.query("SELECT o.status_json,o.last_seen,o.lease_until,n.lease_until AS node_until,o.heartbeat_millis FROM wearable_device_owner o LEFT JOIN wearable_cluster_node n ON n.node_id=o.node_id AND n.generation=o.generation WHERE o.device_type=? AND o.device_id=?",(r,n)-> {
            JSONObject s=JSONObject.parseObject(r.getString(1));
            if(s==null)s=new JSONObject();
            s.put("lastSeenAt",Instant.ofEpochMilli(r.getLong(2)).toString());
            s.put("online",r.getLong(3)>now&&r.getLong(4)>now);
            long heartbeat=r.getLong(5);
            for(String key:new ArrayList<>(s.keySet()))if(key.endsWith("Freshness")&&"CURRENT".equals(s.getString(key))) {
                String at=s.getString(key.substring(0,key.length()-9)+"ReportedAt");
                if(at!=null&&Instant.parse(at).toEpochMilli()+heartbeat<=now)s.put(key,"STALE");
            }
            return s;
        }
        ,type,id);
        JSONObject s=rows.isEmpty()?new JSONObject():rows.get(0);
        boolean online=s.getBooleanValue("online");
        s.put("online",online);
        s.put("freshness",online?"CURRENT":rows.isEmpty()?"UNKNOWN":"STALE");
        if(!online) {
            for(String key:new ArrayList<>(s.keySet()))if(key.endsWith("Freshness")&&"CURRENT".equals(s.getString(key)))s.put(key,"STALE");
            for(String key:Arrays.asList("worn","hookAEngaged","hookBEngaged"))if(s.containsKey(key))s.put(key,null);
        }
        return s;
    }
}
