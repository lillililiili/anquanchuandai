package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.util.*;
import java.util.regex.Pattern;
import static com.ruoyi.guardian.WearableModel.*;

/** External responses are retained independently from local assets and workflow state. */
@Service
public class ExternalDataStore {
    private final JdbcTemplate jdbc;
    private static final Pattern SECRET=Pattern.compile("password|passwd|token|secret|authorization|cookie|credential|sip_pwd|pushUrl|wssUrl|iceServers",Pattern.CASE_INSENSITIVE);
    public ExternalDataStore(JdbcTemplate jdbc){this.jdbc=jdbc;
        jdbc.execute("CREATE TABLE IF NOT EXISTS external_integration (id VARCHAR(100) PRIMARY KEY,site_id VARCHAR(100) NOT NULL,kind VARCHAR(40) NOT NULL,version INT NOT NULL,body LONGTEXT NOT NULL)");
        jdbc.execute("CREATE TABLE IF NOT EXISTS external_data_record (id VARCHAR(100) PRIMARY KEY,integration_id VARCHAR(100) NOT NULL,site_id VARCHAR(100) NOT NULL,kind VARCHAR(40) NOT NULL,direction VARCHAR(12) NOT NULL,external_key VARCHAR(100) NOT NULL,received_at VARCHAR(40) NOT NULL,status VARCHAR(40) NOT NULL,body LONGTEXT NOT NULL,UNIQUE(integration_id,kind,direction,external_key))");
    }
    public JSONArray integrations(GuardianAccess.Context ctx,String site){JSONArray result=new JSONArray();
        for(String body:jdbc.query("SELECT body FROM external_integration ORDER BY site_id,id",(rs,n)->rs.getString(1))){JSONObject row=JSONObject.parseObject(body);if((site==null||site.equals(row.getString("siteId")))&&ctx.can("integrations:read",row.getString("siteId"),null))result.add(publicIntegration(row));}return result;}
    public JSONObject records(GuardianAccess.Context ctx,String site,String integrationId,int page,int pageSize){
        if(page<1||pageSize<1||pageSize>200)throw AdminQueryService.fail(400,"INVALID_PAGE","分页参数无效");
        List<String> allowed=new ArrayList<>();for(Object raw:rows(ctx.data,"sites")){String s=((JSONObject)raw).getString("id");if((site==null||site.equals(s))&&ctx.can("integrations:read",s,null))allowed.add(s);}
        if(allowed.isEmpty())return object("items",new JSONArray(),"total",0,"page",page,"pageSize",pageSize);
        String placeholders=String.join(",",Collections.nCopies(allowed.size(),"?"));String where=" WHERE site_id IN ("+placeholders+")";List<Object> args=new ArrayList<Object>(allowed);
        if(integrationId!=null&&!integrationId.isEmpty()){where+=" AND integration_id=?";args.add(integrationId);}
        Long total=jdbc.queryForObject("SELECT COUNT(*) FROM external_data_record"+where,Long.class,args.toArray());
        args.add(pageSize);args.add((page-1)*pageSize);JSONArray out=new JSONArray();
        for(String body:jdbc.query("SELECT body FROM external_data_record"+where+" ORDER BY received_at DESC,id LIMIT ? OFFSET ?",(rs,n)->rs.getString(1),args.toArray()))out.add(redact(JSONObject.parseObject(body)));
        return object("items",out,"total",total,"page",page,"pageSize",pageSize);
    }
    private JSONObject get(String id){List<String> values=jdbc.query("SELECT body FROM external_integration WHERE id=?",(rs,n)->rs.getString(1),id);return values.isEmpty()?null:JSONObject.parseObject(values.get(0));}
    private void put(JSONObject row){if(jdbc.update("UPDATE external_integration SET site_id=?,kind=?,version=?,body=? WHERE id=?",row.get("siteId"),row.get("kind"),row.getIntValue("version"),row.toJSONString(),row.get("id"))==0)jdbc.update("INSERT INTO external_integration(id,site_id,kind,version,body) VALUES(?,?,?,?,?)",row.get("id"),row.get("siteId"),row.get("kind"),row.getIntValue("version"),row.toJSONString());}
    /** Called only after a real adapter response. No public endpoint can manufacture a receipt. */
    public synchronized void record(String source,String name,String site,String kind,String externalId,JSONObject payload,String localId){
        if(site==null||site.isEmpty()||externalId==null||externalId.isEmpty())return;
        String integrationId="adapter-"+source+"-"+site;JSONObject integration=get(integrationId);String now=Instant.now().toString();
        if(integration==null)integration=object("id",integrationId,"siteId",site,"kind",kind,"name",name,"enabled",true,"version",1,"managed",true,"endpoint","","credentialRef","");
        integration.put("status","CONNECTED");integration.put("lastSyncAt",now);integration.put("lastError",null);put(integration);
        String key=org.apache.commons.codec.digest.DigestUtils.sha256Hex(externalId),id="ED-"+org.apache.commons.codec.digest.DigestUtils.sha256Hex(integrationId+"\n"+kind+"\nIN\n"+externalId);
        JSONObject row=object("id",id,"integrationId",integrationId,"siteId",site,"kind",kind,"direction","IN","externalId",externalId,"payload",redact(payload),"localId",localId,"status","RECEIVED","receivedAt",now,"processedAt",now,"error",null);
        if(jdbc.update("UPDATE external_data_record SET received_at=?,status=?,body=? WHERE id=?",now,"RECEIVED",row.toJSONString(),id)==0)jdbc.update("INSERT INTO external_data_record(id,integration_id,site_id,kind,direction,external_key,received_at,status,body) VALUES(?,?,?,?,?,?,?,?,?)",id,integrationId,site,kind,"IN",key,now,"RECEIVED",row.toJSONString());
    }
    static Object redact(Object value){if(value instanceof JSONObject){JSONObject out=new JSONObject();for(Map.Entry<String,Object> e:((JSONObject)value).entrySet())if(!SECRET.matcher(e.getKey()).find())out.put(e.getKey(),redact(e.getValue()));return out;}if(value instanceof JSONArray){JSONArray out=new JSONArray();for(Object v:(JSONArray)value)out.add(redact(v));return out;}if(value instanceof String&&((String)value).matches("(?i)https?://.*")){try{java.net.URI u=java.net.URI.create((String)value);return new java.net.URI(u.getScheme(),null,u.getHost(),u.getPort(),u.getPath(),null,null).toString();}catch(Exception e){return "[地址已隐藏]";}}return value;}
    private JSONObject publicIntegration(JSONObject row){JSONObject out=copy(row);out.remove("updatedBy");return out;}
}
