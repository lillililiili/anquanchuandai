package com.ruoyi.cluster;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.apache.commons.codec.digest.DigestUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import java.util.function.Supplier;

/** A claim is committed BEFORE I/O. IN_FLIGHT survives death and is never reclaimed to send again.
 * Outcome payloads are encrypted because account/stream responses contain private credentials. */
@Component
public class MediaOperationJournal {
    private final ClusterDatabase db;private final ClusterIdentity identity;private final ClusterWorkCoordinator work;private final byte[] key;
    public MediaOperationJournal(ClusterDatabase db,ClusterIdentity identity,ClusterWorkCoordinator work,
            @Value("${melhat.business.media-encryption-key:${MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY:}}")String key){
        this.db=db;this.identity=identity;this.work=work;this.key=key.isEmpty()?null:Base64.getDecoder().decode(key);
        if(identity.enabled()&&(this.key==null||this.key.length!=32))throw new IllegalStateException("Cluster media journal requires the shared 32-byte encryption key");
    }
    public static String canonical(Object value){
        if(value instanceof JSONObject){Map<String,Object> out=new TreeMap<>();((JSONObject)value).forEach((k,v)->out.put(k,normalize(v)));return JSON.toJSONString(out);}
        return JSON.toJSONString(normalize(value));
    }
    private static Object normalize(Object v){if(v instanceof Map){Map<String,Object> r=new TreeMap<>();((Map<?,?>)v).forEach((k,x)->r.put(String.valueOf(k),normalize(x)));return r;}if(v instanceof Collection){List<Object> r=new ArrayList<>();for(Object x:(Collection<?>)v)r.add(normalize(x));return r;}return v;}
    public JSONObject execute(String method,String path,JSONObject body,Supplier<JSONObject> send,java.util.function.Function<String,JSONObject> lookup){
        if(!identity.enabled()||"GET".equals(method)||"/device-stream-status".equals(path))return send.get();
        String fingerprint=DigestUtils.sha256Hex(method+"\n"+path+"\n"+canonical(body));
        String operation=body==null?path:body.getString("requestId");if(operation==null&&body!=null)operation=body.getString("callId");if(operation==null&&body!=null)operation=body.getString("sessionId");if(operation==null)operation=path;
        final String operationId=operation;String claim=UUID.randomUUID().toString();
        JSONObject prior=work.fenced(()->{work.beforeEffect();
            List<JSONObject> rows=db.jdbc.query("SELECT state,response_json FROM wearable_media_effect WHERE effect_key=?",(r,n)->{JSONObject v=new JSONObject();v.put("state",r.getString(1));v.put("response",r.getString(2));return v;},fingerprint);
            if(!rows.isEmpty()) {
                if(!"NOT_SENT".equals(rows.get(0).getString("state")))return rows.get(0);
                db.jdbc.update("UPDATE wearable_media_effect SET state='IN_FLIGHT',node_id=?,generation=?,claim_token=?,updated_at=? WHERE effect_key=? AND state='NOT_SENT'",identity.nodeId(),identity.generation(),claim,db.now(),fingerprint);
                return null;
            }
            long now=db.now();db.jdbc.update("INSERT INTO wearable_media_effect(effect_key,operation_id,fingerprint,method,effect_path,node_id,generation,claim_token,state,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'IN_FLIGHT',?,?)",fingerprint,operationId,fingerprint,method,path,identity.nodeId(),identity.generation(),claim,now,now);return null;});
        if(prior!=null){if("CONFIRMED".equals(prior.getString("state")))return JSON.parseObject(decrypt(prior.getString("response")));
            try{JSONObject evidence=lookup.apply(fingerprint);if(fingerprint.equals(evidence.getString("fingerprint"))&&evidence.getJSONObject("result")!=null){JSONObject result=evidence.getJSONObject("result");resolve(method,path,body,result);return result;}}catch(RuntimeException unavailable){/* No confirmed evidence: never resend. */}
            throw new IllegalStateException("媒体副作用结果待核对（UNKNOWN），禁止重复发送；请查询原操作或联系管理员核对");}
        boolean invoked=false;
        try {afterClaim();work.beforeEffect();invoked=true;JSONObject response=send.get();
            work.fenced(()->{if(db.jdbc.update("UPDATE wearable_media_effect SET state='CONFIRMED',response_json=?,updated_at=? WHERE effect_key=? AND claim_token=? AND state='IN_FLIGHT'",encrypt(response.toJSONString()),db.now(),fingerprint,claim)!=1)throw new IllegalStateException("Media effect claim was fenced");return null;});return response;
        }catch(RuntimeException e){
            // Keep evidence even when this worker has lost its lease. This transition cannot authorize work.
            try{db.jdbc.update("UPDATE wearable_media_effect SET state=?,updated_at=? WHERE effect_key=? AND claim_token=? AND state='IN_FLIGHT'",invoked?"UNKNOWN":"NOT_SENT",db.now(),fingerprint,claim);}catch(RuntimeException ignored){}
            throw e;
        }
    }
    protected void afterClaim() { }
    /** Only verified read-side evidence may resolve an unknown claim; no retrying a write as a query. */
    public void resolve(String method,String path,JSONObject body,JSONObject evidence){
        String fingerprint=DigestUtils.sha256Hex(method+"\n"+path+"\n"+canonical(body));
        work.fenced(()->{db.jdbc.update("UPDATE wearable_media_effect SET state='CONFIRMED',response_json=?,updated_at=? WHERE effect_key=? AND state IN ('UNKNOWN','IN_FLIGHT')",encrypt(evidence.toJSONString()),db.now(),fingerprint);return null;});
    }
    public int reconcile(java.util.function.Function<String,JSONObject> lookup){
        int resolved=0;
        for(String fingerprint:db.jdbc.query("SELECT effect_key FROM wearable_media_effect WHERE state IN ('IN_FLIGHT','UNKNOWN') AND method<>'JOB'",(r,n)->r.getString(1))){
            try{JSONObject evidence=lookup.apply(fingerprint);JSONObject result=evidence.getJSONObject("result");
                if(!fingerprint.equals(evidence.getString("fingerprint"))||result==null)continue;
                resolved+=work.evidenceWrite(()->db.jdbc.update("UPDATE wearable_media_effect SET state='CONFIRMED',response_json=?,updated_at=? WHERE effect_key=? AND state IN ('IN_FLIGHT','UNKNOWN')",encrypt(result.toJSONString()),db.now(),fingerprint));
            }catch(RuntimeException unavailable){/* Retain durable uncertainty; inspection may be required. */}
        }
        return resolved;
    }
    private String encrypt(String value){try{byte[] nonce=new byte[12];new SecureRandom().nextBytes(nonce);Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce));byte[] encrypted=cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));byte[] out=new byte[12+encrypted.length];System.arraycopy(nonce,0,out,0,12);System.arraycopy(encrypted,0,out,12,encrypted.length);return Base64.getEncoder().encodeToString(out);}catch(Exception e){throw new IllegalStateException("Media evidence encryption unavailable",e);}}
    private String decrypt(String value){try{byte[] bytes=Base64.getDecoder().decode(value);Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,Arrays.copyOf(bytes,12)));return new String(cipher.doFinal(Arrays.copyOfRange(bytes,12,bytes.length)),StandardCharsets.UTF_8);}catch(Exception e){throw new IllegalStateException("Media evidence decryption unavailable",e);}}
}
