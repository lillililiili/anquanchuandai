package com.ruoyi.melhat;

import java.nio.file.*;
import java.util.*;
import java.io.*;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.mock.web.MockMultipartFile;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class EventEvidenceTest {
    @TempDir Path folder;
    EventEvidenceService service;
    JdbcTemplate db;
    TransactionTemplate tx;
    WearSafetyEvent event;
    EventAccessService access;
    byte[] png;
    @BeforeEach void setup() throws Exception {
        DriverManagerDataSource ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        db=new JdbcTemplate(ds);tx=new TransactionTemplate(new DataSourceTransactionManager(ds));
        db.execute("CREATE TABLE wear_event_media(id VARCHAR PRIMARY KEY,event_id BIGINT,submission_version INT,actor_user_id BIGINT,media_type VARCHAR,byte_size BIGINT,create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        service=new EventEvidenceService();access=mock(EventAccessService.class);
        SiteAccessService sites=mock(SiteAccessService.class);LoginUser user=new LoginUser();user.setUserId(100L);when(sites.requireLogin()).thenReturn(user);
        WearSafetyEventMapper events=mock(WearSafetyEventMapper.class);event=new WearSafetyEvent();event.setId(1L);event.setSiteId(1L);when(events.selectById(1L)).thenReturn(event);
        ReflectionTestUtils.setField(service,"db",db);ReflectionTestUtils.setField(service,"directory",folder.toString());
        ReflectionTestUtils.setField(service,"sites",sites);ReflectionTestUtils.setField(service,"events",events);ReflectionTestUtils.setField(service,"access",access);
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();ImageIO.write(new BufferedImage(2,2,BufferedImage.TYPE_INT_RGB),"png",bytes);png=bytes.toByteArray();
    }
    @Test void emptyAttachmentsAreOptionalAndFakeImagePayloadIsRejected() {
        assertDoesNotThrow(()->service.save(event,1,Collections.emptyList()));
        assertDoesNotThrow(()->service.save(event,1,null));
        assertThrows(ServiceException.class,()->service.save(event,1,Collections.singletonList(new MockMultipartFile("files","photo.jpg","image/jpeg","not a photograph".getBytes()))));
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM wear_event_media",Integer.class));
    }
    @Test void validPhotoPersistsAndAccessIsCheckedForListsAndBytes() {
        tx.execute(status->{try {service.save(event,2,Collections.singletonList(new MockMultipartFile("files","现场.png","image/png",png)));}catch(IOException ex){throw new RuntimeException(ex);}return null;});
        List<Map<String,Object>> photos=service.list(1L);assertEquals(1,photos.size());String id=String.valueOf(photos.get(0).get("id"));
        assertEquals("image/png",service.media(1L,id).get("media_type"));
        doThrow(new ServiceException("跨组不可见",403)).when(access).assertReadable(event);
        assertThrows(ServiceException.class,()->service.media(1L,id));assertThrows(ServiceException.class,()->service.list(1L));
    }
    @Test void multiplePhotosAndVideoRetainMediaTypesAndLimits() throws Exception {
        byte[] mp4Header={0,0,0,20,102,116,121,112,105,115,111,109,0,0,0,0,105,115,111,109};
        List<org.springframework.web.multipart.MultipartFile> files=Arrays.asList(
                new MockMultipartFile("files","one.png","image/png",png),
                new MockMultipartFile("files","two.png","image/png",png),
                new MockMultipartFile("files","clip.mp4","video/mp4",mp4Header));
        tx.execute(status->{try {service.save(event,1,files);}catch(IOException ex){throw new RuntimeException(ex);}return null;});
        assertEquals(3,service.list(1L).size());
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM wear_event_media WHERE media_type='video/mp4'",Integer.class));
        assertTrue(service.list(1L).stream().anyMatch(m -> "video/mp4".equals(m.get("mediaType"))));
        assertThrows(ServiceException.class,()->service.save(event,2,Collections.nCopies(7,files.get(0))));
        org.springframework.web.multipart.MultipartFile large=mock(org.springframework.web.multipart.MultipartFile.class);
        when(large.getSize()).thenReturn(51L*1024*1024);when(large.isEmpty()).thenReturn(false);
        assertThrows(ServiceException.class,()->service.save(event,2,Collections.singletonList(large)));
        verify(large,never()).getBytes();
    }
    @Test void failedSubmissionRollsBackBothDatabaseAndFiles() throws Exception {
        tx.execute(status->{try {service.save(event,1,Collections.singletonList(new MockMultipartFile("files","现场.png","image/png",png)));}catch(IOException ex){throw new RuntimeException(ex);}status.setRollbackOnly();return null;});
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM wear_event_media",Integer.class));
        try(java.util.stream.Stream<Path> files=Files.list(folder)){assertEquals(0,files.count());}
    }
}
