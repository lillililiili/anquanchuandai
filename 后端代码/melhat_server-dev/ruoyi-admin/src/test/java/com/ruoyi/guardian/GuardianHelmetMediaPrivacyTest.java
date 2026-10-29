package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianHelmetMediaPrivacyTest {
    @Test void historicalAssetsAndCommandsUseCapturedScopeAndUnknownOwnerRequiresGlobalAdmin() throws Exception {
        JSONObject master=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(),StandardCharsets.UTF_8));migrate(master);
        JSONObject duty=find(master,"accounts","demo-duty"),admin=find(master,"accounts","demo-system");
        duty.put("roleScopes",object("duty",object("siteIds",JSONArray.parseArray("[\"site-1\"]"),"areaIds",JSONArray.parseArray("[\"area-boiler\"]"))));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(master);
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        JSONArray items=new JSONArray();
        items.add(object("id","allowed","siteId","site-1","areaId","area-boiler"));
        items.add(object("id","old-site","siteId","site-2","areaId","area-boiler"));
        items.add(object("id","unknown"));
        JSONArray limited=GuardianHelmetMediaController.historical(access.context(duty),items);
        assertEquals(1,limited.size());assertEquals("allowed",limited.getJSONObject(0).getString("id"));
        JSONArray full=GuardianHelmetMediaController.historical(access.context(admin),items);
        assertEquals(3,full.size());assertTrue(full.getJSONObject(2).getBooleanValue("unassigned"));
        assertFalse(items.getJSONObject(2).containsKey("unassigned"));
    }
    @Test void credentialsAndSignedMediaResponsesAreNotCacheable(){
        MockHttpServletResponse response=new MockHttpServletResponse();
        new GuardianHelmetMediaController(null,null).privateResponses(response);
        assertEquals("no-store, private",response.getHeader("Cache-Control"));assertEquals("no-cache",response.getHeader("Pragma"));
    }
}
