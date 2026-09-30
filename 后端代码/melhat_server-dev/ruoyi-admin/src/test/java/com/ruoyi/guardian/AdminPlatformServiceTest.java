package com.ruoyi.guardian;
import com.alibaba.fastjson2.*;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.helmet.service.PlatformDeviceSyncService;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class AdminPlatformServiceTest {
    JSONObject seed(String path)throws Exception{return JSON.parseObject(StreamUtils.copyToString(new ClassPathResource(path).getInputStream(),StandardCharsets.UTF_8));}
    HeadbandVO hat(String sn,String online){HeadbandVO h=new HeadbandVO();h.setHelmetSn(sn);h.setOnline(online);h.setUid_device("uid-"+sn);return h;}
    @Test void importRepeatAndStatusChangePreserveLifecycleAndProjectUnassigned()throws Exception {
        JSONObject state=seed("admin-seed.json");AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->JSON.parseObject(state.toJSONString()));
        doAnswer(i->{JSONObject saved=i.getArgument(0);state.clear();state.putAll(saved);return null;}).when(ledger).write(any());
        AdminQueryService query=mock(AdminQueryService.class);when(query.allows(any(),any(),eq("assets:write"),eq("site-1"),isNull())).thenReturn(true);
        PlatformDeviceSyncService platform=mock(PlatformDeviceSyncService.class);when(platform.preview()).thenReturn(Arrays.asList(hat("SIMQA-H-1","0"),hat("SIMQA-H-2","1")));
        AdminPlatformService service=new AdminPlatformService(ledger,query,platform);
        assertEquals(2,service.sync("demo-system","site-1").getIntValue("added"));
        JSONObject d=AdminPlatformService.find(state.getJSONArray("devices"),"code","SIMQA-H-1");d.put("lifecycle","MAINTENANCE");d.put("areaId","area-1");
        JSONObject snapshot=seed("guardian-seed.json");assertTrue(PlatformProjection.apply(snapshot,state));assertFalse(PlatformProjection.apply(snapshot,state));
        JSONObject remote=AdminPlatformService.find(snapshot.getJSONArray("devices"),"id","SIMQA-H-1");assertFalse(remote.getBooleanValue("online"));assertNull(remote.get("battery"));assertFalse(remote.containsKey("position"));
        when(platform.preview()).thenReturn(Arrays.asList(hat("SIMQA-H-1","1"),hat("SIMQA-H-2","0")));
        assertEquals(0,service.sync("demo-system","site-1").getIntValue("added"));
        d=AdminPlatformService.find(state.getJSONArray("devices"),"code","SIMQA-H-1");assertEquals("MAINTENANCE",d.getString("lifecycle"));assertEquals("area-1",d.getString("areaId"));assertEquals("ONLINE",d.getString("communication"));
        PlatformProjection.apply(snapshot,state);assertTrue(AdminPlatformService.find(snapshot.getJSONArray("devices"),"id","SIMQA-H-1").getBooleanValue("online"));
        d.put("sourceTime","2020-01-01T00:00:00Z");PlatformProjection.apply(snapshot,state);
        remote=AdminPlatformService.find(snapshot.getJSONArray("devices"),"id","SIMQA-H-1");assertNull(remote.get("online"));assertEquals("STALE",remote.getString("freshness"));
    }
    @Test void permissionsAndUpstreamFailureNeverWrite()throws Exception {
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(seed("admin-seed.json"));
        AdminQueryService query=mock(AdminQueryService.class);PlatformDeviceSyncService platform=mock(PlatformDeviceSyncService.class);
        AdminPlatformService service=new AdminPlatformService(ledger,query,platform);
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.sync("demo-audit","site-1")).code);verifyNoInteractions(platform);
        when(query.allows(any(),any(),anyString(),anyString(),isNull())).thenReturn(true);when(platform.preview()).thenThrow(new RuntimeException("timeout"));
        assertThrows(RuntimeException.class,()->service.sync("demo-system","site-1"));verify(ledger,never()).write(any());
    }
    @Test void duplicateOrDifferentTypeCannotPartiallyImport()throws Exception {
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->seed("admin-seed.json"));
        AdminQueryService query=mock(AdminQueryService.class);when(query.allows(any(),any(),anyString(),anyString(),isNull())).thenReturn(true);
        PlatformDeviceSyncService platform=mock(PlatformDeviceSyncService.class);AdminPlatformService service=new AdminPlatformService(ledger,query,platform);
        when(platform.preview()).thenReturn(Arrays.asList(hat("SIMQA-H-1","0"),hat("SIMQA-H-1","1")));
        assertThrows(AdminQueryService.QueryFailed.class,()->service.sync("demo-system","site-1"));
        when(platform.preview()).thenReturn(Arrays.asList(hat("RL-B001","0")));
        assertThrows(AdminQueryService.QueryFailed.class,()->service.sync("demo-system","site-1"));verify(ledger,never()).write(any());verify(platform,never()).syncRecords(anyList(),any());
    }
    @Test void scheduledRefreshDoesNotAssignNewDevicesOrMoveOtherSite()throws Exception {
        JSONObject state=seed("admin-seed.json");AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->JSON.parseObject(state.toJSONString()));
        doAnswer(i->{JSONObject s=i.getArgument(0);state.clear();state.putAll(s);return null;}).when(ledger).write(any());
        AdminQueryService query=mock(AdminQueryService.class);when(query.allows(any(),any(),anyString(),anyString(),isNull())).thenReturn(true);
        PlatformDeviceSyncService platform=mock(PlatformDeviceSyncService.class);when(platform.preview()).thenReturn(Arrays.asList(hat("SIMQA-H-1","0")));
        AdminPlatformService service=new AdminPlatformService(ledger,query,platform);assertEquals(0,service.sync("demo-system","site-1",true).getIntValue("added"));
        service.sync("demo-system","site-1");assertEquals(1,service.sync("demo-system","site-2").getIntValue("skippedOtherSite"));
        when(platform.preview()).thenReturn(Collections.emptyList());service.sync("demo-system","site-1");
        assertEquals("UNKNOWN",AdminPlatformService.find(state.getJSONArray("devices"),"code","SIMQA-H-1").getString("freshness"));
    }
}
