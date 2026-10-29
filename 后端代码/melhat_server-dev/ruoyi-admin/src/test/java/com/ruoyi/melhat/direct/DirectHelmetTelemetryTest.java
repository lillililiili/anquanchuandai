package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.GuardianIngest;
import com.ruoyi.helmet.mapper.RealTimeAlarmMapper;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.mapper.SafetyHatLocationRecordMapper;
import com.ruoyi.helmet.mapper.SosAlarmRecordMapper;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.pojo.po.SosAlarmRecord;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.Arrays;
import java.util.Collections;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DirectHelmetTelemetryTest {
    @Test void onlyExplicitlyRegisteredUndeletedUniqueHelmetIsSupported() {
        Fixture f = new Fixture();
        when(f.hats.findIncludingDeleted("helmet-a")).thenReturn(Collections.singletonList(f.hat));
        assertSame(f.hat, f.service.registered("helmet-a"));
        f.hat.setCreateBy("platform-sync");
        assertNull(f.service.registered("helmet-a"));
        f.hat.setCreateBy("direct-helmet"); f.hat.setDelFlag("2");
        assertNull(f.service.registered("helmet-a"));
        f.hat.setDelFlag("0");
        when(f.hats.findIncludingDeleted("helmet-a")).thenReturn(Arrays.asList(f.hat, f.hat));
        assertNull(f.service.registered("helmet-a"));
    }

    @Test void locationUsesServerBindingAndDoesNotConfuseRelativeHeightWithAltitude() {
        Fixture f = new Fixture();
        f.service.receive(f.hat, DirectHelmetMessage.parse("{\"act\":\"ca_report_location\","
                + "\"device_id\":\"helmet-a\",\"user_id\":\"9999\",\"bat_l\":55,"
                + "\"x_point\":\"35.466123\",\"y_point\":\"112.574204\",\"relative_altitude\":\"3.2\"}"));
        ArgumentCaptor<SafetyHatLocationRecord> location = ArgumentCaptor.forClass(SafetyHatLocationRecord.class);
        verify(f.locations).insert(location.capture());
        assertEquals(7L, location.getValue().getUserId().longValue());
        assertEquals("现场人员", location.getValue().getUserName());
        assertEquals("112.574204", location.getValue().getLng());
        assertEquals("35.466123", location.getValue().getLat());
        assertNull(location.getValue().getAltitude());
        ArgumentCaptor<SafetyHatInfo> update = ArgumentCaptor.forClass(SafetyHatInfo.class);
        verify(f.hats).updateById(update.capture());
        assertEquals(55, update.getValue().getElectricityUsage().intValue());
        assertNull(update.getValue().getBindUserId());
        verify(f.ingest).directLocation(argThat(point -> "helmet-a".equals(point.getString("deviceId")) && "112.574204".equals(point.getString("longitude")) && "UNKNOWN".equals(point.getString("coordinateSystem"))));
    }

    @Test void heartbeatWithoutFixUpdatesBatteryButNeverCreatesLocation() {
        Fixture f = new Fixture();
        f.service.receive(f.hat, DirectHelmetMessage.parse("{\"act\":\"ca_report_location\",\"bat_l\":30,\"is_weared\":1}"));
        verify(f.hats).updateById(any(SafetyHatInfo.class));
        verifyNoInteractions(f.locations);
        verify(f.ingest, never()).directLocation(any());
    }

    @Test void unknownAlarmCodeIsRetainedAndSosDoesNotPretendMediaCallSucceeded() {
        Fixture f = new Fixture();
        f.service.receive(f.hat, DirectHelmetMessage.parse("{\"act\":\"ca_sos\",\"type\":\"vendor-117\"}"));
        ArgumentCaptor<RealTimeAlarm> alarm = ArgumentCaptor.forClass(RealTimeAlarm.class);
        verify(f.alarms).insert(alarm.capture());
        assertEquals("vendor-117", alarm.getValue().getAlarmType());
        assertEquals("vendor-117", JSONObject.parseObject(alarm.getValue().getDescription()).getString("rawType"));
        verify(f.ingest).projectDirectEvent(argThat(event -> "vendor-117".equals(event.getString("rawType")) && "real_time_alarm".equals(event.getString("sourceRecordType"))));
        f.service.receive(f.hat, DirectHelmetMessage.parse("{\"act\":\"ca_sip_sos\"}"));
        ArgumentCaptor<SosAlarmRecord> sos = ArgumentCaptor.forClass(SosAlarmRecord.class);
        verify(f.sos).insert(sos.capture());
        assertTrue(sos.getValue().getDescription().contains("不代表通话已接通"));
        verify(f.ingest).projectDirectEvent(argThat(event -> "ca_sip_sos".equals(event.getString("act")) && "sos_alarm_record".equals(event.getString("sourceRecordType"))));
    }

    private static final class Fixture {
        final SafetyHatInfoMapper hats = mock(SafetyHatInfoMapper.class);
        final SafetyHatLocationRecordMapper locations = mock(SafetyHatLocationRecordMapper.class);
        final RealTimeAlarmMapper alarms = mock(RealTimeAlarmMapper.class);
        final SosAlarmRecordMapper sos = mock(SosAlarmRecordMapper.class);
        final GuardianIngest ingest = mock(GuardianIngest.class);
        final DirectHelmetTelemetryService service = new DirectHelmetTelemetryService(hats,
                new DirectHelmetPersistence(hats, locations, alarms, sos), ingest);
        final SafetyHatInfo hat = new SafetyHatInfo();
        Fixture() {
            hat.setId(3L); hat.setHatNumber("helmet-a"); hat.setBindUserId(7L);
            hat.setBindUserName("现场人员"); hat.setCreateBy("direct-helmet"); hat.setDelFlag("0");
            when(hats.updateById(any(SafetyHatInfo.class))).thenReturn(1);
            when(locations.insert(any(SafetyHatLocationRecord.class))).thenReturn(1);
            when(alarms.insert(any(RealTimeAlarm.class))).thenReturn(1);
            when(sos.insert(any(SosAlarmRecord.class))).thenReturn(1);
        }
    }
}
