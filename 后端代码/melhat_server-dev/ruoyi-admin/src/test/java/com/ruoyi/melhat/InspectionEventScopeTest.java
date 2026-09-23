package com.ruoyi.melhat;

import java.util.*;
import java.util.regex.*;
import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.apache.ibatis.builder.MapperBuilderAssistant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class InspectionEventScopeTest {
    private final EventAccessService access = new EventAccessService();
    private final SiteAccessService sites = mock(SiteAccessService.class);
    private final WearSafetyEventMapper events = mock(WearSafetyEventMapper.class);
    private JdbcTemplate db;

    @BeforeEach void setup() {
        TableInfoHelper.initTableInfo(new MapperBuilderAssistant(new MybatisConfiguration(), ""), WearSafetyEvent.class);
        db = new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID() + ";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", ""));
        db.execute("CREATE TABLE wear_person(id BIGINT,account_user_id BIGINT,status VARCHAR,del_flag VARCHAR)");
        db.execute("CREATE TABLE wear_work_task(id BIGINT,site_id BIGINT,status VARCHAR,owner_user_id BIGINT,guardian_person_id BIGINT)");
        db.execute("CREATE TABLE wear_work_task_member(task_id BIGINT,person_id BIGINT)");
        db.execute("CREATE TABLE wear_safety_event(id BIGINT,site_id BIGINT,task_id BIGINT,person_id BIGINT,event_type VARCHAR,severity VARCHAR,alarm_code VARCHAR,alarm_name VARCHAR DEFAULT '撞击',status VARCHAR DEFAULT 'open')");
        db.execute("ALTER TABLE wear_safety_event ADD source VARCHAR DEFAULT 'helmet'");
        db.execute("ALTER TABLE wear_safety_event ADD reporter_user_id BIGINT");
        db.execute("INSERT INTO wear_person VALUES(10,100,'0','0'),(20,200,'0','0'),(30,300,'0','0')");
        db.execute("INSERT INTO wear_work_task VALUES(1,1,'in_progress',900,30),(2,1,'in_progress',800,null),(3,1,'ended',900,null)");
        db.execute("ALTER TABLE wear_work_task ADD work_type VARCHAR DEFAULT 'height'");
        db.execute("CREATE TABLE wear_inspection_item(id BIGINT,task_id BIGINT)");
        db.execute("CREATE TABLE wear_inspection_record(task_id BIGINT,item_id BIGINT)");
        db.execute("INSERT INTO wear_work_task_member VALUES(1,10),(1,20),(2,30),(3,10)");
        db.execute("INSERT INTO wear_safety_event(id,site_id,task_id,person_id,event_type,severity,alarm_code,alarm_name) VALUES(1,1,1,20,'impact','abnormal','helmet.impact','撞击'),(2,1,2,30,'impact','abnormal','helmet.impact','撞击'),"
                + "(3,1,1,20,'realtime','warning','helmet.battery','低电量'),(4,1,null,10,'realtime','warning','helmet.battery','低电量'),"
                + "(5,1,3,10,'geofence','abnormal','geofence.exit','离开指定区域'),(6,1,null,10,'impact','abnormal','helmet.impact','撞击'),"
                + "(7,1,1,20,'realtime','abnormal','belt.unhooked','未挂钩')");
        LoginUser user = new LoginUser(); user.setUserId(100L);
        when(sites.requireLogin()).thenReturn(user);
        when(sites.listScopeSiteIds()).thenReturn(Collections.singletonList(1L));
        ReflectionTestUtils.setField(access,"sites",sites);
        ReflectionTestUtils.setField(access,"events",events);
        ReflectionTestUtils.setField(access,"db",db);
        when(events.selectCount(any())).thenAnswer(call -> ids(call.getArgument(0)).size());
    }

    @Test void manualSosIsPrivateToReporterAndAdminEvenOutsideAnyGroup() {
        db.update("INSERT INTO wear_safety_event(id,site_id,person_id,event_type,severity,source,reporter_user_id,status) VALUES(90,1,20,'sos','emergency','manual_sos',200,'pending_review')");
        assertFalse(ids(access.scope(new LambdaQueryWrapper<>())).contains(90L));
        WearSafetyEvent manual=new WearSafetyEvent();manual.setId(90L);manual.setSiteId(1L);
        assertThrows(ServiceException.class,()->access.assertReadable(manual));
        sites.requireLogin().setUserId(200L);
        db.update("DELETE FROM wear_work_task_member");
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).contains(90L));
        access.assertReadable(manual);
        db.update("UPDATE wear_safety_event SET status='closed' WHERE id=90");
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).contains(90L));
        assertFalse(ids(access.actionable(access.scope(new LambdaQueryWrapper<>()))).contains(90L));
        sites.requireLogin().setUserId(999L);
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).contains(90L));
        manual.setSiteId(2L);
        assertThrows(ServiceException.class,()->access.assertReadable(manual));
    }

    private List<Long> ids(LambdaQueryWrapper<WearSafetyEvent> query) {
        query.getSqlSegment();
        String sql=query.getExpression().getNormal().getSqlSegment();
        Matcher matcher=Pattern.compile("#\\{ew.paramNameValuePairs.([^}]+)}").matcher(sql);
        StringBuffer bound=new StringBuffer(); List<Object> values=new ArrayList<>();
        while(matcher.find()) { values.add(query.getParamNameValuePairs().get(matcher.group(1))); matcher.appendReplacement(bound,"?"); }
        matcher.appendTail(bound);
        return db.queryForList("SELECT id FROM wear_safety_event WHERE "+bound+" ORDER BY id",Long.class,values.toArray());
    }

    @Test void memberSeesGroupPeoplesEventsAndOnlyOwnRemindersRegardlessOfEventTask() {
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        sites.requireLogin().setUserId(200L);
        assertEquals(Arrays.asList(1L,3L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
    }
    @Test void pendingEmergencyRemainsVisibleUntilAdminApproves() {
        db.update("UPDATE wear_safety_event SET status='pending_review' WHERE id IN (1,4)");
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L),ids(access.actionable(access.scope(new LambdaQueryWrapper<>()))));
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertEquals(Arrays.asList(1L,2L,4L,5L,6L,7L),ids(access.actionable(access.scope(new LambdaQueryWrapper<>()))));
    }
    @Test void remindersNotifyOnlyWearerAndReviewNotifiesOnlyAdmin() {
        db.execute("CREATE TABLE sys_user(user_id BIGINT,status VARCHAR,del_flag VARCHAR)");
        db.execute("CREATE TABLE sys_role(role_id BIGINT,status VARCHAR,role_key VARCHAR)");
        db.execute("CREATE TABLE sys_user_role(user_id BIGINT,role_id BIGINT)");
        db.execute("CREATE TABLE wear_site_account(user_id BIGINT,site_id BIGINT,status VARCHAR)");
        db.execute("INSERT INTO sys_user VALUES(1,'0','0'),(100,'0','0'),(200,'0','0'),(777,'0','0')");
        db.execute("INSERT INTO wear_site_account VALUES(100,1,'0'),(200,1,'0'),(777,1,'0')");
        WearSafetyEvent row=new WearSafetyEvent();row.setSiteId(1L);row.setId(1L);row.setStatus("open");row.setSeverity("emergency");
        assertEquals(new HashSet<>(Arrays.asList(1L,100L,200L)),new HashSet<>(access.recipients(row)));
        row.setId(3L);row.setSeverity("warning");
        assertEquals(Collections.singletonList(200L),access.recipients(row));
        row.setId(1L);row.setStatus("pending_review");row.setSeverity("emergency");
        assertEquals(Collections.singletonList(1L),access.recipients(row));
        db.update("UPDATE wear_safety_event SET source='manual_sos',event_type='sos',reporter_user_id=100 WHERE id=1");
        row.setSource("manual_sos");row.setEventType("sos");row.setReporterUserId(100L);
        assertEquals(new HashSet<>(Arrays.asList(1L,100L)),new HashSet<>(access.recipients(row)));
    }
    @Test void taskFiltersNarrowTheAuthorizedPeopleScopeIncludingEndedTasks() {
        assertTrue(ids(access.scope(new LambdaQueryWrapper<WearSafetyEvent>().eq(WearSafetyEvent::getTaskId,2L))).isEmpty());
        assertEquals(Collections.singletonList(5L),ids(access.scope(new LambdaQueryWrapper<WearSafetyEvent>().eq(WearSafetyEvent::getTaskId,3L))));
    }
    @Test void leavingGroupImmediatelyRevokesAccessAndUnknownAccountSeesNothing() {
        db.update("DELETE FROM wear_work_task_member WHERE person_id=10");
        assertEquals(Collections.singletonList(4L),ids(access.scope(new LambdaQueryWrapper<>())));
        sites.requireLogin().setUserId(777L);
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).isEmpty());
    }
    @Test void administratorsSeeSafetyEventsButNotOtherPeoplesReminders() {
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertEquals(Arrays.asList(1L,2L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
    }
    @Test void detailAndWritesRejectCrossGroupAndCrossSiteIds() {
        WearSafetyEvent row=new WearSafetyEvent(); row.setId(2L);row.setSiteId(1L);
        assertThrows(ServiceException.class,()->access.assertReadable(row));
        row.setId(1L); access.assertReadable(row);
        row.setSiteId(2L); assertThrows(ServiceException.class,()->access.assertReadable(row));
    }

    @Test void ownersAndGuardiansLoseGroupScopeWhenGroupEnds() {
        sites.requireLogin().setUserId(900L);
        assertEquals(Arrays.asList(1L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        sites.requireLogin().setUserId(300L);
        assertEquals(Arrays.asList(1L,2L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        db.update("UPDATE wear_work_task SET status='ended' WHERE id=1");
        assertEquals(Collections.singletonList(2L),ids(access.scope(new LambdaQueryWrapper<>())));
    }

    @Test void inactivePersonCannotReadGroupEventsOrPersonalReminders() {
        db.update("UPDATE wear_person SET status='1' WHERE account_user_id=100");
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).isEmpty());
        db.update("UPDATE wear_person SET status='0',del_flag='2' WHERE account_user_id=100");
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).isEmpty());
    }

    @Test void matchingTaskIdInAnotherSiteDoesNotGrantAccess() {
        db.update("INSERT INTO wear_safety_event(id,site_id,task_id,person_id,event_type,severity) "
                + "VALUES(8,2,1,20,'impact','high')");
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
    }

    @Test void inboxCountUsesGroupAndPersonalReminderScopeForEveryRole() {
        EventQueryService query = queryService();
        db.update("UPDATE wear_safety_event SET status='pending_review' WHERE id=1");
        assertEquals(5,query.inboxCount().get("count"));
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertEquals(6,query.inboxCount().get("count"));
        when(sites.listScopeSiteIds()).thenReturn(Collections.emptyList());
        assertEquals(0,query.inboxCount().get("count"));
    }

    @Test void listAndTotalCannotEscapeScopeWithAllStatusOrForeignTaskFilter() {
        EventQueryService query = queryService();
        when(events.selectPage(any(Page.class),any())).thenAnswer(call -> {
            List<Long> visible = ids(call.getArgument(1));
            List<WearSafetyEvent> rows = new ArrayList<>();
            for (Long id : visible) {
                WearSafetyEvent event = new WearSafetyEvent(); event.setId(id); rows.add(event);
            }
            return new Page<WearSafetyEvent>(1,20,visible.size()).setRecords(rows);
        });
        assertEquals(5,query.page(1,20,null,"all",null,null,null,null,null,null,null,null,null,null).getTotal());
        assertEquals(0,query.page(1,20,null,"all",null,null,null,null,null,null,null,"2",null,null).getTotal());
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertEquals(6,query.page(1,20,null,"all",null,null,null,null,null,null,null,null,null,null).getTotal());
        assertEquals("2",query.page(1,20,null,"all",null,null,null,null,null,null,null,"2",null,null)
                .getRecords().get(0).getId());
    }

    @Test void activeGroupsContributePeopleButEndedGroupsDoNot() {
        db.update("INSERT INTO wear_person VALUES(40,400,'0','0')");
        db.update("INSERT INTO wear_work_task_member VALUES(2,10),(3,20),(3,40)");
        db.update("INSERT INTO wear_safety_event(id,site_id,task_id,person_id,event_type,severity) "
                + "VALUES(8,1,null,40,'impact','high')");
        assertEquals(Arrays.asList(1L,2L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        // Person 40 is only in an ended group, so even unmatched events are hidden.
        WearSafetyEvent endedGroupPerson = new WearSafetyEvent();
        endedGroupPerson.setId(8L); endedGroupPerson.setSiteId(1L);
        assertThrows(ServiceException.class,()->access.assertReadable(endedGroupPerson));
    }

    @Test void onlyInProgressGroupsGrantScopeWhileOwnRemindersRemainVisible() {
        for (String status : Arrays.asList("draft","ready","paused","ended","completed","cancelled")) {
            db.update("UPDATE wear_work_task SET status=? WHERE id IN (1,3)",status);
            assertEquals(Collections.singletonList(4L),ids(access.scope(new LambdaQueryWrapper<>())),status);
        }
        db.update("UPDATE wear_work_task SET status='in_progress' WHERE id=1");
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        db.update("UPDATE wear_work_task SET status='ended'");
        assertEquals(Arrays.asList(1L,2L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
    }

    @Test void completedInspectionGroupDoesNotGrantScopeBeforeTaskIsMarkedEnded() {
        db.update("UPDATE wear_work_task SET work_type='patrol' WHERE id=1");
        db.update("INSERT INTO wear_inspection_item VALUES(101,1),(102,1)");
        db.update("INSERT INTO wear_inspection_record VALUES(1,101)");
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        db.update("INSERT INTO wear_inspection_record VALUES(1,102)");
        assertEquals(Collections.singletonList(4L),ids(access.scope(new LambdaQueryWrapper<>())));
        db.update("INSERT INTO wear_inspection_item VALUES(103,1)");
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
    }

    @Test void personScopeIgnoresMissingOrForeignEventTaskAndRejectsForeignPersonInOwnTask() {
        db.update("INSERT INTO wear_safety_event(id,site_id,task_id,person_id,event_type,severity) VALUES"
                + "(8,1,null,20,'impact','high'),(9,1,2,20,'impact','high'),"
                + "(10,1,1,30,'impact','high'),(11,1,1,null,'impact','high')");
        assertEquals(Arrays.asList(1L,4L,5L,6L,7L,8L,9L),ids(access.scope(new LambdaQueryWrapper<>())));
        WearSafetyEvent row = new WearSafetyEvent(); row.setSiteId(1L);
        row.setId(8L); access.assertReadable(row);
        row.setId(9L); access.assertReadable(row);
        row.setId(10L); assertThrows(ServiceException.class,()->access.assertReadable(row));
        row.setId(11L); assertThrows(ServiceException.class,()->access.assertReadable(row));
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertEquals(Arrays.asList(1L,2L,4L,5L,6L,7L,8L,9L,10L,11L),ids(access.scope(new LambdaQueryWrapper<>())));
    }

    @Test void removingPersonFromEverySharedGroupRevokesTheirUnmatchedEvents() {
        db.update("INSERT INTO wear_safety_event(id,site_id,person_id,event_type,severity) "
                + "VALUES(8,1,20,'impact','high')");
        assertTrue(ids(access.scope(new LambdaQueryWrapper<>())).contains(8L));
        db.update("DELETE FROM wear_work_task_member WHERE person_id=20");
        assertEquals(Arrays.asList(4L,5L,6L),ids(access.scope(new LambdaQueryWrapper<>())));
    }

    @Test void unnamedRowsAndPlaceholdersAreNeverExposed() {
        db.update("UPDATE wear_safety_event SET alarm_name=null,alarm_code=null WHERE id=1");
        db.update("UPDATE wear_safety_event SET alarm_name='告警名称未提供' WHERE id=6");
        assertEquals(Arrays.asList(4L,5L,7L),ids(access.scope(new LambdaQueryWrapper<>())));
        when(sites.isPlatformAdmin(any())).thenReturn(true);
        assertFalse(ids(access.scope(new LambdaQueryWrapper<>())).contains(1L));
        assertFalse(ids(access.scope(new LambdaQueryWrapper<>())).contains(6L));
    }

    private EventQueryService queryService() {
        EventQueryService query = new EventQueryService();
        ReflectionTestUtils.setField(query,"eventAccess",access);
        ReflectionTestUtils.setField(query,"siteAccessService",sites);
        ReflectionTestUtils.setField(query,"eventMapper",events);
        ReflectionTestUtils.setField(query,"commandService",mock(EventCommandService.class));
        return query;
    }
}
