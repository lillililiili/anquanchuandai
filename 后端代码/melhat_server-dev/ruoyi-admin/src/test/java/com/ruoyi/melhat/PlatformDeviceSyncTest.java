package com.ruoyi.melhat;

import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.PlatformDeviceSyncService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class PlatformDeviceSyncTest {
    @Test
    void importsUnboundDevicesAndSecondSyncIsIdempotent() throws Exception {
        HeadbandService platform = mock(HeadbandService.class);
        SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
        when(platform.getHeadBandList(anyMap())).thenReturn(Collections.singletonList(device("REAL-1", "0")));
        Map<String, SafetyHatInfo> rows = new HashMap<>();
        when(mapper.findIncludingDeleted(anyString())).thenAnswer(i -> rows.containsKey(i.getArgument(0))
                ? Collections.singletonList(rows.get(i.getArgument(0))) : Collections.emptyList());
        when(mapper.insert(any(SafetyHatInfo.class))).thenAnswer(i -> {
            SafetyHatInfo row = i.getArgument(0); rows.put(row.getHatNumber(), row); return 1;
        });
        PlatformDeviceSyncService service = new PlatformDeviceSyncService(platform, mapper);
        assertEquals(1, service.sync("admin").get("added"));
        assertEquals(1, service.sync("admin").get("unchanged"));
        assertNull(rows.get("REAL-1").getBindUserId());
        assertNull(rows.get("REAL-1").getBindGroupId());
        assertEquals("0", rows.get("REAL-1").getStatus());
        verify(mapper, times(1)).insert(any(SafetyHatInfo.class));
        verify(mapper, never()).updateById(any(SafetyHatInfo.class));
    }

    @Test
    void updateDoesNotOverwriteBindingsAndDoesNotRestoreDeletedDevice() throws Exception {
        HeadbandService platform = mock(HeadbandService.class);
        SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
        when(platform.getHeadBandList(anyMap())).thenReturn(Arrays.asList(device("REAL-1", "0"), device("REAL-2", "0")));
        SafetyHatInfo bound = new SafetyHatInfo(); bound.setId(1L); bound.setStatus("1"); bound.setDelFlag("0");
        bound.setBindUserId(11L); bound.setBindGroupId(22L);
        SafetyHatInfo deleted = new SafetyHatInfo(); deleted.setDelFlag("2");
        when(mapper.findIncludingDeleted("REAL-1")).thenReturn(Collections.singletonList(bound));
        when(mapper.findIncludingDeleted("REAL-2")).thenReturn(Collections.singletonList(deleted));
        when(mapper.updateById(any(SafetyHatInfo.class))).thenReturn(1);
        Map<String, Integer> result = new PlatformDeviceSyncService(platform, mapper).sync("admin");
        assertEquals(1, result.get("updated")); assertEquals(1, result.get("skippedDeleted"));
        ArgumentCaptor<SafetyHatInfo> capture = ArgumentCaptor.forClass(SafetyHatInfo.class);
        verify(mapper).updateById(capture.capture());
        assertNull(capture.getValue().getBindUserId()); assertNull(capture.getValue().getBindGroupId());
        assertEquals(11L, bound.getBindUserId()); assertEquals(22L, bound.getBindGroupId());
        verify(mapper, never()).insert(any(SafetyHatInfo.class));
    }

    @Test
    void rejectsDuplicateRemoteNumbersBeforeWriting() throws Exception {
        HeadbandService platform = mock(HeadbandService.class);
        SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
        when(platform.getHeadBandList(anyMap())).thenReturn(Arrays.asList(device("REAL-1", "0"), device("REAL-1", "0")));
        assertThrows(ServiceException.class, () -> new PlatformDeviceSyncService(platform, mapper).sync("admin"));
        verifyNoInteractions(mapper);
    }

    private HeadbandVO device(String sn, String status) {
        HeadbandVO device = new HeadbandVO(); device.setHelmetSn(sn); device.setOnline(status); device.setUid_device("uid-" + sn);
        return device;
    }
}
