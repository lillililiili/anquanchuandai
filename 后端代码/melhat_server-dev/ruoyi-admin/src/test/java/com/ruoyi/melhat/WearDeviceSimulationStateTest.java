package com.ruoyi.melhat;

import java.util.*;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.*;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.DeviceSimulationStateService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.dto.DeviceDto;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import static org.mockito.Mockito.*;
import static org.junit.jupiter.api.Assertions.*;

class WearDeviceSimulationStateTest
{
    DeviceSimulationStateService service;
    WearDeviceMapper devices;
    SiteAccessService access;
    RedisCache redis;
    Map<String, Object> saved;

    @BeforeEach void setup()
    {
        service = new DeviceSimulationStateService();
        devices = mock(WearDeviceMapper.class); access = mock(SiteAccessService.class); redis = mock(RedisCache.class);
        ReflectionTestUtils.setField(service, "devices", devices);
        ReflectionTestUtils.setField(service, "access", access);
        ReflectionTestUtils.setField(service, "redis", redis);
        ReflectionTestUtils.setField(service, "enabled", true);
        WearDevice d = new WearDevice(); d.setId(42L); d.setSiteId(1L);
        when(devices.selectByIdForUpdate(42L)).thenReturn(d);
        when(access.requireCurrentSiteForWrite()).thenReturn(1L);
        when(devices.applySimulationState(eq(42L), any(Date.class), anyString())).thenReturn(1);
        doAnswer(a -> { saved = new HashMap<>(a.getArgument(1)); return null; }).when(redis)
            .setCacheObject(anyString(), any(), eq(7), eq(TimeUnit.DAYS));
        when(redis.getCacheObject(anyString())).thenAnswer(a -> saved);
    }
    DeviceDto dto() { DeviceDto d = new DeviceDto(); d.setId("42"); d.setSiteId("1"); return d; }
    Map<String,Object> report(boolean online, String status)
    {
        Map<String,Object> b = new HashMap<>(); b.put("online",online); b.put("status",status); b.put("statusLabel", "normal".equals(status)?"正常":"脱帽告警"); return b;
    }
    @Test void mainPlatformRetainsOnlineOfflineAndAbnormalWithoutReadingLab()
    {
        service.report(42L,report(true,"normal")); DeviceDto d = dto(); service.enrich(d);
        assertEquals("1",d.getOnline()); assertTrue(d.isSimulation()); assertEquals("normal",d.getSimulationStatus());
        service.report(42L,report(true,"helmet.removal")); d=dto(); service.enrich(d);
        assertEquals("脱帽告警",d.getSimulationStatusLabel());
        service.report(42L,report(false,"normal")); d=dto(); service.enrich(d);
        assertEquals("0",d.getOnline());
        verify(devices,times(3)).applySimulationState(eq(42L), any(Date.class), anyString());
    }
    @Test void expiredConsoleHeartbeatCannotKeepEmployeeOnline()
    {
        service.report(42L,report(true,"normal")); saved.put("receivedAt",System.currentTimeMillis()-31000);
        DeviceDto d=dto(); service.enrich(d); assertEquals("0",d.getOnline());
    }
    @Test void laterRealTelemetryAndDifferentSiteDoNotUseSimulation()
    {
        service.report(42L,report(true,"helmet.removal"));
        DeviceDto d=dto(); d.setLastReportedAt(new Date(System.currentTimeMillis()+2000)); service.enrich(d); assertFalse(d.isSimulation());
        d=dto(); d.setSiteId("2"); service.enrich(d); assertFalse(d.isSimulation());
    }
    @Test void crossSiteAndInvalidPayloadCannotWrite()
    {
        when(access.requireCurrentSiteForWrite()).thenReturn(2L);
        assertThrows(ServiceException.class,()->service.report(42L,report(true,"normal")));
        when(access.requireCurrentSiteForWrite()).thenReturn(1L);
        assertThrows(ServiceException.class,()->service.report(42L,Collections.singletonMap("online","true")));
        verify(devices,never()).applySimulationState(anyLong(),any(),anyString());
    }
}
