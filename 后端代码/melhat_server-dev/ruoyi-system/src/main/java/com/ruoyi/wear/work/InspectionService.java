package com.ruoyi.wear.work;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.work.domain.WearWorkTask;

/** Task-scoped, server-owned inspection progress. All mutations serialize on the group. */
@Service
public class InspectionService {
    @Autowired private JdbcTemplate db;
    @Autowired private WorkTaskService tasks;
    @Autowired private SiteAccessService access;
    @Value("${wear.inspection.media-directory:/data/inspection}") private String mediaDirectory;

    // READ_COMMITTED ensures a waiting member sees the previous lock holder's records.
    private WearWorkTask lock(Long taskId) {
        tasks.requireReadable(taskId);
        db.queryForList("SELECT id FROM wear_work_task WHERE id=? FOR UPDATE", taskId);
        WearWorkTask task = tasks.requireReadable(taskId);
        if (db.queryForObject("SELECT COUNT(*) FROM wear_inspection_item WHERE task_id=?", Integer.class, taskId) == 0)
            db.update("INSERT INTO wear_inspection_item(task_id,title,sort_order) VALUES(?,?,1)", taskId, task.getTitle());
        db.update("INSERT IGNORE INTO wear_inspection_group(task_id) VALUES(?)", taskId);
        return task;
    }

    @Transactional(rollbackFor=Exception.class, isolation=org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public Map<String,Object> summary(Long taskId) {
        lock(taskId);
        return snapshot(taskId);
    }

    private Map<String,Object> snapshot(Long taskId) {
        List<Map<String,Object>> items = db.queryForList("SELECT CAST(i.id AS CHAR) id,i.title,i.location,i.instruction,"
                + "r.actor_name inspector,DATE_FORMAT(r.recorded_at,'%Y-%m-%dT%H:%i:%s+08:00') recordedAt,"
                + "CASE WHEN EXISTS(SELECT 1 FROM wear_inspection_report a WHERE a.task_id=i.task_id AND a.item_id=i.id) THEN 'abnormal' "
                + "WHEN r.id IS NOT NULL THEN 'completed' ELSE 'in_progress' END status "
                + "FROM wear_inspection_item i LEFT JOIN wear_inspection_record r ON r.task_id=i.task_id AND r.item_id=i.id "
                + "WHERE i.task_id=? ORDER BY i.sort_order,i.id", taskId);
        String current = db.queryForObject("SELECT CAST(current_item_id AS CHAR) FROM wear_inspection_group WHERE task_id=?", String.class, taskId);
        boolean valid = false;
        int completed = 0;
        for (Map<String,Object> item : items) {
            if (item.get("recordedAt") != null) completed++;
            if (Objects.equals(current,item.get("id")) && item.get("recordedAt")==null) valid=true;
        }
        if (!valid) current = items.stream().filter(i -> i.get("recordedAt")==null)
                .map(i -> String.valueOf(i.get("id"))).findFirst().orElse(null);
        Map<String,Object> result = new LinkedHashMap<>();
        result.put("taskId",String.valueOf(taskId)); result.put("items",items);
        result.put("currentItemId",current); result.put("completed",completed); result.put("total",items.size());
        result.put("records",db.queryForList("SELECT CAST(r.id AS CHAR) id,CAST(r.item_id AS CHAR) itemId,i.title,"
                + "CAST(r.actor_user_id AS CHAR) inspectorUserId,r.actor_name inspector,"
                + "DATE_FORMAT(r.recorded_at,'%Y-%m-%dT%H:%i:%s+08:00') recordedAt "
                + "FROM wear_inspection_record r LEFT JOIN wear_inspection_item i ON i.id=r.item_id "
                + "WHERE r.task_id=? ORDER BY r.id DESC",taskId));
        List<Map<String,Object>> reports = db.queryForList("SELECT a.id,CAST(a.item_id AS CHAR) itemId,i.title,a.location,a.description,"
                + "a.actor_name inspector,DATE_FORMAT(a.reported_at,'%Y-%m-%dT%H:%i:%s+08:00') reportedAt "
                + "FROM wear_inspection_report a LEFT JOIN wear_inspection_item i ON i.id=a.item_id WHERE a.task_id=? ORDER BY a.reported_at DESC", taskId);
        for (Map<String,Object> report : reports) {
            List<Map<String,Object>> media = db.queryForList("SELECT id,media_type mediaType,byte_size byteSize FROM wear_inspection_media WHERE report_id=? ORDER BY id",report.get("id"));
            for (Map<String,Object> m : media) m.put("url","/api/v1/work-tasks/"+taskId+"/inspection/media/"+m.get("id"));
            report.put("media",media);
        }
        result.put("reports", reports);
        result.put("accountProgress", accountProgress());
        return result;
    }

    /** One unit per member work group, independent of the number of inspection items. */
    private Map<String,Object> accountProgress() {
        Set<Long> taskIds = tasks.memberTaskIds();
        List<Long> sites = access.listScopeSiteIds();
        Map<String,Object> progress = new LinkedHashMap<>();
        progress.put("completed", 0);
        progress.put("total", 0);
        if (taskIds.isEmpty() || sites.isEmpty()) return progress;
        List<Object> args = new ArrayList<>(taskIds);
        args.addAll(sites);
        Map<String,Object> row = db.queryForMap("SELECT COUNT(*) total, COALESCE(SUM(CASE WHEN t.status='ended' OR ("
                + "EXISTS(SELECT 1 FROM wear_inspection_item i WHERE i.task_id=t.id) AND "
                + "NOT EXISTS(SELECT 1 FROM wear_inspection_item i WHERE i.task_id=t.id AND NOT EXISTS("
                + "SELECT 1 FROM wear_inspection_record r WHERE r.task_id=t.id AND r.item_id=i.id))) "
                + "THEN 1 ELSE 0 END),0) completed FROM wear_work_task t WHERE t.id IN ("
                + String.join(",", Collections.nCopies(taskIds.size(), "?")) + ") AND t.site_id IN ("
                + String.join(",", Collections.nCopies(sites.size(), "?")) + ")", args.toArray());
        progress.put("completed", ((Number)row.get("completed")).intValue());
        progress.put("total", ((Number)row.get("total")).intValue());
        return progress;
    }

    @Transactional(rollbackFor=Exception.class, isolation=org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public Map<String,Object> select(Long taskId, Long itemId) {
        writable(lock(taskId)); requireItem(taskId,itemId);
        if (recorded(taskId,itemId)) fail("该巡检项已经完成，请选择其他巡检项",409);
        db.update("UPDATE wear_inspection_group SET current_item_id=? WHERE task_id=?", itemId,taskId);
        return snapshot(taskId);
    }

    @Transactional(rollbackFor=Exception.class, isolation=org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public Map<String,Object> record(Long taskId, Long itemId, String requestId) {
        WearWorkTask task = lock(taskId); requestId = requestId(requestId); requireItem(taskId,itemId);
        List<Map<String,Object>> prior = db.queryForList("SELECT item_id FROM wear_inspection_record WHERE task_id=? AND request_id=?",taskId,requestId);
        if (!prior.isEmpty()) {
            if (!String.valueOf(itemId).equals(String.valueOf(prior.get(0).get("item_id")))) fail("重复请求与原巡检项不一致",409);
            return snapshot(taskId);
        }
        writable(task);
        // A second member pressing the same item never creates another completion or overwrites its actor.
        if (recorded(taskId,itemId)) return snapshot(taskId);
        LoginUser actor = access.requireLogin();
        Integer sequence = db.queryForObject("SELECT COALESCE(MAX(sequence_no),0)+1 FROM wear_inspection_record WHERE task_id=?",Integer.class,taskId);
        db.update("INSERT INTO wear_inspection_record(task_id,item_id,sequence_no,request_id,actor_user_id,actor_name) VALUES(?,?,?,?,?,?)",
                taskId,itemId,sequence,requestId,actor.getUserId(),actorName(actor));
        Map<String,Object> result = snapshot(taskId);
        db.update("UPDATE wear_inspection_group SET current_item_id=? WHERE task_id=?",result.get("currentItemId"),taskId);
        return result;
    }

    @Transactional(rollbackFor=Exception.class, isolation=org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public Map<String,Object> addItem(Long taskId, Map<String,Object> body) {
        if (!access.isPlatformAdmin(access.requireLogin())) fail("仅管理员可维护巡检项",403);
        writable(lock(taskId));
        String title = field(body,"title",128,true), location=field(body,"location",200,false), instruction=field(body,"instruction",500,false);
        int count = db.queryForObject("SELECT COUNT(*) FROM wear_inspection_item WHERE task_id=?",Integer.class,taskId);
        if (count>=200) fail("每组最多200项巡检",400);
        db.update("INSERT INTO wear_inspection_item(task_id,title,location,instruction,sort_order) VALUES(?,?,?,?,?)",taskId,title,location,instruction,count+1);
        return snapshot(taskId);
    }

    @Transactional(rollbackFor=Exception.class, isolation=org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public Map<String,Object> report(Long taskId,Long itemId,String requestId,String location,String description,List<MultipartFile> files) throws Exception {
        WearWorkTask task=lock(taskId); requireItem(taskId,itemId); requestId=requestId(requestId);
        Map<String,Object> fields=new HashMap<>(); fields.put("location",location); fields.put("description",description);
        location=field(fields,"location",200,true); description=field(fields,"description",1000,true);
        if (files==null) files=Collections.emptyList();
        if(files.size()>6) fail("最多添加6个附件",400);
        List<byte[]> contents=new ArrayList<>(); List<String> types=new ArrayList<>();
        long total=0; MessageDigest digest=MessageDigest.getInstance("SHA-256");
        digest.update((itemId+"\n"+location+"\n"+description+"\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
        for(MultipartFile file:files) {
            total+=file.getSize();
            if(file.isEmpty() || file.getSize()>50*1024*1024 || total>100*1024*1024) fail("单个附件不超过50MB，合计不超过100MB",400);
            byte[] bytes=file.getBytes(); String type=mediaType(bytes);
            if(type.startsWith("image/") && bytes.length>10*1024*1024) fail("单张照片不超过10MB",400);
            digest.update(java.nio.ByteBuffer.allocate(8).putLong(bytes.length).array()); digest.update(bytes);
            contents.add(bytes); types.add(type);
        }
        String hash=Base64.getEncoder().encodeToString(digest.digest());
        List<Map<String,Object>> prior=db.queryForList("SELECT id,payload_hash FROM wear_inspection_report WHERE task_id=? AND request_id=?",taskId,requestId);
        if(!prior.isEmpty()) {
            if(!hash.equals(prior.get(0).get("payload_hash"))) fail("重复请求内容与原报告不一致",409);
            return snapshot(taskId);
        }
        writable(task);
        String reportId=UUID.randomUUID().toString(); LoginUser actor=access.requireLogin();
        db.update("INSERT INTO wear_inspection_report(id,task_id,item_id,request_id,actor_user_id,actor_name,location,description,payload_hash) VALUES(?,?,?,?,?,?,?,?,?)",
                reportId,taskId,itemId,requestId,actor.getUserId(),actorName(actor),location,description,hash);
        Path folder=Paths.get(mediaDirectory).toAbsolutePath().normalize(); Files.createDirectories(folder);
        List<Path> created=new ArrayList<>();
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override public void afterCompletion(int status) {
                if(status!=STATUS_COMMITTED) for(Path p:created) try { Files.deleteIfExists(p); } catch(IOException ignored) { }
            }
        });
        for(int i=0;i<contents.size();i++) {
            String id=UUID.randomUUID().toString(); Path output=folder.resolve(id); created.add(output); Files.write(output,contents.get(i));
            db.update("INSERT INTO wear_inspection_media(id,report_id,storage_name,media_type,byte_size) VALUES(?,?,?,?,?)",id,reportId,id,types.get(i),contents.get(i).length);
        }
        return snapshot(taskId);
    }

    public Map<String,Object> media(Long taskId,String id) {
        tasks.requireReadable(taskId);
        List<Map<String,Object>> rows=db.queryForList("SELECT m.storage_name,m.media_type FROM wear_inspection_media m JOIN wear_inspection_report r ON r.id=m.report_id WHERE m.id=? AND r.task_id=?",id,taskId);
        if(rows.isEmpty()) fail("附件不存在",404);
        Map<String,Object> result=rows.get(0);
        Path base=Paths.get(mediaDirectory).toAbsolutePath().normalize(); Path path=base.resolve(String.valueOf(result.get("storage_name"))).normalize();
        if(!path.startsWith(base) || !Files.isRegularFile(path)) fail("附件不存在",404);
        result.put("resource",new FileSystemResource(path)); return result;
    }

    public static String mediaType(byte[] bytes) {
        if(bytes.length>=3 && (bytes[0]&255)==255 && (bytes[1]&255)==216 && (bytes[2]&255)==255) return "image/jpeg";
        if(bytes.length>=8 && Arrays.equals(Arrays.copyOf(bytes,8),new byte[]{(byte)137,80,78,71,13,10,26,10})) return "image/png";
        if(bytes.length>=12 && new String(bytes,0,4,java.nio.charset.StandardCharsets.US_ASCII).equals("RIFF") && new String(bytes,8,4,java.nio.charset.StandardCharsets.US_ASCII).equals("WEBP")) return "image/webp";
        if(bytes.length>=12 && new String(bytes,4,4,java.nio.charset.StandardCharsets.US_ASCII).equals("ftyp")) {
            String brand=new String(bytes,8,4,java.nio.charset.StandardCharsets.US_ASCII);
            if(Arrays.asList("isom","iso2","mp41","mp42","avc1","M4V ","qt  ","3gp4","3gp5").contains(brand)) return "video/mp4";
        }
        if(bytes.length>=4 && (bytes[0]&255)==0x1a && (bytes[1]&255)==0x45 && (bytes[2]&255)==0xdf && (bytes[3]&255)==0xa3) return "video/webm";
        throw new ServiceException("附件仅支持JPEG、PNG、WebP照片及MP4、WebM视频",400);
    }
    private void requireItem(Long taskId,Long itemId) {
        if(itemId==null || db.queryForObject("SELECT COUNT(*) FROM wear_inspection_item WHERE id=? AND task_id=?",Integer.class,itemId,taskId)==0) fail("巡检项不属于当前组",403);
    }
    private boolean recorded(Long taskId,Long itemId) { return db.queryForObject("SELECT COUNT(*) FROM wear_inspection_record WHERE task_id=? AND item_id=?",Integer.class,taskId,itemId)>0; }
    private void writable(WearWorkTask task) { if("ended".equals(task.getStatus())) fail("已结束作业不能新增巡检记录",409); }
    private String actorName(LoginUser actor) {
        List<String> names=db.queryForList("SELECT name FROM wear_person WHERE account_user_id=? AND del_flag='0' AND status='0' LIMIT 1",String.class,actor.getUserId());
        return !names.isEmpty()?names.get(0):(actor.getUser().getNickName()==null?actor.getUsername():actor.getUser().getNickName());
    }
    private static String requestId(String id) { if(id==null || !id.matches("[A-Za-z0-9_-]{8,64}")) fail("请求标识无效",400); return id; }
    private static String field(Map<String,Object> body,String key,int max,boolean required) {
        String value=body.get(key)==null?"":String.valueOf(body.get(key)).trim();
        if(value.length()>max || (required && value.isEmpty())) fail("请填写有效的"+(key.equals("title")?"巡检项名称":key.equals("location")?"异常位置":"描述"),400);
        return value;
    }
    private static void fail(String message,int code) { throw new ServiceException(message,code); }
}
