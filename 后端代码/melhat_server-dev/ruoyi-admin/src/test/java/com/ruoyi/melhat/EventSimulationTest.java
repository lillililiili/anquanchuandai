package com.ruoyi.melhat;

import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.event.*;
import com.ruoyi.wear.event.domain.*;
import com.ruoyi.wear.event.dto.*;
import com.ruoyi.wear.event.mapper.*;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
import com.ruoyi.wear.work.EventTaskMatchService;
import org.junit.jupiter.api.*;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import java.util.Collections;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.any;

class EventSimulationTest
{
    private EventIngestService service;
    private WearSafetyEventMapper events;
    private WearEventActionMapper actions;
    private WearDeviceMapper devices;
    private SiteAccessService access;
    private WearDevice device;
    private WearProductModel model;

    @BeforeEach
    void setup()
    {
        service = new EventIngestService();
        events = mock(WearSafetyEventMapper.class);
        actions = mock(WearEventActionMapper.class);
        devices = mock(WearDeviceMapper.class);
        access = mock(SiteAccessService.class);
        ReflectionTestUtils.setField(service, "eventMapper", events);
        ReflectionTestUtils.setField(service, "actionMapper", actions);
        ReflectionTestUtils.setField(service, "deviceMapper", devices);
        ReflectionTestUtils.setField(service, "siteAccessService", access);
        ReflectionTestUtils.setField(service, "assignmentMapper", mock(WearAssignmentMapper.class));
        ReflectionTestUtils.setField(service, "inboxMapper", mock(WearEventInboxMapper.class));
        ReflectionTestUtils.setField(service, "notifyService", mock(EventNotifyService.class));
        ReflectionTestUtils.setField(service, "eventTaskMatchService", mock(EventTaskMatchService.class));
        WearSiteAccountMapper grants = mock(WearSiteAccountMapper.class);
        when(grants.selectList(any())).thenReturn(Collections.emptyList());
        ReflectionTestUtils.setField(service, "siteAccountMapper", grants);
        WearProductModelMapper models = mock(WearProductModelMapper.class);
        ReflectionTestUtils.setField(service, "modelMapper", models);
        model = new WearProductModel(); model.setTypeCode("helmet");
        when(models.selectById(3L)).thenReturn(model);
        device = new WearDevice(); device.setId(2L); device.setSiteId(1L); device.setModelId(3L); device.setSn("CALL-LAB-H");
        when(devices.selectById(2L)).thenReturn(device);
        when(access.parseSiteId("1")).thenReturn(1L);
        LoginUser login = new LoginUser(); SysUser user = new SysUser(); user.setUserName("test"); user.setUserId(9L); login.setUser(user); login.setUserId(9L);
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(login, null, Collections.emptyList()));
    }
    @AfterEach void clear() { SecurityContextHolder.clearContext(); }
    private SimulateRequest request()
    {
        SimulateRequest r = new SimulateRequest(); r.setSourceEventId("call-lab:unit"); r.setSiteId("1");
        r.setDeviceId("2"); r.setType("sos"); r.setScenarioCode("helmet.sos"); return r;
    }
    @Test void persistsSimulationAuditAndDoesNotDuplicateItOnReplay()
    {
        final WearSafetyEvent[] saved = new WearSafetyEvent[1];
        when(events.insert(any(WearSafetyEvent.class))).thenAnswer(i -> {
            saved[0] = i.getArgument(0); saved[0].setId(10L); return 1;
        });
        when(events.selectById(10L)).thenAnswer(i -> saved[0]);
        EventDto dto = service.simulate(request());
        assertEquals(true, dto.getDemo()); assertEquals("simulator", dto.getSource()); assertEquals("2", dto.getDeviceId());
        ArgumentCaptor<WearEventAction> audit = ArgumentCaptor.forClass(WearEventAction.class);
        verify(actions).insert(audit.capture());
        assertEquals("simulate", audit.getValue().getAction()); assertTrue(audit.getValue().getReason().contains("helmet.sos"));
        when(events.selectOne(any())).thenReturn(saved[0]);
        service.simulate(request());
        verify(events).bumpRepeat(10L);
        verify(actions, times(1)).insert(any(WearEventAction.class));
    }
    @Test void rejectsMissingDeviceAndDeviceFromAnotherSiteBeforeWriting()
    {
        device.setSiteId(7L);
        assertThrows(ServiceException.class, () -> service.simulate(request()));
        when(devices.selectById(2L)).thenReturn(null);
        assertThrows(ServiceException.class, () -> service.simulate(request()));
        verify(events, never()).insert(any(WearSafetyEvent.class));
    }

    @Test void everyScenarioReturnsCoreNameAndDescriptionInEventSnapshot()
    {
        final WearSafetyEvent[] saved = new WearSafetyEvent[1];
        when(events.insert(any(WearSafetyEvent.class))).thenAnswer(i -> {
            saved[0] = i.getArgument(0); saved[0].setId(10L); return 1;
        });
        when(events.selectById(10L)).thenAnswer(i -> saved[0]);
        for (Object item : SimulationScenarios.list())
        {
            com.alibaba.fastjson2.JSONObject scenario = (com.alibaba.fastjson2.JSONObject) item;
            model.setTypeCode(scenario.getString("deviceType"));
            SimulateRequest r = request();
            // Identifiers are opaque. Names must come from core metadata.
            r.setSourceEventId("opaque-event-id");
            r.setScenarioCode(scenario.getString("id"));
            r.setType(scenario.getString("type"));
            java.util.Map<String, java.math.BigDecimal> values = new java.util.HashMap<>();
            for (Object fieldItem : scenario.getJSONArray("fields"))
            {
                com.alibaba.fastjson2.JSONObject field = (com.alibaba.fastjson2.JSONObject) fieldItem;
                values.put(field.getString("key"), field.getBigDecimal("value"));
            }
            r.setMeasurements(values);
            EventDto event = service.simulate(r);
            assertEquals(scenario.getString("id"), event.getAlarmCode());
            assertEquals(scenario.getString("label"), event.getAlarmName());
            assertTrue(event.getAlarmDescription().startsWith(event.getAlarmName()));
            for (Object fieldItem : scenario.getJSONArray("fields"))
            {
                com.alibaba.fastjson2.JSONObject field = (com.alibaba.fastjson2.JSONObject) fieldItem;
                assertTrue(event.getAlarmDescription().contains(field.getString("label")));
            }
            assertEquals(event.getAlarmName(), EventViews.toDto(saved[0]).getAlarmName());
        }
    }

    @Test void preservesArbitraryCoreAlarmWithoutGuessingFromTypeOrIdentifier()
    {
        final WearSafetyEvent[] saved = new WearSafetyEvent[1];
        when(events.insert(any(WearSafetyEvent.class))).thenAnswer(i -> {
            saved[0] = i.getArgument(0); saved[0].setId(10L); return 1;
        });
        when(events.selectById(10L)).thenAnswer(i -> saved[0]);
        IngestRequest r = new IngestRequest();
        r.setSource("helmet"); r.setSourceEventId("opaque"); r.setType("realtime"); r.setSiteId("1");
        r.setAlarmCode("vendor.future_alarm"); r.setAlarmName("核心系统新增告警");
        r.setAlarmDescription("核心系统的实际告警描述与参数");
        EventDto dto = service.ingest(r);
        assertEquals(r.getAlarmCode(), dto.getAlarmCode());
        assertEquals(r.getAlarmName(), dto.getAlarmName());
        assertEquals(r.getAlarmDescription(), dto.getAlarmDescription());
        when(events.selectOne(any())).thenReturn(saved[0]);
        r.setAlarmName("后续状态变化");
        assertEquals("核心系统新增告警", service.ingest(r).getAlarmName());
    }
    @Test void rejectsUnauthorizedSimulatorBeforeReadingOrWriting()
    {
        doThrow(new ServiceException("denied", 403)).when(access).assertCanSimulateEvent();
        assertThrows(ServiceException.class, () -> service.simulate(request()));
        verifyNoInteractions(devices, events);
    }
    @Test void refusesCrossSiteDuplicateIdentifier()
    {
        WearSafetyEvent existing = new WearSafetyEvent(); existing.setSiteId(8L);
        when(events.selectOne(any())).thenReturn(existing);
        assertThrows(ServiceException.class, () -> service.simulate(request()));
        verify(events, never()).bumpRepeat(any());
    }
}
