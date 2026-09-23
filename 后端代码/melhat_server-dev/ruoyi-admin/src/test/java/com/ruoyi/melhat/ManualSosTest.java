package com.ruoyi.melhat;

import java.util.*;
import org.junit.jupiter.api.*;
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.*;
import com.ruoyi.wear.event.mapper.*;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.web.InspectionAccessConfig;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ManualSosTest {
    ManualSosService service;
    WearSafetyEventMapper events;
    WearEventActionMapper actions;
    SiteAccessService sites;
    EventNotifyService notifications;
    WearSafetyEvent stored;
    static final String KEY="manual-request-0001";

    @BeforeEach void setup() {
        service=new ManualSosService();events=mock(WearSafetyEventMapper.class);
        actions=mock(WearEventActionMapper.class);sites=mock(SiteAccessService.class);
        notifications=mock(EventNotifyService.class);
        ReflectionTestUtils.setField(service,"events",events);
        ReflectionTestUtils.setField(service,"actions",actions);
        ReflectionTestUtils.setField(service,"sites",sites);
        ReflectionTestUtils.setField(service,"notifications",notifications);
        ReflectionTestUtils.setField(service,"people",mock(WearPersonMapper.class));
        SysUser account=new SysUser();account.setUserId(100L);account.setUserName("reporter");account.setNickName("报警人");
        LoginUser login=new LoginUser();login.setUserId(100L);login.setUser(account);
        when(sites.requireLogin()).thenReturn(login);when(sites.requireCurrentSiteForWrite()).thenReturn(1L);
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(login,null,Collections.emptyList()));
        when(events.selectOne(any())).thenAnswer(call->stored);
        when(events.insert(any())).thenAnswer(call->{stored=call.getArgument(0);stored.setId(90L);return 1;});
    }
    @AfterEach void cleanup() {SecurityContextHolder.clearContext();}

    @Test void submitsRealEmergencyOnceWithServerIdentityAndAudit() {
        assertEquals("pending_review",service.submit(KEY," 锅炉平台 "," 需要协助 ").getStatus());
        assertEquals(100L,stored.getReporterUserId());assertEquals(1L,stored.getSiteId());
        assertEquals("sos",stored.getEventType());assertEquals("emergency",stored.getSeverity());assertEquals(0,stored.getDemo());
        assertNull(stored.getDeviceId());assertNull(stored.getTaskId());
        assertEquals("报警位置：锅炉平台\n报警说明：需要协助",stored.getAlarmDescription());
        assertEquals("90",service.submit(KEY,"锅炉平台","需要协助").getId());
        verify(events,times(1)).insert(any());verify(notifications,times(1)).notifyAfterCommit(stored);
        ArgumentCaptor<WearEventAction> action=ArgumentCaptor.forClass(WearEventAction.class);
        verify(actions).insert(action.capture());assertEquals("manual_sos",action.getValue().getAction());
        assertEquals("pending_review",action.getValue().getToStatus());
        assertThrows(ServiceException.class,()->service.submit(KEY,"另一处","需要协助"));
    }
    @Test void rejectsMissingFieldsAndUnauthorizedSiteWithoutWriting() {
        assertThrows(ServiceException.class,()->service.submit(KEY," ","需要协助"));
        assertThrows(ServiceException.class,()->service.submit(KEY,"平台"," "));
        assertThrows(ServiceException.class,()->service.submit("bad","平台","需要协助"));
        assertThrows(ServiceException.class,()->service.submit(KEY,"平台",String.join("",Collections.nCopies(501,"字"))));
        doThrow(new ServiceException("未授权厂站",403)).when(sites).assertAuthorized(1L);
        assertThrows(ServiceException.class,()->service.submit(KEY,"平台","需要协助"));
        verify(events,never()).insert(any());verifyNoInteractions(actions,notifications);
    }
    @Test void racedDuplicateReturnsExistingEventWithoutAnotherAuditOrNotification() {
        doAnswer(call->{stored=call.getArgument(0);stored.setId(91L);throw new DuplicateKeyException("duplicate");}).when(events).insert(any());
        assertEquals("91",service.submit(KEY,"平台","需要协助").getId());
        verifyNoInteractions(actions,notifications);
    }
    @Test void endpointIgnoresSpoofedAccountStatusAndSite() {
        com.ruoyi.wear.web.v1.WearEventController controller=new com.ruoyi.wear.web.v1.WearEventController();
        ReflectionTestUtils.setField(controller,"manualSos",service);
        Map<String,Object> body=new HashMap<>();body.put("requestId",KEY);body.put("location","平台");body.put("description","需要协助");
        body.put("reporterUserId",200);body.put("siteId",999);body.put("status","closed");
        controller.manualSos(body);
        assertEquals(100L,stored.getReporterUserId());assertEquals(1L,stored.getSiteId());assertEquals("pending_review",stored.getStatus());
        assertTrue(InspectionAccessConfig.allowsInspector("POST","/api/v1/events/manual-sos"));
        assertFalse(InspectionAccessConfig.allowsInspector("POST","/api/v1/events/90/close"));
    }
    @Test void genericIngestCannotForgeManualSource() {
        com.ruoyi.wear.event.dto.IngestRequest input=new com.ruoyi.wear.event.dto.IngestRequest();input.setSource("MANUAL_SOS");
        assertThrows(ServiceException.class,()->new EventIngestService().ingest(input));
    }
}
