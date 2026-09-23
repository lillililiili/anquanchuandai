package com.ruoyi.melhat;

import java.sql.Timestamp;
import java.util.*;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.work.InspectionService;
import com.ruoyi.wear.work.WorkTaskService;
import com.ruoyi.wear.work.domain.WearWorkTask;
import com.ruoyi.wear.work.dto.WorkTaskDto;
import com.ruoyi.wear.work.mapper.WearWorkTaskMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskMemberMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskRequirementMapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

public class InspectionMemberProgressTest {
    private JdbcTemplate db;
    private TransactionTemplate tx;
    private final InspectionService service = new InspectionService();
    private final WorkTaskService tasks = mock(WorkTaskService.class);
    private final SiteAccessService access = mock(SiteAccessService.class);
    private WearWorkTask height;

    public static String dateFormat(Timestamp value, String format) {
        return value == null ? null : value.toLocalDateTime().toString();
    }

    @BeforeEach void setup() {
        DriverManagerDataSource ds = new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID()
                + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE", "sa", "");
        db = new JdbcTemplate(ds);
        tx = new TransactionTemplate(new DataSourceTransactionManager(ds));
        db.execute("CREATE ALIAS DATE_FORMAT FOR \"com.ruoyi.melhat.InspectionMemberProgressTest.dateFormat\"");
        db.execute("CREATE TABLE wear_work_task(id BIGINT PRIMARY KEY,site_id BIGINT,status VARCHAR)");
        db.execute("CREATE TABLE wear_inspection_item(id BIGINT AUTO_INCREMENT PRIMARY KEY,task_id BIGINT,title VARCHAR,location VARCHAR,instruction VARCHAR,sort_order INT)");
        db.execute("CREATE TABLE wear_inspection_group(task_id BIGINT PRIMARY KEY,current_item_id BIGINT)");
        db.execute("CREATE TABLE wear_inspection_record(id BIGINT AUTO_INCREMENT PRIMARY KEY,task_id BIGINT,item_id BIGINT,sequence_no INT,request_id VARCHAR,actor_user_id BIGINT,actor_name VARCHAR,recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        db.execute("CREATE TABLE wear_inspection_report(id VARCHAR PRIMARY KEY,task_id BIGINT,item_id BIGINT,request_id VARCHAR,actor_user_id BIGINT,actor_name VARCHAR,location VARCHAR,description VARCHAR,payload_hash VARCHAR,reported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        db.execute("CREATE TABLE wear_inspection_media(id VARCHAR,report_id VARCHAR,media_type VARCHAR,byte_size BIGINT)");
        db.execute("CREATE TABLE wear_person(name VARCHAR,account_user_id BIGINT,del_flag VARCHAR,status VARCHAR)");
        db.execute("INSERT INTO wear_work_task VALUES(3,1,'in_progress'),(4,1,'in_progress'),(7,1,'in_progress'),(15,1,'ready'),(19,1,'ended'),(27,1,'ended'),(90,1,'ended'),(91,2,'ended')");
        db.execute("INSERT INTO wear_inspection_item(task_id,title,sort_order) VALUES(7,'已完成巡检',1),(4,'未完成巡检',1)");
        db.execute("INSERT INTO wear_inspection_record(task_id,item_id,actor_user_id,actor_name) SELECT 7,id,999,'另一组员' FROM wear_inspection_item WHERE task_id=7");
        db.execute("INSERT INTO wear_person VALUES('陈建国',114,'0','0')");
        when(tasks.memberTaskIds()).thenReturn(new HashSet<>(Arrays.asList(3L,4L,7L,15L,19L,27L,91L)));
        when(access.listScopeSiteIds()).thenReturn(Collections.singletonList(1L));
        LoginUser user = new LoginUser(); user.setUserId(114L); user.setUser(new SysUser());
        when(access.requireLogin()).thenReturn(user);
        height = new WearWorkTask(); height.setId(3L); height.setTitle("锅炉平台检修");
        height.setSiteId(1L); height.setWorkType("height"); height.setStatus("in_progress");
        height.setOwnerUserId(122L); height.setGuardianPersonId(88L);
        when(tasks.requireReadable(3L)).thenReturn(height);
        ReflectionTestUtils.setField(service,"db",db);
        ReflectionTestUtils.setField(service,"tasks",tasks);
        ReflectionTestUtils.setField(service,"access",access);
        ReflectionTestUtils.setField(service,"mediaDirectory",System.getProperty("java.io.tmpdir"));
    }

    @Test void ordinaryMemberCanInspectHeightWorkAndProgressCountsAllOwnGroups() {
        Map<String,Object> before = tx.execute(s -> service.summary(3L));
        assertProgress(before, 3, 6);
        assertEquals(0, before.get("completed"));
        assertEquals(1, before.get("total"));
        Long item = Long.valueOf(String.valueOf(before.get("currentItemId")));
        Map<String,Object> after = tx.execute(s -> service.record(3L,item,"member-record-1"));
        assertProgress(after, 4, 6);
        assertEquals(114L, db.queryForObject("SELECT actor_user_id FROM wear_inspection_record WHERE task_id=3",Long.class));
        assertEquals("陈建国", db.queryForObject("SELECT actor_name FROM wear_inspection_record WHERE task_id=3",String.class));
        tx.execute(s -> service.record(3L,item,"member-record-1"));
        assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM wear_inspection_record WHERE task_id=3",Integer.class));
        when(access.isPlatformAdmin(any())).thenReturn(true);
        assertProgress(tx.execute(s -> service.summary(3L)), 4, 6);
    }

    @Test void ordinaryMemberCanReportHeightWorkButEndedAndOutsiderAreRejected() {
        Map<String,Object> before = tx.execute(s -> service.summary(3L));
        Long item = Long.valueOf(String.valueOf(before.get("currentItemId")));
        tx.execute(s -> {
            try { return service.report(3L,item,"member-report-1","平台东侧","护栏松动",Collections.emptyList()); }
            catch(Exception e) { throw new RuntimeException(e); }
        });
        assertEquals(114L,db.queryForObject("SELECT actor_user_id FROM wear_inspection_report",Long.class));
        height.setStatus("ended");
        assertEquals(409,assertThrows(ServiceException.class,() -> tx.execute(s -> service.record(3L,item,"ended-record-1"))).getCode());
        when(tasks.requireReadable(3L)).thenThrow(new ServiceException("非组员",403));
        assertEquals(403,assertThrows(ServiceException.class,() -> tx.execute(s -> service.summary(3L))).getCode());
    }

    @Test void partialGroupsAndEmptyMembershipNeverInflateProgress() {
        db.execute("INSERT INTO wear_inspection_item(task_id,title,sort_order) VALUES(7,'追加巡检项',2)");
        assertProgress(tx.execute(s -> service.summary(3L)), 2, 6);
        when(tasks.memberTaskIds()).thenReturn(Collections.emptySet());
        assertProgress(tx.execute(s -> service.summary(3L)), 0, 0);
    }

    @Test void completingAnyWorkTypeUpdatesTheMineListWithoutEndingTheWorkPermit() {
        WorkTaskService listing = spy(new WorkTaskService());
        WearWorkTaskMapper mapper = mock(WearWorkTaskMapper.class);
        ReflectionTestUtils.setField(listing,"taskMapper",mapper);
        ReflectionTestUtils.setField(listing,"siteAccessService",access);
        ReflectionTestUtils.setField(listing,"inspectionDb",db);
        ReflectionTestUtils.setField(listing,"memberMapper",mock(WearWorkTaskMemberMapper.class));
        ReflectionTestUtils.setField(listing,"requirementMapper",mock(WearWorkTaskRequirementMapper.class));
        doReturn(Collections.singleton(3L)).when(listing).memberTaskIds();
        Page<WearWorkTask> page = new Page<>(1,20);
        page.setRecords(Collections.singletonList(height)); page.setTotal(1);
        when(mapper.selectPage(any(Page.class),any())).thenReturn(page);
        for (String type : Arrays.asList("height","other","patrol")) {
            height.setWorkType(type);
            db.update("DELETE FROM wear_inspection_record WHERE task_id=3");
            assertEquals("in_progress",listing.mine(1,20).getRecords().get(0).getInspectionStatus());
            Map<String,Object> summary = tx.execute(s -> service.summary(3L));
            Long item = Long.valueOf(String.valueOf(summary.get("currentItemId")));
            tx.execute(s -> service.record(3L,item,"list-record-"+type));
            WorkTaskDto row = listing.mine(1,20).getRecords().get(0);
            assertEquals("completed",row.getInspectionStatus(),type);
            assertEquals("in_progress",row.getStatus(),"Inspection must not close the work permit");
        }
    }

    private void assertProgress(Map<String,Object> snapshot, int completed, int total) {
        Map<?,?> progress = (Map<?,?>)snapshot.get("accountProgress");
        assertEquals(completed,progress.get("completed"));
        assertEquals(total,progress.get("total"));
    }
}
