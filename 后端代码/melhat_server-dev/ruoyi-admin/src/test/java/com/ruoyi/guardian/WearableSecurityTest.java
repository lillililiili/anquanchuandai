package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.core.redis.RedisCache;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class WearableSecurityTest {
    @Test void opaqueSessionsRejectForgeryAudienceRevocationAndDisabledAccount() {
        RedisCache redis = mock(RedisCache.class);
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        JSONObject state = JSONObject.parseObject("{\"accounts\":[{\"id\":\"demo-system\",\"enabled\":true,\"credentialVersion\":1}]}");
        when(ledger.read()).thenReturn(state);
        Map<String,String> cache = new HashMap<>();
        doAnswer(i -> { cache.put(i.getArgument(0),i.getArgument(1));return null; }).when(redis).setCacheObject(anyString(),anyString(),eq(8),eq(TimeUnit.HOURS));
        when(redis.getCacheObject(anyString())).thenAnswer(i -> cache.get(i.getArgument(0)));
        when(redis.deleteObject(anyString())).thenAnswer(i -> cache.remove(i.getArgument(0)) != null);
        WearableSessions sessions = new WearableSessions(redis,ledger);
        JSONObject actor = state.getJSONArray("accounts").getJSONObject(0);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(WearableSessions.HEADER,"demo-system");
        assertEquals(401,assertThrows(AdminQueryService.QueryFailed.class,()->sessions.require(request,"admin")).code);
        String token=sessions.issue(actor,"admin");request.removeHeader(WearableSessions.HEADER);request.addHeader(WearableSessions.HEADER,token);
        assertEquals("demo-system",sessions.require(request,"admin").getString("id"));
        assertThrows(AdminQueryService.QueryFailed.class,()->sessions.require(request,"guardian"));
        actor.put("credentialVersion",2);assertThrows(AdminQueryService.QueryFailed.class,()->sessions.require(request,"admin"));
        actor.put("credentialVersion",1);actor.put("enabled",false);assertThrows(AdminQueryService.QueryFailed.class,()->sessions.require(request,"admin"));
        actor.put("enabled",true);sessions.revoke(request);assertThrows(AdminQueryService.QueryFailed.class,()->sessions.require(request,"admin"));
    }

    @Test void readonlyDeviceWriteIsRejectedBeforeIdempotencyReplay() {
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);
        JSONObject state = JSONObject.parseObject("{\"accounts\":[{\"id\":\"demo-audit\",\"enabled\":true}],\"devices\":[],\"idempotency\":{}}");
        when(ledger.read()).thenReturn(state);
        AdminDeviceService service=new AdminDeviceService(ledger,mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(service,"queries",mock(AdminQueryService.class));
        JSONObject input=JSONObject.parseObject("{\"siteId\":\"site-1\",\"operationId\":\"SIMQA\",\"data\":{\"code\":\"SIMQA\",\"type\":\"BELT\"}}");
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute("demo-audit","devices.create",input)).code);
        verify(ledger,never()).write(any());
    }

    @Test void deviceCreationIgnoresRetiredAreasAndRejectsAnotherSite() {
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);
        JSONObject state=new JSONObject();
        JSONObject actor=new JSONObject();actor.put("id","area-editor");actor.put("enabled",true);
        com.alibaba.fastjson2.JSONArray accounts=new com.alibaba.fastjson2.JSONArray();accounts.add(actor);state.put("accounts",accounts);
        state.put("devices",new com.alibaba.fastjson2.JSONArray());
        JSONObject area=new JSONObject();area.put("id","area-1");area.put("siteId","site-1");area.put("enabled",true);
        com.alibaba.fastjson2.JSONArray areas=new com.alibaba.fastjson2.JSONArray();areas.add(area);state.put("areas",areas);
        when(ledger.read()).thenReturn(state);
        AdminQueryService queries=mock(AdminQueryService.class);
        when(queries.allows(state,actor,"assets:write","site-1",null)).thenReturn(true);
        AdminDeviceService service=new AdminDeviceService(ledger,mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(service,"queries",queries);
        JSONObject data=new JSONObject();data.put("code","SIMQA-AREA");data.put("name","模拟测试");data.put("type","BELT");data.put("areaId","area-1");
        JSONObject input=new JSONObject();input.put("siteId","site-1");input.put("operationId","create-1");input.put("data",data);
        JSONObject created=service.execute("area-editor","devices.create",input).getJSONObject("data");
        assertNull(created.getString("areaId"));
        input.put("id",created.getString("id"));input.put("expectedVersion",1);input.put("operationId","move-1");data.put("areaId","area-2");
        data.remove("type");
        assertNull(service.execute("area-editor","devices.update",input).getJSONObject("data").getString("areaId"));
        input.remove("id");input.put("siteId","site-2");input.put("operationId","foreign-1");data.put("type","BELT");
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute("area-editor","devices.create",input)).code);
        assertNull(state.getJSONArray("devices").getJSONObject(0).getString("areaId"));
    }

    @Test void sourceWorkAndInventoryCannotBeReplacedByPortalClient() throws Exception {
        GuardianStore store=spy(new GuardianStore(mock(GuardianHatArchive.class)));
        JSONObject current=JSONObject.parseObject("{\"stations\":[{\"name\":\"测试\"}],\"works\":[{\"id\":\"W1\",\"members\":[\"P1\"]}],\"devices\":[{\"id\":\"real-helmet\",\"online\":false}],\"seq\":9}");
        ReflectionTestUtils.setField(store,"state",current);
        JSONObject changed=JSONObject.parseObject(current.toJSONString());changed.getJSONArray("works").getJSONObject(0).put("members",new com.alibaba.fastjson2.JSONArray());changed.put("seq",10);
        changed.getJSONArray("devices").getJSONObject(0).put("online",true);changed.put("events",new com.alibaba.fastjson2.JSONArray());
        GuardianController controller=new GuardianController(null,null,store,null,mock(GuardianAccess.class),null);
        org.springframework.test.web.servlet.MockMvc http=org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(new GuardianError()).build();
        for(int revision:new int[]{9,8}) {
            String body=http.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/guardian/v1/snapshot")
                    .header("X-Wearable-Revision",revision).contentType("application/json").content(changed.toJSONString()))
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isGone()).andReturn().getResponse().getContentAsString();
            assertEquals("SNAPSHOT_WRITE_REMOVED",JSONObject.parseObject(body).getString("errorCode"));
        }
        assertEquals(1,current.getJSONArray("works").getJSONObject(0).getJSONArray("members").size());
        assertFalse(current.getJSONArray("devices").getJSONObject(0).getBooleanValue("online"));assertEquals(9,current.getIntValue("seq"));assertFalse(current.containsKey("events"));
        verify(store,never()).replaceFromClient(any(),anyInt());
    }
}
