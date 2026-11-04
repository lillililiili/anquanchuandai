package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.ResolverStyle;
import java.util.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

/** Device-originated recording synchronization; no user identity or public command authorization is invented. */
@Service
public class HelmetLocalRecordingSync {
    private final HelmetMediaStore store;
    private final ObjectProvider<DirectHelmetGateway> gateways;
    private final ObjectProvider<HelmetMediaService> media;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.guardian.WearableMaintenance maintenance;
    @org.springframework.beans.factory.annotation.Autowired private ObjectProvider<com.ruoyi.guardian.GuardianIngest> ingest;
    @org.springframework.beans.factory.annotation.Autowired private com.ruoyi.guardian.AdminLedgerStore ledger;
    private static final ZoneId DEVICE_ZONE=ZoneId.of("Asia/Shanghai");
    private static final DateTimeFormatter FILE_TIME=DateTimeFormatter.ofPattern("uuuuMMddHHmmss").withResolverStyle(ResolverStyle.STRICT);
    private static final DateTimeFormatter QUERY_TIME=DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(DEVICE_ZONE);
    public HelmetLocalRecordingSync(HelmetMediaStore store,ObjectProvider<DirectHelmetGateway> gateways,ObjectProvider<HelmetMediaService> media){this.store=store;this.gateways=gateways;this.media=media;}

    /** Called inside the original durable report transaction: storage only, no monitor or network acquisition. */
    public void observe(String receiptId,String deviceId,String type,JSONObject captured){
        if(captured==null||!Arrays.asList("0","1").contains(type))return;
        Instant at=Instant.parse(captured.getString("receivedAt"));
        store.update(state->{
            JSONObject devices=map(state,"localRecordingSyncDevices"),tasks=map(state,"autoSyncTasks"),cursor=devices.getJSONObject(deviceId);
            JSONArray receipts=new JSONArray();
            if(cursor!=null){
                Instant previous=Instant.parse(cursor.getString("lastReceivedAt"));
                if(at.isBefore(previous))return null;
                if(at.equals(previous)){
                    receipts=cursor.getJSONArray("lastReceiptIds");
                    // Legacy cursors cannot distinguish receipts at their last timestamp.
                    if(receipts==null||receipts.contains(receiptId))return null;
                }
            }
            // Durable reports arrive in sequence order; distinct receipts may share a clock tick.
            receipts.add(receiptId);
            if(cursor==null){cursor=new JSONObject();devices.put(deviceId,cursor);}
            cursor.put("lastReceivedAt",at.toString());cursor.put("lastReceiptIds",receipts);
            JSONObject open=tasks.getJSONObject(cursor.getString("openTaskId"));
            if("0".equals(type)){
                if(open!=null&&"recording".equals(open.getString("status")))return null;
                if(!currentBinding(captured,at))return null;
                String id="ARS-"+org.apache.commons.codec.digest.DigestUtils.sha256Hex(receiptId).substring(0,32);
                JSONObject task=obj("id",id,"deviceId",deviceId,"kind","video","source","DEVICE_LOCAL_RECORDING","status","recording",
                        "startedAt",at.toString(),"updatedAt",at.toString(),"message","设备正在录像","fileCount",0,"receivedCount",0,
                        "siteId",captured.get("siteId"),"areaId",captured.get("areaId"),"receivedPersonId",captured.get("personId"),
                        "receivedPersonName",captured.get("personName"),"bindingId",captured.get("bindingId"),"startContext",JSONObject.parseObject(captured.toJSONString()));
                tasks.put(id,task);cursor.put("openTaskId",id);return null;
            }
            if(open==null||!"recording".equals(open.getString("status")))return null;
            cursor.remove("openTaskId");open.put("stoppedAt",at.toString());open.put("updatedAt",at.toString());
            open.put("stopContext",JSONObject.parseObject(captured.toJSONString()));
            boolean same=currentBinding(captured,at);
            for(String field:Arrays.asList("siteId","areaId","personId","bindingId","bindingStart"))same&=Objects.equals(open.getJSONObject("startContext").get(field),captured.get(field));
            if(!same){open.put("status","failed");open.put("message","录像期间领用或厂站范围已变化，请核对后手动上传");}
            else {open.put("status","queued");open.put("message","录像已结束，正在等待文件保存");open.put("nextAttemptAt",at.plusSeconds(5).toString());}
            return null;
        });
    }
    private static boolean currentBinding(JSONObject captured,Instant at){
        try {JSONObject device=captured.getJSONObject("device");
            return device!=null&&"DIRECT_HELMET".equals(device.getString("source"))&&!Boolean.FALSE.equals(device.get("active"))
                    &&!Arrays.asList("DISABLED","SCRAPPED").contains(device.getString("lifecycle"))&&!text(captured,"siteId").isEmpty()
                    &&!text(captured,"personId").isEmpty()&&!text(captured,"bindingId").isEmpty()&&captured.get("bindingEnd")==null
                    &&!Instant.parse(text(captured,"bindingStart")).isAfter(at);
        }catch(RuntimeException invalid){return false;}
    }
    @Scheduled(fixedDelay=5000,initialDelay=5000) public synchronized void reconcile(){
        if(maintenance!=null&&!maintenance.tryBeginWrite())return;
        try {
            for(Object value:map(store.snapshot(),"autoSyncTasks").values()){
                JSONObject task=(JSONObject)value;
                if(Arrays.asList("recording","completed","failed").contains(task.getString("status")))continue;
                try{advance(task);}catch(RuntimeException error){status(task,"waiting_device","暂未取得设备或媒体服务响应，将自动重试");save(task);}
            }
        }finally{if(maintenance!=null)maintenance.endWrite();}
    }
    private void advance(JSONObject task){
        Instant now=Instant.now();String deviceId=task.getString("deviceId");
        if(!text(task,"nextAttemptAt").isEmpty()&&now.isBefore(Instant.parse(task.getString("nextAttemptAt"))))return;
        if(!media.getObject().available()){status(task,"waiting_device","媒体服务暂不可用，恢复后自动同步");save(task);return;}
        if(!text(task,"uploadCommandId").isEmpty()){checkUploaded(task);return;}
        if(!gateways.getObject().supports(deviceId)){status(task,"failed","设备登记已变化，自动同步已停止");save(task);return;}
        if(!sameCurrentScope(task)){status(task,"failed","设备领用或厂站范围已变化，请核对后手动上传");save(task);return;}
        if(!gateways.getObject().isOnline(deviceId)){status(task,"waiting_device","设备离线，联网后自动同步");save(task);return;}
        JSONObject command=map(store.snapshot(),"commands").getJSONObject(task.getString("queryCommandId"));
        if(command!=null){
            JSONArray result=command.getJSONArray("result");
            if(result!=null&&!result.isEmpty()){
                JSONArray selected=selectFiles(task,result);
                if(selected==null){status(task,"failed","设备返回的录像名称或文件校验值无法确认，请手动核对");save(task);return;}
                if(!selected.isEmpty()){
                    task.put("files",selected);task.put("fileCount",selected.size());
                    send(task,"upload_recording",selected);return;
                }
            }
            if(!Arrays.asList("acknowledged","rejected","timeout").contains(command.getString("status"))
                    &&now.isBefore(Instant.parse(command.getString("expiresAt"))))return;
            if(task.getIntValue("queryAttempts")>=3){status(task,"failed","设备未返回本次录像文件，请确认录像已保存后手动查询");save(task);return;}
        }
        send(task,"list_recordings",null);
    }
    private boolean sameCurrentScope(JSONObject task){
        try {JSONObject current=ingest.getObject().captureDirect(task.getString("deviceId"));
            if(!currentBinding(current,Instant.now()))return false;
            JSONObject original=task.getJSONObject("startContext");
            for(String field:Arrays.asList("siteId","areaId","personId","bindingId","bindingStart"))if(!Objects.equals(original.get(field),current.get(field)))return false;
            return true;
        }catch(RuntimeException changed){return false;}
    }
    private JSONArray selectFiles(JSONObject task,JSONArray result){
        Instant from=windowStart(task),to=Instant.parse(task.getString("stoppedAt")).plusSeconds(30);
        JSONArray selected=new JSONArray();Set<String> seen=new HashSet<>();JSONObject claims=map(store.snapshot(),"autoSyncFileClaims");
        for(Object raw:result){if(!(raw instanceof JSONObject))return null;JSONObject file=(JSONObject)raw;
            String name=text(file,"file_name"),md5=text(file,"file_md5");
            if(!name.matches("[0-9]{14}\\.mp4")||!md5.matches("[A-Za-z0-9_-]{8,128}"))return null;
            Instant filmed;try{filmed=LocalDateTime.parse(name.substring(0,14),FILE_TIME).atZone(DEVICE_ZONE).toInstant();}catch(RuntimeException invalid){return null;}
            if(filmed.isBefore(from)||filmed.isAfter(to))continue;
            String key=task.getString("deviceId")+":"+md5;
            if(claims.containsKey(key)&&!task.getString("id").equals(claims.getString(key)))continue;
            if(seen.add(md5))selected.add(obj("fileName",name,"progressId",md5));
        }
        return selected.size()>20?null:selected;
    }
    private void send(JSONObject task,String action,JSONArray files){
        // Assignment HTTP writes use this same monitor. Keep the last authority check and socket send together,
        // without retaining the SQL/business lock while waiting on the socket or acquiring the media monitor.
        synchronized(ledger){
            if(!sameCurrentScope(task)){status(task,"failed","设备领用或厂站范围已变化，请核对后手动上传");save(task);return;}
            sendAuthorized(task,action,files);
        }
    }
    private static Instant windowStart(JSONObject task){
        Instant window=Instant.parse(task.getString("startedAt")).minusSeconds(30),binding=Instant.parse(task.getJSONObject("startContext").getString("bindingStart"));
        return window.isBefore(binding)?binding:window;
    }
    private void sendAuthorized(JSONObject task,String action,JSONArray files){
        boolean upload="upload_recording".equals(action);int attempt=upload?1:task.getIntValue("queryAttempts")+1;
        String id="HS-"+org.apache.commons.codec.digest.DigestUtils.sha256Hex(task.getString("id")+":"+action+":"+attempt).substring(0,32);
        Instant now=Instant.now();JSONObject wire;
        if(upload){JSONArray names=new JSONArray();for(Object raw:files)names.add(((JSONObject)raw).get("fileName"));wire=HelmetMediaService.wire(action,obj("files",names));}
        else wire=HelmetMediaService.wire(action,obj("startTime",QUERY_TIME.format(windowStart(task)),"endTime",QUERY_TIME.format(Instant.parse(task.getString("stoppedAt")).plusSeconds(30))));
        wire.put("talkback_id",id);
        JSONObject command=obj("id",id,"deviceId",task.get("deviceId"),"action",action,"source","DEVICE_LOCAL_RECORDING","autoSyncTaskId",task.get("id"),
                "siteId",task.get("siteId"),"areaId",task.get("areaId"),"personId",task.get("receivedPersonId"),"personName",task.get("receivedPersonName"),
                "createdAt",now.toString(),"expiresAt",now.plusSeconds(120).toString(),"status","requesting","message","正在同步设备本次录像");
        if(upload)command.put("requestedFiles",files);
        task.put(upload?"uploadCommandId":"queryCommandId",id);if(!upload)task.put("queryAttempts",attempt);
        task.remove("nextAttemptAt");status(task,upload?"uploading":"querying",upload?"正在上传本次录像":"正在查询本次录像文件");
        store.update(state->{map(state,"commands").put(id,command);map(state,"autoSyncTasks").put(task.getString("id"),task);
            if(upload)for(Object raw:files)map(state,"autoSyncFileClaims").put(task.getString("deviceId")+":"+((JSONObject)raw).getString("progressId"),task.get("id"));return null;});
        try{gateways.getObject().sendCommand(task.getString("deviceId"),wire);command.put("status","sent");command.put("sentAt",Instant.now().toString());}
        catch(Exception uncertain){command.put("status","unknown");command.put("message","未确认设备是否收到，等待真实回执或文件");}
        store.update(state->{JSONObject current=map(state,"commands").getJSONObject(id);
            // A fast device receipt can arrive before sendCommand returns; never overwrite its result.
            if(current!=null&&"requesting".equals(current.getString("status"))){current.put("status",command.get("status"));current.put("message",command.get("message"));if(command.containsKey("sentAt"))current.put("sentAt",command.get("sentAt"));}
            return null;});
    }
    private void checkUploaded(JSONObject task){
        JSONArray files=task.getJSONArray("files"),assets=media.getObject().assets(task.getString("deviceId")),ids=new JSONArray();Set<String> received=new HashSet<>();
        for(Object raw:assets){JSONObject asset=(JSONObject)raw;
            if(!task.getString("uploadCommandId").equals(asset.getString("requestId"))||!"ready".equals(asset.getString("status"))||!"video".equals(asset.getString("kind")))continue;
            for(Object requested:files){JSONObject file=(JSONObject)requested;if(file.getString("fileName").equals(asset.getString("originalName"))&&file.getString("progressId").equals(asset.getString("progressId"))&&received.add(file.getString("progressId")))ids.add(asset.get("id"));}
        }
        task.put("receivedCount",received.size());task.put("assetIds",ids);
        if(received.size()==files.size()){status(task,"completed","录像已同步到现场资料");save(task);return;}
        JSONObject command=map(store.snapshot(),"commands").getJSONObject(task.getString("uploadCommandId"));
        if(command!=null&&Instant.parse(command.getString("createdAt")).plusSeconds(600).isBefore(Instant.now()))status(task,"failed","尚未收到完整录像文件，请检查设备上传网络后手动重试");
        else status(task,"uploading","已接收 "+received.size()+" / "+files.size()+" 个录像文件");
        save(task);
    }
    private void save(JSONObject task){store.update(state->{map(state,"autoSyncTasks").put(task.getString("id"),task);return null;});}
    private static void status(JSONObject task,String status,String message){task.put("status",status);task.put("message",message);task.put("updatedAt",Instant.now().toString());}
    private static JSONObject map(JSONObject state,String key){JSONObject map=state.getJSONObject(key);if(map==null){map=new JSONObject();state.put(key,map);}return map;}
    private static String text(JSONObject row,String key){String value=row.getString(key);return value==null?"":value;}
}
