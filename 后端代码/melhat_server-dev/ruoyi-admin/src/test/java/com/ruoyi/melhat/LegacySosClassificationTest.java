package com.ruoyi.melhat;

import java.util.Arrays;
import java.util.Collections;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.mapper.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class LegacySosClassificationTest {
    @Test void legacySnapshotsRetainSosIdentityAcrossAllOldLevels() {
        for (String level : Arrays.asList(null, "", "high", "abnormal", "warning")) {
            WearSafetyEvent row = legacy(level);
            EventDto dto = EventViews.toDto(row);
            assertEquals("emergency", dto.getSeverity());
            assertEquals("SOS 求助", dto.getAlarmName());
            assertEquals("sos", dto.getType());
            assertEquals("159", dto.getId());
            assertEquals("陈建国", dto.getPersonName());
            assertEquals("RL-H001", dto.getSn());
            assertFalse(EventReminderPolicy.isReminder(row));
            assertTrue(EventSeverityPolicy.isEmergency(row));
            row.setAlarmName("告警名称未提供");
            assertEquals("SOS 求助", EventViews.toDto(row).getAlarmName());
            row.setAlarmName("手动 SOS 报警");
            assertEquals("手动 SOS 报警", EventViews.toDto(row).getAlarmName());
        }
    }

    @Test void legacySosReportCannotCompleteVerificationOrUseReminderShortcut() {
        SysUser user = new SysUser(); user.setUserId(9L); user.setUserName("inspector");
        LoginUser login = new LoginUser(); login.setUserId(9L); login.setUser(user);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(login, null, Collections.emptyList()));
        try {
            for (String level : Arrays.asList(null, "high", "warning")) {
                WearSafetyEvent row = legacy(level);
                WearSafetyEventMapper events = mock(WearSafetyEventMapper.class);
                WearEventActionMapper actions = mock(WearEventActionMapper.class);
                EventCommandService commands = new EventCommandService();
                EventEvidenceService evidence = mock(EventEvidenceService.class);
                ReflectionTestUtils.setField(commands,"eventMapper",events);
                ReflectionTestUtils.setField(commands,"actionMapper",actions);
                ReflectionTestUtils.setField(commands,"evidence",evidence);
                ReflectionTestUtils.setField(commands,"siteAccessService",mock(SiteAccessService.class));
                ReflectionTestUtils.setField(commands,"eventAccess",mock(EventAccessService.class));
                ReflectionTestUtils.setField(commands,"notifyService",mock(EventNotifyService.class));
                when(events.selectById(159L)).thenReturn(row);
                when(evidence.hasSubmission(159L,1)).thenReturn(true);
                when(events.handleIfActive(159L,"pending_review",1,"inspector")).thenReturn(1);
                assertThrows(ServiceException.class, () -> commands.confirm(159L,1));
                assertThrows(ServiceException.class, () -> commands.close(159L,"未经现场核验",1));
                commands.handle(159L,"人员已找到，等待管理员核实",1);
                verify(events).handleIfActive(159L,"pending_review",1,"inspector");
                verify(events,never()).closeIfStatus(anyLong(),anyString(),anyInt(),anyString());
                verify(actions).insert(argThat(a -> "pending_review".equals(a.getToStatus())));
            }
        } finally { SecurityContextHolder.clearContext(); }
    }

    @Test void endingLinkedSosAssistanceOnlyUpdatesCallNotEventVerification() {
        com.ruoyi.wear.call.CallService service = new com.ruoyi.wear.call.CallService();
        com.ruoyi.wear.call.mapper.WearCallSessionMapper calls = mock(com.ruoyi.wear.call.mapper.WearCallSessionMapper.class);
        WearSafetyEventMapper events = mock(WearSafetyEventMapper.class);
        SiteAccessService sites = mock(SiteAccessService.class);
        com.ruoyi.wear.call.CallGateway gateway = mock(com.ruoyi.wear.call.CallGateway.class);
        com.ruoyi.wear.call.domain.WearCallSession call = new com.ruoyi.wear.call.domain.WearCallSession();
        call.setId(7L); call.setEventId(159L); call.setSiteId(1L); call.setDeviceId(9L);
        call.setKind("sos"); call.setStatus("connected"); call.setRequesterUserId(9L);
        call.setSn("RL-H001"); call.setChannelName("sos-159");
        LoginUser login = new LoginUser(); login.setUserId(9L);
        when(sites.requireLogin()).thenReturn(login);
        when(calls.selectById(7L)).thenReturn(call);
        ReflectionTestUtils.setField(service,"callMapper",calls);
        ReflectionTestUtils.setField(service,"eventMapper",events);
        ReflectionTestUtils.setField(service,"siteAccessService",sites);
        ReflectionTestUtils.setField(service,"callGateway",gateway);
        ReflectionTestUtils.setField(service,"deviceMapper",mock(com.ruoyi.wear.device.mapper.WearDeviceMapper.class));
        assertEquals("ended", service.end(7L).getStatus());
        assertEquals(159L, call.getEventId());
        verify(calls).updateById(call);
        verifyNoInteractions(events);
        verify(gateway).endChannel("sos-159");
        verify(gateway).endDevice("RL-H001");
        verifyNoMoreInteractions(gateway);
    }

    private WearSafetyEvent legacy(String level) {
        WearSafetyEvent row = new WearSafetyEvent();
        row.setId(159L); row.setEventType("sos"); row.setSeverity(level);
        row.setStatus("open"); row.setVersion(1); row.setSiteId(1L);
        row.setPersonName("陈建国"); row.setSn("RL-H001");
        return row;
    }
}
