package com.ruoyi.melhat;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.*;
import com.ruoyi.wear.web.InspectionAccessConfig;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class InspectionEventWorkflowTest {
    EventCommandService service;
    WearSafetyEventMapper events;
    WearEventActionMapper actions;
    SiteAccessService sites;
    EventNotifyService notifications;
    WearSafetyEvent row;
    EventEvidenceService evidence;

    @BeforeEach void setup() {
        service=new EventCommandService(); events=mock(WearSafetyEventMapper.class);
        actions=mock(WearEventActionMapper.class); sites=mock(SiteAccessService.class);
        notifications=mock(EventNotifyService.class);
        evidence=mock(EventEvidenceService.class);
        ReflectionTestUtils.setField(service,"evidence",evidence);
        com.baomidou.mybatisplus.core.metadata.TableInfoHelper.initTableInfo(new org.apache.ibatis.builder.MapperBuilderAssistant(new com.baomidou.mybatisplus.core.MybatisConfiguration(),""), com.ruoyi.wear.event.domain.WearEventAction.class);
        ReflectionTestUtils.setField(service,"eventMapper",events);
        ReflectionTestUtils.setField(service,"actionMapper",actions);
        ReflectionTestUtils.setField(service,"siteAccessService",sites);
        ReflectionTestUtils.setField(service,"eventAccess",mock(EventAccessService.class));
        ReflectionTestUtils.setField(service,"notifyService",notifications);
        row=new WearSafetyEvent(); row.setId(1L);row.setSiteId(1L);row.setEventType("geofence");row.setStatus("open");row.setVersion(1);row.setSeverity("abnormal");
        row.setClaimantUserId(999L); // Legacy ownership must not exclude a group member.
        when(events.selectById(1L)).thenReturn(row);
        SysUser account=new SysUser(); account.setUserId(100L);account.setUserName("inspector");
        LoginUser login=new LoginUser();login.setUserId(100L);login.setUser(account);
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(login,null,Collections.emptyList()));
    }
    @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }

    @Test void manualSosGoesDirectlyToAdminWithoutFieldReportAndReopensAtApproval() {
        row.setSource("manual_sos");row.setEventType("sos");row.setSeverity("emergency");
        row.setStatus("pending_review");row.setReporterUserId(200L);
        LoginUser reviewer=new LoginUser();reviewer.setUserId(100L);
        when(sites.requireLogin()).thenReturn(reviewer);
        when(events.closeIfStatus(1L,"pending_review",1,"inspector")).thenReturn(1);
        service.close(1L,"管理员已核实并处理",1);
        verify(actions,never()).selectList(any());
        row.setReporterUserId(100L);
        assertThrows(ServiceException.class,()->service.close(1L,"自行审批",1));
        row.setStatus("closed");
        when(events.reopenManualSos(1L,1,"inspector")).thenReturn(1);
        service.reopen(1L,"重新核查",1);
        verify(events).reopenManualSos(1L,1,"inspector");
        verify(events,never()).reopenIfClosed(anyLong(),anyInt(),anyString());
    }

    @Test void groupMemberSubmitsAbnormalWithPhotosAndClosesImmediately() {
        when(events.handleIfActive(1L,"closed",1,"inspector")).thenReturn(1);
        service.handle(1L,"围栏定位偏移",1);
        verify(events).handleIfActive(1L,"closed",1,"inspector");
        verify(notifications).notifyAfterCommit(row);
        verify(sites,never()).assertCanClaimEvent();
        assertThrows(ServiceException.class,()->service.claim(1L,1));
        assertThrows(ServiceException.class,()->service.transfer(1L,"3","转交",1));
    }
    @Test void oversizedCauseAndConcurrentReportCannotWriteAnotherAction() {
        assertThrows(ServiceException.class,()->service.handle(1L,String.join("",Collections.nCopies(501,"字")),1));
        verify(events,never()).handleIfActive(anyLong(),anyString(),anyInt(),anyString());
        assertThrows(ServiceException.class,()->service.handle(1L,"已说明原因",1));
        verifyNoInteractions(actions,notifications);
    }
    @Test void ownDeviceReminderConfirmsOnceWithoutReviewNotification() {
        row.setEventType("realtime");row.setSeverity("warning");row.setAlarmName("低电量");
        when(events.closeIfStatus(1L,"open",1,"inspector")).thenReturn(1);
        service.confirm(1L,1);
        verify(events).closeIfStatus(1L,"open",1,"inspector");verifyNoInteractions(notifications);
        when(events.closeIfStatus(1L,"open",1,"inspector")).thenReturn(0);
        assertThrows(ServiceException.class,()->service.confirm(1L,1));
        verify(actions,times(1)).insert(any());
    }
    @Test void safetyEventsCannotUseConfirmationShortcut() {
        assertThrows(ServiceException.class,()->service.confirm(1L,1));
        row.setEventType("realtime");row.setAlarmName("低电量");row.setSeverity("high");
        assertFalse(EventReminderPolicy.isReminder(row));
        assertThrows(ServiceException.class,()->service.confirm(1L,1));
        row.setSeverity("warning");assertTrue(EventReminderPolicy.isReminder(row));
        assertThrows(ServiceException.class,()->service.handle(1L,"设备提醒",1));
    }
    @Test void oldReviewerRoleCannotReviewAndOnlyAdminCanManage() {
        assertFalse(WearRoleKeys.canReviewEvent(Collections.singleton("wear_reviewer"),false));
        assertFalse(WearRoleKeys.canEditTask(Collections.singleton("wear_team_lead"),false));
        assertTrue(WearRoleKeys.canReviewEvent(Collections.singleton("admin"),false));
        doThrow(new ServiceException("管理员复核",403)).when(sites).assertCanReviewEvent();
        row.setStatus("pending_review");assertThrows(ServiceException.class,()->service.close(1L,"复核",1));
        verify(events,never()).closeIfStatus(anyLong(),anyString(),anyInt(),anyString());
    }
    @Test void emergencyMustAwaitDifferentAdministratorAndCannotSkipFieldReport() {
        row.setSeverity("emergency");
        when(events.handleIfActive(1L,"pending_review",1,"inspector")).thenReturn(1);
        service.handle(1L,"现场已确认并拍照",1);
        verify(events).handleIfActive(1L,"pending_review",1,"inspector");
        assertThrows(ServiceException.class,()->service.close(1L,"通过",1));
        row.setStatus("pending_review");
        assertThrows(ServiceException.class,()->service.close(1L,"通过",1));
        com.ruoyi.wear.event.domain.WearEventAction report=new com.ruoyi.wear.event.domain.WearEventAction();report.setActor("inspector");
        when(actions.selectList(any())).thenReturn(Collections.singletonList(report));
        assertThrows(ServiceException.class,()->service.close(1L,"通过",1));
        report.setActor("another-field-user");
        when(events.closeIfStatus(1L,"pending_review",1,"inspector")).thenReturn(1);
        service.close(1L,"已核实，通过",1);
        verify(events).closeIfStatus(1L,"pending_review",1,"inspector");
    }
    @Test void emptyOptionalReportClosesAbnormalButEmergencyStillNeedsReview() throws Exception {
        when(events.handleIfActive(1L,"closed",1,"inspector")).thenReturn(1);
        service.report(1L,null,1,null);
        verify(events).handleIfActive(1L,"closed",1,"inspector");
        row.setSeverity("emergency");
        when(events.handleIfActive(1L,"pending_review",1,"inspector")).thenReturn(1);
        service.report(1L,"  ",1,Collections.emptyList());
        verify(events).handleIfActive(1L,"pending_review",1,"inspector");
        verify(actions,times(2)).insert(any());
    }
    @Test void multipartEndpointAcceptsOmittedCommentAndFiles() throws Exception {
        com.ruoyi.wear.web.v1.WearEventController controller=new com.ruoyi.wear.web.v1.WearEventController();
        EventCommandService commands=mock(EventCommandService.class);
        ReflectionTestUtils.setField(controller,"commandService",commands);
        org.springframework.test.web.servlet.MockMvc mvc=org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart("/api/v1/events/1/report").param("version","1"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isOk());
        verify(commands).report(1L,"",1,null);
    }
    @Test void actualDeviceTypeControlsClassificationWithoutInferringPersonFall() {
        row.setDeviceType("helmet");row.setAlarmCode("helmet.battery");assertEquals("warning",EventSeverityPolicy.classify(row));
        row.setAlarmCode("watch.battery");assertEquals("abnormal",EventSeverityPolicy.classify(row));
        row.setAlarmCode("helmet.fall");row.setEventType("fall");assertEquals("abnormal",EventSeverityPolicy.classify(row));
        row.setAlarmCode("helmet.sos");row.setEventType("sos");assertEquals("emergency",EventSeverityPolicy.classify(row));
    }
    @Test void apiAllowlistAllowsInspectionAndReportsButRejectsManagementAndReview() {
        assertTrue(InspectionAccessConfig.allowsInspector("GET","/api/v1/work-tasks/mine"));
        assertTrue(InspectionAccessConfig.allowsInspector("POST","/api/v1/work-tasks/1/inspection/reports"));
        assertTrue(InspectionAccessConfig.allowsInspector("POST","/api/v1/events/1/confirm"));
        assertTrue(InspectionAccessConfig.allowsInspector("POST","/api/v1/events/1/report"));
        assertTrue(InspectionAccessConfig.allowsInspector("GET","/api/v1/events/1/media"));
        for(String path: Arrays.asList("/api/v1/work-tasks","/api/v1/duty/operators","/api/v1/people/1/equipment"))
            assertFalse(InspectionAccessConfig.allowsInspector("GET",path),path);
        for(String action: Arrays.asList("claim","transfer","close","reopen","task"))
            assertFalse(InspectionAccessConfig.allowsInspector("POST","/api/v1/events/1/"+action),action);
    }
}
