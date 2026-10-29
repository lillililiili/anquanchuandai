package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Repository;
import java.util.List;

/** SQL journal participates in the caller's raw-report transaction. No GuardianStore lock here. */
@Repository
public class HelmetBusinessJournal {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    public HelmetBusinessJournal(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        this.transaction = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        new ResourceDatabasePopulator(new ClassPathResource("db/20261023_helmet_business.sql")).execute(jdbc.getDataSource());
    }
    public void location(JSONObject point) {
        saveLocation(point,false);
    }
    public void offlineLocation(JSONObject point){saveLocation(point,true);}
    private void saveLocation(JSONObject point,boolean idempotent) {
        point.put("queryMillis",point.containsKey("collectedMillis")?point.getLongValue("collectedMillis"):point.getLongValue("receivedMillis"));
        jdbc.update("INSERT INTO helmet_location_fix (id,device_id,person_id,site_id,area_id,received_at,observed_at,body) VALUES (?,?,?,?,?,?,?,?)"+(idempotent?" ON DUPLICATE KEY UPDATE id=id":""),
                point.getString("id"),point.getString("deviceId"),point.getString("personId"),point.getString("siteId"),
                point.getString("areaId"),point.getLongValue("receivedMillis"),point.getLongValue("queryMillis"),point.toJSONString());
    }
    public void event(JSONObject event) {
        if (event.getLong("sourceRecordId") == null) throw new IllegalStateException("告警原始记录编号缺失");
        transaction.execute(status -> {
            String key=groupKey(event);
            // Upsert creates the mutex row without a check/insert race, and joins the raw-report transaction.
            jdbc.update("INSERT INTO helmet_event_group (group_key) VALUES (?) ON DUPLICATE KEY UPDATE group_key=group_key",key);
            JSONObject group=jdbc.queryForObject("SELECT open_event_id,initial_body FROM helmet_event_group WHERE group_key=? FOR UPDATE",
                    (rs,n)->WearableModel.object("id",rs.getString(1),"initial",rs.getString(2)),key);
            String open=group.getString("id");
            List<String> existing=jdbc.query("SELECT event_id FROM helmet_event_link WHERE source_type=? AND source_record_id=?",
                    (rs,n)->rs.getString(1),event.getString("sourceRecordType"),event.getLong("sourceRecordId"));
            if(!existing.isEmpty()) { event.put("eventId",existing.get(0));return null; }
            boolean first=open==null;
            if(first) {
                open=event.getString("eventId");
                if(open==null) open="HE-"+java.util.UUID.randomUUID();
            }
            event.put("eventId",open);event.put("eventGroupKey",key);
            event.remove("initialReport");
            if(first) jdbc.update("UPDATE helmet_event_group SET open_event_id=?,initial_body=? WHERE group_key=?",open,event.toJSONString(),key);
            else event.put("initialReport",JSONObject.parseObject(group.getString("initial")));
            jdbc.update("INSERT INTO helmet_event_link (event_id,group_key,source_type,source_record_id,device_id,received_at,body) VALUES (?,?,?,?,?,?,?)",
                    open,key,event.getString("sourceRecordType"),event.getLong("sourceRecordId"),
                    event.getString("deviceId"),event.getLongValue("receivedMillis"),event.toJSONString());
            return null;
        });
    }
    private static String groupKey(JSONObject event) {
        com.alibaba.fastjson2.JSONArray key=new com.alibaba.fastjson2.JSONArray();
        for(String name:new String[]{"deviceId","act","rawType","personId","siteId","areaId","bindingId","bindingStart","bindingEnd"}) key.add(event.getString(name));
        return org.apache.commons.codec.digest.DigestUtils.sha256Hex(key.toJSONString());
    }
    public List<JSONObject> pending() {
        return jdbc.query("SELECT body FROM helmet_event_link WHERE projected=0 ORDER BY received_at,source_type,source_record_id LIMIT 100",
                (rs,n)->JSONObject.parseObject(rs.getString(1)));
    }
    public void projected(JSONObject envelope) {
        jdbc.update("UPDATE helmet_event_link SET projected=1 WHERE source_type=? AND source_record_id=? AND event_id=?",
                envelope.getString("sourceRecordType"),envelope.getLong("sourceRecordId"),envelope.getString("eventId"));
    }
    public List<String> openEventIds() {
        return jdbc.query("SELECT open_event_id FROM helmet_event_group WHERE open_event_id IS NOT NULL",(rs,n)->rs.getString(1));
    }
    public List<JSONObject> locations(String personId,String deviceId,long from,long to,long cursorTime,String cursorId,int limit) {
        String selector=personId != null ? "person_id" : "device_id";
        return jdbc.query("SELECT body FROM helmet_location_fix WHERE " + selector + "=? AND observed_at>=? AND observed_at<?"
                        + " AND (observed_at>? OR (observed_at=? AND id>?)) ORDER BY observed_at,id LIMIT ?",
                (rs,n)->JSONObject.parseObject(rs.getString(1)),personId != null ? personId : deviceId,from,to,cursorTime,cursorTime,cursorId,limit);
    }
    /** A persisted final verification is authoritative. Repeated synchronization is harmless. */
    public void close(JSONObject event) {
        JSONObject verification=event.getJSONObject("verification");
        if (verification==null || !"已核验".equals(event.getString("status"))) return;
        transaction.execute(status -> { closeInTransaction(event,verification);return null; });
    }
    private void closeInTransaction(JSONObject event,JSONObject verification) {
        String id=event.getString("id");
        List<String> groups=jdbc.query("SELECT DISTINCT group_key FROM helmet_event_link WHERE event_id=?",(rs,n)->rs.getString(1),id);
        // Same lock order as admission: group, then links/raw. A newly accepted source cannot be missed.
        for(String group:groups) jdbc.queryForObject("SELECT group_key FROM helmet_event_group WHERE group_key=? FOR UPDATE",String.class,group);
        List<JSONObject> links=jdbc.query("SELECT source_type,source_record_id,closure_version FROM helmet_event_link WHERE event_id=? FOR UPDATE",
                (rs,n)->WearableModel.object("type",rs.getString(1),"id",rs.getLong(2),"version",rs.getInt(3)),id);
        if(links.isEmpty()) return;
        java.sql.Timestamp when=java.sql.Timestamp.from(java.time.Instant.parse(verification.getString("submittedAt")));
        for(JSONObject link:links) {
        if(link.getIntValue("version")>=event.getIntValue("version")) continue;
        int changed;
        if("real_time_alarm".equals(link.getString("type"))) {
            changed=jdbc.update("UPDATE real_time_alarm SET is_handled=1,handle_time=?,update_by=?,update_time=? WHERE id=? AND create_by='direct-helmet' AND del_flag='0'",
                    when,verification.getString("actorId"),when,link.getLong("id"));
        } else if("sos_alarm_record".equals(link.getString("type"))) {
            changed=jdbc.update("UPDATE sos_alarm_record SET process_status=1,handler=?,handle_time=?,update_by=?,update_time=? WHERE id=? AND create_by='direct-helmet' AND del_flag='0'",
                    verification.getString("actorId"),when,verification.getString("actorId"),when,link.getLong("id"));
        } else throw new IllegalStateException("未知告警来源");
        if(changed!=1 && (changed!=0 || jdbc.queryForObject("SELECT COUNT(*) FROM "+link.getString("type")
                +" WHERE id=? AND create_by='direct-helmet' AND del_flag='0'",Integer.class,link.getLong("id"))!=1))
            throw new IllegalStateException("告警原始记录核验同步失败");
        jdbc.update("UPDATE helmet_event_link SET closure_version=? WHERE source_type=? AND source_record_id=?",
                event.getIntValue("version"),link.getString("type"),link.getLong("id"));
        }
        jdbc.update("UPDATE helmet_event_group SET open_event_id=NULL WHERE open_event_id=?",id);
    }
}
