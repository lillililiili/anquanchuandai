package com.ruoyi.portal.demo;

import java.util.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ruoyi.portal.*;
import com.ruoyi.portal.demo.DemoAssignmentController.*;

@Service @Profile("portal-demo")
public class DemoAssignmentService {
    private final JdbcTemplate db;private final PortalAccess access;private final DemoPeopleSource source;private final ObjectMapper json;
    public DemoAssignmentService(JdbcTemplate db,PortalAccess access,DemoPeopleSource source,ObjectMapper json){this.db=db;this.access=access;this.source=source;this.json=json;}
    private PortalException conflict(){return new PortalException(409,"VERSION_OR_ASSIGNMENT_CONFLICT","记录已变化或装备已被领用，请刷新后重试");}
    private String authorize(String site){String actor=access.actorId();access.require("portal:equipment:assign");if(!PortalQuery.id(site))throw PortalException.invalid();source.scope(actor,site);return actor;}
    public Object options(String site,String person){String actor=authorize(site);if(source.person(actor,site,person)==null)throw PortalException.missing();Map<String,Object> result=new LinkedHashMap<>();result.put("available",db.queryForList("SELECT id,code,type,version FROM portal_device d WHERE site_id=? AND NOT EXISTS(SELECT 1 FROM portal_assignment a WHERE a.device_id=d.id AND ended_at IS NULL) ORDER BY code",site));result.put("current",db.queryForList("SELECT a.id,a.version,a.device_id AS deviceId,d.code,d.type FROM portal_assignment a JOIN portal_device d ON d.id=a.device_id WHERE a.site_id=? AND a.person_id=? AND a.ended_at IS NULL",site,person));return result;}
    private String hash(String data){try{byte[] bytes=MessageDigest.getInstance("SHA-256").digest(data.getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder();for(byte b:bytes)out.append(String.format("%02x",b));return out.toString();}catch(Exception e){throw new IllegalStateException(e);}}
    private Object previous(String actor,String key,String operation,String payload){
        if(!PortalQuery.id(key))throw PortalException.invalid();String digest=hash(payload);
        db.update("INSERT IGNORE INTO portal_idempotency(actor_id,request_key,operation,request_hash) VALUES(?,?,?,?)",actor,key,operation,digest);
        Map<String,Object> r=db.queryForMap("SELECT operation,request_hash,response_json FROM portal_idempotency WHERE actor_id=? AND request_key=? FOR UPDATE",actor,key);
        if(!operation.equals(r.get("operation"))||!digest.equals(r.get("request_hash")))throw new PortalException(409,"IDEMPOTENCY_CONFLICT","同一幂等键不能用于不同操作");
        try{return r.get("response_json")==null?null:json.readValue(r.get("response_json").toString(),Map.class);}catch(Exception e){throw new IllegalStateException(e);}
    }
    private Object finish(String actor,String site,String object,String action,String key,long version){
        Map<String,Object> result=new LinkedHashMap<>();result.put("id",object);result.put("version",version);result.put("environment","SIMULATED");
        db.update("INSERT INTO portal_audit VALUES(?,?,?,?,?,UTC_TIMESTAMP(3),'SUCCESS')",UUID.randomUUID().toString(),actor,site,object,action);
        try{db.update("UPDATE portal_idempotency SET response_json=? WHERE actor_id=? AND request_key=?",json.writeValueAsString(result),actor,key);}catch(Exception e){throw new IllegalStateException(e);}return result;
    }
    @Transactional public Object issue(String key,Issue body){
        if(body==null||!PortalQuery.id(body.personId)||!PortalQuery.id(body.deviceId))throw PortalException.invalid();String actor=authorize(body.siteId);
        Object previous=previous(actor,key,"ISSUE",body.siteId+"|"+body.personId+"|"+body.deviceId);if(previous!=null)return previous;
        List<Map<String,Object>> people=db.queryForList("SELECT id FROM portal_person WHERE site_id=? AND id=? FOR UPDATE",body.siteId,body.personId);
        List<Map<String,Object>> devices=db.queryForList("SELECT type FROM portal_device WHERE site_id=? AND id=? FOR UPDATE",body.siteId,body.deviceId);
        if(people.isEmpty()||devices.isEmpty())throw PortalException.missing();String type=devices.get(0).get("type").toString();
        if(db.queryForObject("SELECT COUNT(*) FROM portal_assignment WHERE ended_at IS NULL AND (device_id=? OR (person_id=? AND device_type=?))",Integer.class,body.deviceId,body.personId,type)>0)throw conflict();
        String id=UUID.randomUUID().toString();db.update("INSERT INTO portal_assignment(id,site_id,person_id,device_id,device_type,started_at) VALUES(?,?,?,?,?,UTC_TIMESTAMP(3))",id,body.siteId,body.personId,body.deviceId,type);
        db.update("INSERT INTO portal_assignment_history VALUES(?,?,?,?,?,'ISSUE',UTC_TIMESTAMP(3),?)",UUID.randomUUID().toString(),id,body.siteId,body.personId,body.deviceId,actor);
        return finish(actor,body.siteId,id,"ISSUE",key,1);
    }
    @Transactional public Object giveBack(String id,String key,Return body){
        if(body==null||!PortalQuery.id(id)||body.version==null||body.version<1)throw PortalException.invalid();String actor=authorize(body.siteId);
        Object previous=previous(actor,key,"RETURN",body.siteId+"|"+id+"|"+body.version);if(previous!=null)return previous;
        List<Map<String,Object>> rows=db.queryForList("SELECT * FROM portal_assignment WHERE site_id=? AND id=? FOR UPDATE",body.siteId,id);if(rows.isEmpty())throw PortalException.missing();Map<String,Object> r=rows.get(0);
        if(r.get("ended_at")!=null||((Number)r.get("version")).longValue()!=body.version)throw conflict();
        db.update("UPDATE portal_assignment SET ended_at=UTC_TIMESTAMP(3),version=version+1 WHERE id=?",id);
        db.update("INSERT INTO portal_assignment_history VALUES(?,?,?,?,?,'RETURN',UTC_TIMESTAMP(3),?)",UUID.randomUUID().toString(),id,body.siteId,r.get("person_id"),r.get("device_id"),actor);
        return finish(actor,body.siteId,id,"RETURN",key,body.version+1);
    }
}
