package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Repository;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.core.io.ClassPathResource;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.dao.DuplicateKeyException;
import java.util.*;
import java.util.function.Function;
import static com.ruoyi.melhat.split.SplitTelemetry.*;

/** Private durable protocol journals. No network or ledger callbacks while SQL locks are held. */
@Repository
public class SplitHelmetStore {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    public SplitHelmetStore(JdbcTemplate jdbc,SplitHelmetProperties properties){
        this.jdbc=jdbc;tx=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        if(properties.isEnabled())new ResourceDatabasePopulator(new ClassPathResource("db/20261116_split_helmet.sql")).execute(jdbc.getDataSource());
    }
    public JSONObject inbox(String id){return one("SELECT body FROM split_helmet_inbox WHERE ingress_id=?",id);}
    public boolean receive(JSONObject row){
        try{jdbc.update("INSERT INTO split_helmet_inbox(ingress_id,device_id,kind,received_at,fingerprint,body) VALUES(?,?,?,?,?,?)",row.getString("ingressId"),row.getString("deviceId"),row.getString("kind"),row.getLongValue("receivedMillis"),row.getString("fingerprint"),row.toJSONString());return true;}
        catch(DuplicateKeyException duplicate){JSONObject old=inbox(row.getString("ingressId"));if(old==null||!Objects.equals(old.getString("fingerprint"),row.getString("fingerprint")))throw fail(409,"INGRESS_CONFLICT","回调编号已用于其他报文");return false;}
    }
    public List<JSONObject> pending(){return list("SELECT body FROM split_helmet_inbox WHERE projected=0 ORDER BY received_at,ingress_id LIMIT 100");}
    public void delivered(String id){jdbc.update("UPDATE split_helmet_inbox SET projected=1 WHERE ingress_id=?",id);}
    /** projected: 0=PENDING, 1=PROCESSED, 2=REJECTED; rejected raw bodies remain auditable. */
    public void rejected(String id){jdbc.update("UPDATE split_helmet_inbox SET projected=2 WHERE ingress_id=?",id);}
    public JSONObject state(String sn){JSONObject s=one("SELECT body FROM split_helmet_state WHERE device_id=?",sn);return s==null?new JSONObject():s;}
    public void state(String sn,Function<JSONObject,JSONObject> edit){tx.execute(t->{
        jdbc.update("INSERT INTO split_helmet_state(device_id,body) VALUES(?,'{}') ON DUPLICATE KEY UPDATE device_id=device_id",sn);
        JSONObject s=one("SELECT body FROM split_helmet_state WHERE device_id=? FOR UPDATE",sn);JSONObject next=edit.apply(s);
        jdbc.update("UPDATE split_helmet_state SET body=? WHERE device_id=?",next.toJSONString(),sn);return null;});}
    public JSONObject session(String id){return one("SELECT body FROM split_helmet_session WHERE id=?",id);}
    public JSONObject sessionRequest(String actor,String key){return one("SELECT body FROM split_helmet_session WHERE actor_id=? AND request_key=?",actor,key);}
    public void acquire(JSONObject session){
        try{tx.execute(t->{
            jdbc.update("INSERT INTO split_helmet_session(id,actor_id,request_key,fingerprint,status,expires_at,body) VALUES(?,?,?,?,?,?,?)",session.getString("id"),session.getString("actorId"),session.getString("requestKey"),session.getString("fingerprint"),session.getString("status"),session.getLongValue("expiresMillis"),session.toJSONString());
            List<String> ids=new ArrayList<>(session.getJSONArray("deviceIds").toJavaList(String.class));Collections.sort(ids);
            for(String sn:ids)jdbc.update("INSERT INTO split_helmet_lease(device_id,session_id) VALUES(?,?)",sn,session.getString("id"));return null;});}
        catch(DuplicateKeyException busy){throw fail(409,"CALL_BUSY","所选安全帽存在未结束会话，请先结束原会话");}
    }
    public boolean owns(String session,String sn){return jdbc.queryForObject("SELECT COUNT(*) FROM split_helmet_lease WHERE device_id=? AND session_id=?",Integer.class,sn,session)>0;}
    public void saveSession(JSONObject row){jdbc.update("UPDATE split_helmet_session SET status=?,expires_at=?,body=? WHERE id=?",row.getString("status"),row.getLongValue("expiresMillis"),row.toJSONString(),row.getString("id"));}
    public void release(JSONObject row){tx.execute(t->{saveSession(row);jdbc.update("DELETE FROM split_helmet_lease WHERE session_id=?",row.getString("id"));return null;});}
    public void releaseDevice(String id,String sn){jdbc.update("DELETE FROM split_helmet_lease WHERE session_id=? AND device_id=?",id,sn);}
    public List<JSONObject> activeSessions(){return list("SELECT body FROM split_helmet_session WHERE status NOT IN ('ended','failed') ORDER BY expires_at LIMIT 100");}
    public JSONObject command(String id){return one("SELECT body FROM split_helmet_command WHERE id=?",id);}
    public JSONObject commandRequest(String actor,String key){return one("SELECT body FROM split_helmet_command WHERE actor_id=? AND request_key=?",actor,key);}
    public void commandIntent(JSONObject row){jdbc.update("INSERT INTO split_helmet_command(id,actor_id,device_id,request_key,fingerprint,created_at,body) VALUES(?,?,?,?,?,?,?)",row.getString("id"),row.getString("actorId"),row.getString("deviceId"),row.getString("requestKey"),row.getString("fingerprint"),row.getLongValue("createdMillis"),row.toJSONString());}
    public void saveCommand(JSONObject row){jdbc.update("UPDATE split_helmet_command SET body=? WHERE id=?",row.toJSONString(),row.getString("id"));}
    public List<JSONObject> commands(String sn){return list("SELECT body FROM split_helmet_command WHERE device_id=? ORDER BY created_at DESC LIMIT 100",sn);}
    /** A display page must never define the lifetime of a recording or its eventual file correlation. */
    public List<JSONObject> mediaCommands(String sn){return list("SELECT body FROM split_helmet_command WHERE device_id=? AND (body LIKE ? OR body LIKE ?) ORDER BY created_at DESC",sn,"%\"action\":\"start_recording\"%","%\"action\":\"take_photo\"%");}
    /** File authorization outlives the rolling command display; private origins never enter public projections. */
    public void saveFile(String sn,JSONObject item,String key,String sourceUrl){
        long observed=0;try{observed=java.time.Instant.parse(item.getString("createdAt")).toEpochMilli();}catch(RuntimeException ignored){}
        jdbc.update("INSERT INTO split_helmet_file(id,device_id,file_key,observed_at,body,source_url,refreshed_at) VALUES(?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE body=VALUES(body),source_url=VALUES(source_url),observed_at=VALUES(observed_at),refreshed_at=VALUES(refreshed_at)",
                item.getString("id"),sn,key,observed,item.toJSONString(),sourceUrl,System.currentTimeMillis());
    }
    public JSONObject file(String sn,String id){
        List<JSONObject> found=jdbc.query("SELECT body,file_key,source_url,refreshed_at FROM split_helmet_file WHERE device_id=? AND id=?",(rs,n)->{
            JSONObject item=JSONObject.parseObject(rs.getString(1));item.put("privateFileKey",rs.getString(2));item.put("privateSourceUrl",rs.getString(3));item.put("privateRefreshedAt",rs.getLong(4));return item;
        },sn,id);return found.isEmpty()?null:found.get(0);
    }
    public List<JSONObject> files(String sn){return list("SELECT body FROM split_helmet_file WHERE device_id=? ORDER BY observed_at DESC,id",sn);}
    public List<JSONObject> unfinishedCommands(){List<JSONObject> rows=list("SELECT body FROM split_helmet_command WHERE body LIKE ? ORDER BY created_at","%\"action\":\"start_recording\"%");rows.removeIf(r->!"start_recording".equals(r.getString("action"))||Arrays.asList("completed","stopped","failed").contains(r.getString("status")));return rows;}
    private JSONObject one(String sql,Object...args){List<JSONObject> rows=list(sql,args);return rows.isEmpty()?null:rows.get(0);}
    private List<JSONObject> list(String sql,Object...args){return jdbc.query(sql,(r,n)->JSONObject.parseObject(r.getString(1)),args);}
}
