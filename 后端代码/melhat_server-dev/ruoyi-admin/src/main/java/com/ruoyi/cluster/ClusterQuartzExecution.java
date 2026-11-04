package com.ruoyi.cluster;
import com.ruoyi.common.core.ClusterJobExecution;
import org.springframework.stereotype.Component;
import org.apache.commons.codec.digest.DigestUtils;
import java.util.*;
@Component
public class ClusterQuartzExecution implements ClusterJobExecution {
    private final ClusterIdentity identity;private final ClusterDatabase db;private final ClusterWorkCoordinator work;
    public ClusterQuartzExecution(ClusterIdentity identity,ClusterDatabase db,ClusterWorkCoordinator work){this.identity=identity;this.db=db;this.work=work;}
    public boolean execute(String jobKey,String firingKey,Invocation invocation)throws Exception{
        if(!identity.enabled()){invocation.run();return true;}
        // Per-job lease prevents overlap; durable firing claim prevents a delayed second scheduler.
        Boolean result=work.run("quartz:"+DigestUtils.sha256Hex(jobKey),true,()->{
            String id=DigestUtils.sha256Hex(jobKey+"\n"+firingKey),claim=UUID.randomUUID().toString();
            boolean accepted=work.fenced(()->{List<String> states=db.jdbc.query("SELECT state FROM wearable_media_effect WHERE effect_key=?",(r,n)->r.getString(1),id);if(!states.isEmpty()&&!"NOT_SENT".equals(states.get(0)))return false;long now=db.now();
                if(!states.isEmpty()){db.jdbc.update("UPDATE wearable_media_effect SET state='IN_FLIGHT',node_id=?,generation=?,claim_token=?,updated_at=? WHERE effect_key=? AND state='NOT_SENT'",identity.nodeId(),identity.generation(),claim,now,id);return true;}
                db.jdbc.update("INSERT INTO wearable_media_effect(effect_key,operation_id,fingerprint,method,effect_path,node_id,generation,claim_token,state,created_at,updated_at) VALUES(?,?,?,'JOB',?,?,?,?,'IN_FLIGHT',?,?)",id,id,id,"quartz:"+jobKey,identity.nodeId(),identity.generation(),claim,now,now);return true;});
            if(!accepted)return false;
            boolean invoked=false;
            try{work.beforeEffect();invoked=true;invocation.run();work.fenced(()->{db.jdbc.update("UPDATE wearable_media_effect SET state='CONFIRMED',updated_at=? WHERE effect_key=? AND claim_token=? AND state='IN_FLIGHT'",db.now(),id,claim);return null;});}
            catch(Exception e){db.jdbc.update("UPDATE wearable_media_effect SET state=?,updated_at=? WHERE effect_key=? AND claim_token=? AND state='IN_FLIGHT'",invoked?"UNKNOWN":"NOT_SENT",db.now(),id,claim);throw new IllegalStateException("Quartz运行未确认，禁止自动重放该次任务",e);}return true;});
        return Boolean.TRUE.equals(result);
    }
}
