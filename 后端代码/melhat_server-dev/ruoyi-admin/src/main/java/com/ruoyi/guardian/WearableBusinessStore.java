package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionTemplate;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.function.Supplier;

/** SQL is authoritative after a namespace's first successful import. JSON files are never rewritten. */
@Repository
public class WearableBusinessStore {
    public static final class Snapshot {
        public final JSONObject state;
        public final long revision;
        Snapshot(JSONObject state, long revision) { this.state = state; this.revision = revision; }
    }
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transactions;
    private final byte[] mediaKey;
    private final boolean lockingReads;
    private final FudaAlarmJournal alarmJournal;
    private static final Object BUSINESS_LOCK = new Object();
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Map<String, String> GUARDIAN = new LinkedHashMap<String, String>();
    private static final Map<String, String> MEDIA = new LinkedHashMap<String, String>();
    static {
        for (String name : Arrays.asList("stations", "people", "bindings", "mapAreas")) GUARDIAN.put(name, "wearable_projection");
        GUARDIAN.put("devices", "wearable_device_state"); GUARDIAN.put("locations", "wearable_location");
        GUARDIAN.put("events", "wearable_event"); GUARDIAN.put("eventOperations", "wearable_event_operation");
        GUARDIAN.put("assistance", "wearable_assistance"); GUARDIAN.put("works", "wearable_work");
        GUARDIAN.put("fences", "wearable_fence"); GUARDIAN.put("fenceRecords", "wearable_fence_record");
        GUARDIAN.put("groups", "wearable_group"); GUARDIAN.put("vitals", "wearable_vital");
        GUARDIAN.put("audit", "wearable_business_audit");
        for (String name : Arrays.asList("calls", "broadcasts", "sharedCommunications", "voiceSessions")) GUARDIAN.put(name, "wearable_communication");
        GUARDIAN.put("media", "wearable_media_asset"); GUARDIAN.put("uploads", "wearable_media_asset");
        MEDIA.put("accounts", "wearable_media_account"); MEDIA.put("commands", "wearable_device_command");
        MEDIA.put("calls", "wearable_communication"); MEDIA.put("streams", "wearable_media_stream");
    }

    public WearableBusinessStore(JdbcTemplate jdbc) { this(jdbc, ""); }
    @Autowired
    public WearableBusinessStore(JdbcTemplate jdbc,
            @Value("${melhat.business.media-encryption-key:${MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY:}}") String encodedKey) {
        this(jdbc,encodedKey,true);
    }
    private WearableBusinessStore(JdbcTemplate jdbc,String encodedKey,boolean initialize) {
        this(jdbc,encodedKey,initialize,true);
    }
    private WearableBusinessStore(JdbcTemplate jdbc,String encodedKey,boolean initialize,boolean lockingReads) {
        this.lockingReads = lockingReads;
        this.jdbc = jdbc;
        this.transactions = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        try { this.mediaKey = encodedKey == null || encodedKey.trim().isEmpty() ? null : Base64.getDecoder().decode(encodedKey.trim()); }
        catch (IllegalArgumentException error) { throw new IllegalStateException("媒体数据库加密密钥必须为 Base64 编码", error); }
        if (mediaKey != null && mediaKey.length != 32) throw new IllegalStateException("媒体数据库加密密钥必须包含32字节");
        if(initialize)new ResourceDatabasePopulator(new ClassPathResource("db/20261026_wearable_business.sql")).execute(jdbc.getDataSource());
        this.alarmJournal = lockingReads ? new FudaAlarmJournal(jdbc) : null;
        if(initialize) this.alarmJournal.initialize();
    }

    public static WearableBusinessStore readOnly(JdbcTemplate jdbc,String encodedKey) { return new WearableBusinessStore(jdbc,encodedKey,false,false); }
    public static WearableBusinessStore existing(JdbcTemplate jdbc,String encodedKey) { return new WearableBusinessStore(jdbc,encodedKey,false,true); }
    /** Keep the existing single-process write serialization across a receipt's entire SQL transaction. */
    public static Object transactionLock() { return BUSINESS_LOCK; }

    /** Import only on first use. A corrupt legacy file fails closed instead of falling back to sample data. */
    public synchronized Snapshot load(String namespace, Path legacyFile, Supplier<JSONObject> empty) {
        requireNamespace(namespace);
        List<String> existing = jdbc.query("SELECT namespace FROM wearable_business_meta WHERE namespace=?", (rs,n)->rs.getString(1), namespace);
        if (existing.isEmpty()) {
            Integer orphaned=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_document WHERE namespace=?",Integer.class,namespace);
            if(orphaned!=null && orphaned>0)throw new IllegalStateException("业务迁移标记缺失但数据库已有数据，禁止重新导入");
            JSONObject initial;
            String digest = null, source = null;
            try {
                if (legacyFile != null && Files.exists(legacyFile)) {
                    byte[] bytes = Files.readAllBytes(legacyFile);
                    initial = JSON.parseObject(new String(bytes, StandardCharsets.UTF_8));
                    if (initial == null || "guardian".equals(namespace) && (initial.getIntValue("version") != 1 || initial.getJSONArray("stations") == null))
                        throw new IllegalStateException("历史业务文件格式无效，禁止覆盖");
                    source = legacyFile.toAbsolutePath().normalize().toString(); digest = sha256(bytes);
                    Path backup = legacyFile.resolveSibling(legacyFile.getFileName() + ".pre-sql.bak");
                    if (Files.exists(backup)) {
                        if (!Arrays.equals(Files.readAllBytes(backup), bytes)) throw new IllegalStateException("迁移备份与历史业务文件不一致，请先核对");
                    } else Files.copy(legacyFile, backup);
                } else initial = empty.get();
            } catch (Exception error) { throw new IllegalStateException("历史业务数据导入失败，原文件保持不变", error); }
            final JSONObject imported = initial; final String importedSource = source, hash = digest;
            transactions.execute(status -> {
                jdbc.update("INSERT INTO wearable_business_meta (namespace,revision,imported_from,import_sha256,imported_at) VALUES (?,0,?,?,?) ON DUPLICATE KEY UPDATE namespace=namespace",
                        namespace, importedSource, hash, System.currentTimeMillis());
                JSONObject meta = lock(namespace);
                if (meta.getLongValue("revision") == 0) {
                    replace(namespace, imported, true);
                    jdbc.update("UPDATE wearable_business_meta SET revision=1 WHERE namespace=?", namespace);
                }
                return null;
            });
        }
        return read(namespace);
    }

    public Snapshot read(String namespace) {
        requireNamespace(namespace);
        return transactions.execute(status -> {
            JSONObject meta = lock(namespace);
            JSONObject state = new JSONObject();
            jdbc.query("SELECT collection_key, value_type, body FROM wearable_business_document WHERE namespace=? ORDER BY collection_key", rs -> {
                String key = rs.getString(1), type = rs.getString(2);
                if ("scalar".equals(type)) state.put(key, JSON.parse(decode(namespace,key,"$",rs.getString(3))));
                else {
                    String ordering="locations".equals(key)?"observed_at DESC,record_key":"sort_order,record_key";
                    List<Map<String,Object>> rows = jdbc.queryForList("SELECT record_key, body FROM " + table(namespace,key) + " WHERE namespace=? AND collection_key=? ORDER BY "+ordering, namespace,key);
                    if ("array".equals(type)) {
                        JSONArray values = new JSONArray();
                        for (Map<String,Object> row : rows) values.add(JSON.parse(decode(namespace,key,String.valueOf(row.get("record_key")),String.valueOf(row.get("body")))));
                        state.put(key, values);
                    } else {
                        JSONObject values = new JSONObject();
                        for (Map<String,Object> row : rows) values.put(String.valueOf(row.get("record_key")),JSON.parse(decode(namespace,key,String.valueOf(row.get("record_key")),String.valueOf(row.get("body")))));
                        state.put(key,values);
                    }
                }
            }, namespace);
            return new Snapshot(state,meta.getLongValue("revision"));
        });
    }

    /** Optimistic storage revision prevents another instance or a stale cache from overwriting accepted data. */
    public long save(String namespace, long expectedRevision, JSONObject next, Runnable dependentWrite) {
        requireNamespace(namespace);
        return transactions.execute(status -> {
            JSONObject meta=lock(namespace);
            if (meta.getLongValue("revision") != expectedRevision) throw new IllegalStateException("业务数据库版本已变化，请刷新后重试");
            replace(namespace,next);
            if (dependentWrite != null) dependentWrite.run();
            long revision=expectedRevision+1;
            jdbc.update("UPDATE wearable_business_meta SET revision=? WHERE namespace=?",revision,namespace);
            return revision;
        });
    }

    private JSONObject lock(String namespace) {
        List<JSONObject> rows=jdbc.query("SELECT revision,imported_from,import_sha256 FROM wearable_business_meta WHERE namespace=?"+(lockingReads?" FOR UPDATE":""),
                (rs,n)->object("revision",rs.getLong(1),"source",rs.getString(2),"hash",rs.getString(3)),namespace);
        if(rows.size()!=1) throw new IllegalStateException("业务数据尚未完成初始化");
        return rows.get(0);
    }

    private void replace(String namespace,JSONObject state) {
        replace(namespace,state,false);
    }

    private void replace(String namespace,JSONObject state,boolean historicalImport) {
        if(state==null) throw new IllegalArgumentException("缺少业务数据");
        Set<String> previousEventIds="guardian".equals(namespace)
                ? new HashSet<String>(jdbc.query("SELECT record_key FROM wearable_event WHERE namespace='guardian' AND collection_key='events'",(rs,n)->rs.getString(1)))
                : Collections.emptySet();
        Set<String> old=new HashSet<String>(jdbc.query("SELECT collection_key FROM wearable_business_document WHERE namespace=?",(rs,n)->rs.getString(1),namespace));
        for(String key:state.keySet()) {
            if(key.length()>64) throw new IllegalArgumentException("业务集合标识过长");
            Object value=state.get(key);
            String type=value instanceof JSONArray ? "array" : value instanceof JSONObject ? "object" : "scalar";
            LinkedHashMap<String,Object> records=new LinkedHashMap<String,Object>();
            if(value instanceof JSONArray) {
                Map<String,Integer> anonymous=new HashMap<String,Integer>();
                for(Object raw:(JSONArray)value) {
                    String id=raw instanceof JSONObject ? ((JSONObject)raw).getString("id") : null;
                    if(id==null || id.isEmpty()) {
                        String hash=sha256(JSON.toJSONBytes(raw)); int ordinal=anonymous.getOrDefault(hash,0);anonymous.put(hash,ordinal+1);
                        id="legacy-"+hash+"-"+ordinal;
                    }
                    if(records.containsKey(id)) throw new IllegalArgumentException("业务记录编号重复: "+key);
                    records.put(id,raw);
                }
            } else if(value instanceof JSONObject) {
                JSONObject map=(JSONObject)value;for(String id:map.keySet())records.put(id,map.get(id));
            }
            syncRows(namespace,key,records);
            String body="scalar".equals(type) ? encode(namespace,key,"$",JSON.toJSONString(value)) : null;
            jdbc.update("INSERT INTO wearable_business_document (namespace,collection_key,value_type,body) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE value_type=VALUES(value_type),body=VALUES(body)",namespace,key,type,body);
            old.remove(key);
        }
        for(String key:old) {
            // Complete snapshots may trim their location working set; durable history is append-only.
            if(!"locations".equals(key))jdbc.update("DELETE FROM "+table(namespace,key)+" WHERE namespace=? AND collection_key=?",namespace,key);
            jdbc.update("DELETE FROM wearable_business_document WHERE namespace=? AND collection_key=?",namespace,key);
        }
        if("guardian".equals(namespace)) {
            syncActions(state);
            if(alarmJournal!=null) alarmJournal.appendNew(state,previousEventIds,historicalImport);
        }
    }

    private void syncRows(String namespace,String key,LinkedHashMap<String,Object> rows) {
        String table=table(namespace,key);
        Map<String,JSONObject> previous=new HashMap<String,JSONObject>();
        jdbc.query("SELECT record_key,body,sort_order FROM "+table+" WHERE namespace=? AND collection_key=?",rs->{previous.put(rs.getString(1),object("body",rs.getString(2),"order",rs.getInt(3)));},namespace,key);
        int order=0;
        for(Map.Entry<String,Object> entry:rows.entrySet()) {
            String id=entry.getKey();if(id==null || id.length()>512)throw new IllegalArgumentException("业务记录键无效");
            JSONObject prior=previous.remove(id);String json=JSON.toJSONString(entry.getValue());
            if(prior!=null && json.equals(decode(namespace,key,id,prior.getString("body"))) && ("locations".equals(key)||prior.getIntValue("order")==order)){order++;continue;}
            JSONObject row=entry.getValue() instanceof JSONObject?(JSONObject)entry.getValue():new JSONObject();
            Long time=observedAt(row);
            jdbc.update("INSERT INTO "+table+" (namespace,collection_key,record_key,record_id,device_id,person_id,site_id,area_id,event_id,source,observed_at,sort_order,body) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE record_id=VALUES(record_id),device_id=VALUES(device_id),person_id=VALUES(person_id),site_id=VALUES(site_id),area_id=VALUES(area_id),event_id=VALUES(event_id),source=VALUES(source),observed_at=VALUES(observed_at),sort_order=VALUES(sort_order),body=VALUES(body)",
                    namespace,key,id,text(row,"id"),"devices".equals(key)?text(row,"id"):first(row,"deviceId","sn"),text(row,"personId"),text(row,"siteId"),text(row,"areaId"),text(row,"eventId"),first(row,"source","protocol"),time,order++,encode(namespace,key,id,json));
        }
        if(!"locations".equals(key))for(String id:previous.keySet())jdbc.update("DELETE FROM "+table+" WHERE namespace=? AND collection_key=? AND record_key=?",namespace,key,id);
    }

    private void syncActions(JSONObject state) {
        JSONArray events=state.getJSONArray("events");LinkedHashMap<String,Object> actions=new LinkedHashMap<String,Object>();
        if(events!=null)for(Object raw:events) {
            JSONObject event=(JSONObject)raw;String eventId=event.getString("id");
            for(String kind:Arrays.asList("timeline","observations")) {
                JSONArray list=event.getJSONArray(kind);if(list==null)continue;
                for(int i=0;i<list.size();i++) {
                    JSONObject action=object("eventId",eventId,"kind",kind,"ordinal",i,"personId",event.get("personId"),"deviceId",event.get("deviceId"),"siteId",event.get("siteId"),"areaId",event.get("areaId"),"value",list.get(i));
                    actions.put(eventId+":"+kind+":"+i,action);
                }
            }
            if(event.getJSONObject("verification")!=null)actions.put(eventId+":verification",object("eventId",eventId,"kind","verification","value",event.getJSONObject("verification"),"siteId",event.get("siteId"),"deviceId",event.get("deviceId")));
        }
        syncRows("guardian","$eventActions",actions);
    }

    /** The caller supplies a stable receipt ID on replay. Equal payloads with different receipts are preserved. */
    public long appendDeviceReport(String receiptId,String protocol,String deviceId,JSONObject payload) {
        if(receiptId==null || !receiptId.matches("[A-Za-z0-9._:-]{1,128}") || protocol==null || protocol.length()>64 || deviceId==null || deviceId.length()>128 || payload==null)
            throw new IllegalArgumentException("设备接收记录参数无效");
        return transactions.execute(status->{
            jdbc.update("INSERT INTO wearable_device_report (receipt_id,protocol,device_id,received_at,body) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE receipt_id=receipt_id",receiptId,protocol,deviceId,System.currentTimeMillis(),payload.toJSONString());
            JSONObject saved=jdbc.queryForObject("SELECT sequence,protocol,device_id,body FROM wearable_device_report WHERE receipt_id=?",(rs,n)->object("sequence",rs.getLong(1),"protocol",rs.getString(2),"deviceId",rs.getString(3),"body",rs.getString(4)),receiptId);
            if(!protocol.equals(saved.getString("protocol")) || !deviceId.equals(saved.getString("deviceId")) || !JSON.parseObject(payload.toJSONString()).equals(JSON.parseObject(saved.getString("body"))))throw new IllegalStateException("接收编号已被其他报文使用");
            return saved.getLongValue("sequence");
        });
    }
    public void markReportProcessed(String receiptId) { jdbc.update("UPDATE wearable_device_report SET processed_at=? WHERE receipt_id=? AND processed_at IS NULL",System.currentTimeMillis(),receiptId); }
    /** Business SQL and the delivery marker commit together; retries lock the same receipt. */
    public boolean processReport(String receiptId,Runnable handler) {
        if(receiptId==null || handler==null)throw new IllegalArgumentException("缺少设备报文处理参数");
        synchronized(BUSINESS_LOCK) {
        return transactions.execute(status->{
            List<JSONObject> rows=jdbc.query("SELECT processed_at,protocol,device_id,received_at,body FROM wearable_device_report WHERE receipt_id=? FOR UPDATE",(rs,n)->{
                long value=rs.getLong(1);Long processed=rs.wasNull()?null:value;
                return object("processedAt",processed,"protocol",rs.getString(2),"deviceId",rs.getString(3),"receivedMillis",rs.getLong(4),"payload",JSON.parseObject(rs.getString(5)));
            },receiptId);
            if(rows.size()!=1)throw new IllegalArgumentException("设备接收记录不存在");
            if(rows.get(0).get("processedAt")!=null)return false;
            if(alarmJournal==null)handler.run();else alarmJournal.duringReceipt(rows.get(0),handler);
            markReportProcessed(receiptId);return true;
        });
        }
    }
    public List<JSONObject> pendingReports(long afterSequence,int limit) {
        if(afterSequence<0 || limit<1 || limit>1000)throw new IllegalArgumentException("报文分页参数无效");
        return jdbc.query("SELECT sequence,receipt_id,protocol,device_id,received_at,body FROM wearable_device_report WHERE sequence>? AND processed_at IS NULL ORDER BY sequence LIMIT ?",
                (rs,n)->object("sequence",rs.getLong(1),"receiptId",rs.getString(2),"protocol",rs.getString(3),"deviceId",rs.getString(4),"receivedMillis",rs.getLong(5),"payload",JSON.parseObject(rs.getString(6))),afterSequence,limit);
    }

    public List<JSONObject> locations(String personId,String deviceId,long from,long to,long cursorTime,String cursorId,int limit) {
        String column=personId==null?"device_id":"person_id";
        return jdbc.query("SELECT body,observed_at FROM wearable_location WHERE namespace='guardian' AND collection_key='locations' AND "+column+"=? AND observed_at>=? AND observed_at<? AND (observed_at>? OR (observed_at=? AND record_key>?)) ORDER BY observed_at,record_key LIMIT ?",
                (rs,n)->{JSONObject row=JSON.parseObject(rs.getString(1));row.put("queryMillis",rs.getLong(2));return row;},personId==null?deviceId:personId,from,to,cursorTime,cursorTime,cursorId,limit);
    }

    static Long observedAt(JSONObject row) {
        for(String key:Arrays.asList("queryMillis","collectedMillis","receivedMillis"))if(row.get(key)!=null)return row.getLong(key);
        for(String key:Arrays.asList("observedAt","reportedAt","locationReportedAt","createdAt","receivedAt","time")) {
            String value=row.getString(key);if(value==null)continue;
            try{return Instant.parse(value).toEpochMilli();}catch(RuntimeException ignored){}
            try{return LocalDateTime.parse(value,DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")).atZone(ZoneId.of("Asia/Shanghai")).toInstant().toEpochMilli();}catch(RuntimeException ignored){}
        }
        return null;
    }
    private static String table(String ns,String collection) {
        if("$eventActions".equals(collection))return "wearable_event_action";
        String result=("guardian".equals(ns)?GUARDIAN:MEDIA).get(collection);
        return result==null?"wearable_business_extra":result;
    }
    private static void requireNamespace(String namespace) { if(!"guardian".equals(namespace)&&!"media".equals(namespace))throw new IllegalArgumentException("业务存储命名空间无效"); }
    private static boolean secret(String namespace,String collection) { return "media".equals(namespace)||"sharedCommunications".equals(collection)||"voiceSessions".equals(collection); }
    private String encode(String ns,String key,String id,String plain) {
        if(!secret(ns,key))return plain;
        if(mediaKey==null)throw new IllegalStateException("保存私有媒体数据前必须配置 MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY");
        try {
            byte[] nonce=new byte[12];RANDOM.nextBytes(nonce);Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(mediaKey,"AES"),new GCMParameterSpec(128,nonce));cipher.updateAAD((ns+"\n"+key+"\n"+id).getBytes(StandardCharsets.UTF_8));
            byte[] encrypted=cipher.doFinal(plain.getBytes(StandardCharsets.UTF_8));byte[] value=new byte[nonce.length+encrypted.length];System.arraycopy(nonce,0,value,0,nonce.length);System.arraycopy(encrypted,0,value,nonce.length,encrypted.length);return "enc:v1:"+Base64.getEncoder().encodeToString(value);
        } catch(Exception error){throw new IllegalStateException("私有媒体数据加密失败",error);}
    }
    private String decode(String ns,String key,String id,String stored) {
        if(!secret(ns,key))return stored;
        if(mediaKey==null || stored==null || !stored.startsWith("enc:v1:"))throw new IllegalStateException("私有媒体数据缺少有效加密密钥或密文");
        try{
            byte[] value=Base64.getDecoder().decode(stored.substring(7));Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(mediaKey,"AES"),new GCMParameterSpec(128,Arrays.copyOfRange(value,0,12)));cipher.updateAAD((ns+"\n"+key+"\n"+id).getBytes(StandardCharsets.UTF_8));return new String(cipher.doFinal(Arrays.copyOfRange(value,12,value.length)),StandardCharsets.UTF_8);
        }catch(Exception error){throw new IllegalStateException("私有媒体数据无法解密，禁止覆盖原记录",error);}
    }
    private static String sha256(byte[] bytes) {
        try{StringBuilder out=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(bytes))out.append(String.format("%02x",b&255));return out.toString();}catch(Exception error){throw new IllegalStateException(error);}
    }
    private static String first(JSONObject row,String a,String b){String value=text(row,a);return value==null?text(row,b):value;}
    private static String text(JSONObject row,String key){String value=row.getString(key);return value==null||value.isEmpty()?null:value;}
    private static JSONObject object(Object...pairs){JSONObject o=new JSONObject();for(int i=0;i<pairs.length;i+=2)o.put((String)pairs[i],pairs[i+1]);return o;}
}
