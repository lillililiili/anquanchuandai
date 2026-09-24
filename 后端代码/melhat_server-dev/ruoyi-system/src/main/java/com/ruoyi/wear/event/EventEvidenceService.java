package com.ruoyi.wear.event;

import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import javax.imageio.ImageIO;
import java.io.ByteArrayInputStream;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;

@Service
public class EventEvidenceService {
    @Autowired private JdbcTemplate db;
    @Autowired private SiteAccessService sites;
    @Autowired private EventAccessService access;
    @Autowired private WearSafetyEventMapper events;
    @Value("${wear.event-media-directory:/data/event-evidence}") private String directory;

    public void save(WearSafetyEvent event, int version, List<MultipartFile> files) throws IOException {
        if(files==null || files.isEmpty()) return;
        if(files.size()>6) throw new ServiceException("最多添加6个照片或视频附件",400);
        List<byte[]> bytes=new ArrayList<>();
        List<String> types=new ArrayList<>();
        long total=0;
        for(MultipartFile file:files) {
            total+=file.getSize();
            if(file.isEmpty() || file.getSize()>50L*1024*1024 || total>100L*1024*1024)
                throw new ServiceException("单个附件不超过50MB，合计不超过100MB",400);
            byte[] data=file.getBytes();
            String type=com.ruoyi.wear.work.InspectionService.mediaType(data);
            if(type.startsWith("video/")) {
                bytes.add(data); types.add(type); continue;
            }
            if(!"image/jpeg".equals(type) && !"image/png".equals(type))
                throw new ServiceException("照片支持JPEG/PNG，视频支持MP4/WebM",400);
            if(data.length>10*1024*1024) throw new ServiceException("每张照片不超过10MB",400);
            try (javax.imageio.stream.ImageInputStream input=ImageIO.createImageInputStream(new ByteArrayInputStream(data))) {
                java.util.Iterator<javax.imageio.ImageReader> readers=ImageIO.getImageReaders(input);
                if(!readers.hasNext()) throw new ServiceException("现场照片格式无效",400);
                javax.imageio.ImageReader reader=readers.next();
                try {
                    reader.setInput(input);
                    if((long)reader.getWidth(0)*reader.getHeight(0)>25000000L) throw new ServiceException("照片尺寸过大，请重新拍摄",400);
                    if(reader.read(0)==null) throw new ServiceException("现场照片损坏",400);
                } finally {reader.dispose();}
            } catch(IOException ex) {throw new ServiceException("现场照片损坏，请重新拍摄",400);}
            bytes.add(data); types.add(type);
        }
        Path base=Paths.get(directory).toAbsolutePath().normalize(); Files.createDirectories(base);
        List<Path> created=new ArrayList<>();
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override public void afterCompletion(int status) {
                if(status!=STATUS_COMMITTED) for(Path file:created) try {Files.deleteIfExists(file);} catch(IOException ignored) {}
            }
        });
        for(int index=0;index<bytes.size();index++) {
            byte[] data=bytes.get(index);
            String id=UUID.randomUUID().toString(); Path path=base.resolve(id); created.add(path); Files.write(path,data);
            db.update("INSERT INTO wear_event_media(id,event_id,submission_version,actor_user_id,media_type,byte_size) VALUES(?,?,?,?,?,?)",
                    id,event.getId(),version,sites.requireLogin().getUserId(),types.get(index),data.length);
        }
    }
    public boolean hasSubmission(Long eventId, int version) {
        Integer count = db.queryForObject(
                "SELECT COUNT(*) FROM wear_event_media WHERE event_id=? AND submission_version=? AND byte_size>0",
                Integer.class, eventId, version);
        return count != null && count > 0;
    }

    private void readable(Long id) {
        WearSafetyEvent event=events.selectById(id);
        if(event==null) throw new ServiceException("事件不存在",404);
        sites.assertAuthorized(event.getSiteId()); access.assertReadable(event);
    }
    public List<Map<String,Object>> list(Long eventId) {
        readable(eventId);
        List<Map<String,Object>> rows=db.queryForList("SELECT id,media_type AS mediaType,byte_size AS byteSize,submission_version AS submissionVersion,create_time AS createTime FROM wear_event_media WHERE event_id=? ORDER BY create_time,id",eventId);
        for(Map<String,Object> row:rows) row.put("url","/api/v1/events/"+eventId+"/media/"+row.get("id"));
        return rows;
    }
    public Map<String,Object> media(Long eventId,String id) {
        readable(eventId);
        List<Map<String,Object>> rows=db.queryForList("SELECT id,media_type FROM wear_event_media WHERE id=? AND event_id=?",id,eventId);
        if(rows.isEmpty()) throw new ServiceException("附件不存在",404);
        Path base=Paths.get(directory).toAbsolutePath().normalize(),path=base.resolve(String.valueOf(rows.get(0).get("id"))).normalize();
        if(!path.startsWith(base) || !Files.isRegularFile(path)) throw new ServiceException("附件不存在",404);
        rows.get(0).put("resource",new FileSystemResource(path)); return rows.get(0);
    }
}
