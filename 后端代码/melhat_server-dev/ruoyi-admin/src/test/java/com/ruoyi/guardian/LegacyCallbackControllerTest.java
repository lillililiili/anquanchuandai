package com.ruoyi.guardian;

import com.ruoyi.headband.pojo.param.GnssNotifyParam;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.pojo.po.SosAlarmRecord;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISosAlarmRecordService;
import com.ruoyi.helmet.vo.SafetyHatListVO;
import com.ruoyi.web.controller.business.ExternalController;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class LegacyCallbackControllerTest {
    @Test void sosKeepsScopedBusinessEventWithoutOpeningUnownedCallOrBroadcastingCredentials() {
        ExternalController controller = new ExternalController();
        LegacyCallbackAccess access = mock(LegacyCallbackAccess.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        ISosAlarmRecordService records = mock(ISosAlarmRecordService.class);
        GuardianIngest ingest = mock(GuardianIngest.class);
        HeadbandService headband = mock(HeadbandService.class);
        ReflectionTestUtils.setField(controller,"callbackAccess",access);
        ReflectionTestUtils.setField(controller,"safetyHatInfoService",hats);
        ReflectionTestUtils.setField(controller,"sosAlarmRecordService",records);
        ReflectionTestUtils.setField(controller,"guardianIngest",ingest);
        ReflectionTestUtils.setField(controller,"headbandService",headband);
        controller.callHat("registered");
        verifyNoInteractions(access,hats,records,ingest,headband);
        GnssNotifyParam report = new GnssNotifyParam();report.setHelmetSn("registered");report.setTimestamp("2026-11-04 08:00:00");
        SafetyHatListVO hat = new SafetyHatListVO();hat.setId(9L);hat.setBindUserId(10L);hat.setBindUserName("person");
        when(hats.getByHatNumber("registered")).thenReturn(hat);
        assertEquals(200,controller.sosCall(report).getCode());
        verify(access).requireDevice("registered");
        verify(records).save(argThat(record -> record instanceof SosAlarmRecord && Long.valueOf(9).equals(record.getHatId())));
        verify(ingest).sos("registered",null,null,"2026-11-04 08:00:00");
        verifyNoInteractions(headband);

        clearInvocations(hats,records,ingest);
        doThrow(new AdminQueryService.QueryFailed(403,"CALLBACK_DEVICE_OUT_OF_SCOPE","denied")).when(access).requireDevice("registered");
        assertThrows(AdminQueryService.QueryFailed.class,()->controller.sosCall(report));
        verifyNoInteractions(hats,records,ingest,headband);
    }
}
