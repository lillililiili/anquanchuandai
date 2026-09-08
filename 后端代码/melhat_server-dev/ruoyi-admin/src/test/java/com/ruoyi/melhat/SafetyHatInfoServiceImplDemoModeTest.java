package com.ruoyi.melhat;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.impl.SafetyHatInfoServiceImpl;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class SafetyHatInfoServiceImplDemoModeTest {

    @Test
    void demoModeReturnsLocalRecordsAndStatusesWithoutHeadbandSync() {
        HeadbandService headbandService = mock(HeadbandService.class);
        SafetyHatInfoServiceImpl service = service(headbandService, true);
        SafetyHatInfo localHat = hat("MH-DEMO-001", "0", "local-uid");
        Page<SafetyHatInfo> localPage = new Page<>();
        localPage.setRecords(Arrays.asList(localHat));

        IPage<SafetyHatInfo> result = ReflectionTestUtils.invokeMethod(service, "getStatusInfo", localPage);

        assertSame(localPage, result);
        assertEquals("0", result.getRecords().get(0).getStatus());
        assertEquals("local-uid", result.getRecords().get(0).getUid());
        verifyNoInteractions(headbandService);
    }

    @Test
    void nonDemoModeRetainsHeadbandSynchronizationBranch() throws Exception {
        HeadbandService headbandService = mock(HeadbandService.class);
        SafetyHatInfoServiceImpl service = service(headbandService, false);
        SafetyHatInfo localHat = hat("MH-DEMO-001", "0", "local-uid");
        Page<SafetyHatInfo> localPage = new Page<>();
        localPage.setRecords(Arrays.asList(localHat));
        HeadbandVO remoteHat = new HeadbandVO();
        remoteHat.setHelmetSn("MH-DEMO-001");
        remoteHat.setOnline("1");
        remoteHat.setUid_device("remote-uid");
        when(headbandService.getHeadBandList(anyMap())).thenReturn(Arrays.asList(remoteHat));

        IPage<SafetyHatInfo> result = ReflectionTestUtils.invokeMethod(service, "getStatusInfo", localPage);

        assertSame(localPage, result);
        assertEquals("1", result.getRecords().get(0).getStatus());
        assertEquals("remote-uid", result.getRecords().get(0).getUid());
        verify(headbandService).getHeadBandList(anyMap());
    }

    private SafetyHatInfoServiceImpl service(HeadbandService headbandService, boolean demoMode) {
        SafetyHatInfoServiceImpl service = new SafetyHatInfoServiceImpl();
        ReflectionTestUtils.setField(service, "headbandService", headbandService);
        ReflectionTestUtils.setField(service, "demoMode", demoMode);
        return service;
    }

    private SafetyHatInfo hat(String number, String status, String uid) {
        SafetyHatInfo hat = new SafetyHatInfo();
        hat.setHatNumber(number);
        hat.setStatus(status);
        hat.setUid(uid);
        return hat;
    }
}
