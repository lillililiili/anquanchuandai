package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class ExternalDataStoreTest {
    JdbcTemplate jdbc(){return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));}
    GuardianAccess.Context actor(boolean admin){JSONObject data=object("sites",JSONArray.of(object("id","site-1","enabled",true)),"accounts",JSONArray.of(object("id",admin?"demo-system":"readonly","enabled",true)),"roles",new JSONArray());AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(data);return new GuardianAccess(ledger,mock(AdminQueryService.class)).context(object("id",admin?"demo-system":"readonly"));}
    @Test void removedConfigurationWritesDoNotReachStorage() throws Exception {
        JdbcTemplate db=jdbc();ExternalDataStore store=new ExternalDataStore(db);
        GuardianAccess access=mock(GuardianAccess.class);
        WearableBusinessPolicy policy=mock(WearableBusinessPolicy.class);
        MockMvc http=MockMvcBuilders.standaloneSetup(new WearableBusinessController(access,policy,store)).build();
        http.perform(post("/api/admin/v1/external/integrations").contentType(MediaType.APPLICATION_JSON)
                .content("{\"siteId\":\"site-1\",\"kind\":\"WORK_TICKET\",\"name\":\"retired\"}"))
                .andExpect(status().isMethodNotAllowed());
        http.perform(patch("/api/admin/v1/external/integrations/legacy-config").contentType(MediaType.APPLICATION_JSON)
                .content("{\"enabled\":true}"))
                .andExpect(status().isNotFound());
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM external_integration",Integer.class));
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM external_data_record",Integer.class));
        verifyNoInteractions(access,policy);
    }
    @Test void scopedResponsesAreIdempotentAndRedacted(){JdbcTemplate db=jdbc();ExternalDataStore store=new ExternalDataStore(db);JSONObject payload=object("title","相片","password","never-store","nested",object("token","secret","url","https://media.invalid/a?token=secret"));store.record("helmet-media","媒体","site-1","MEDIA","asset-1",payload,"asset-1");store.record("helmet-media","媒体","site-1","MEDIA","asset-1",object("title","已更新"),"asset-1");assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM external_data_record",Integer.class));assertEquals(1,store.records(actor(true),"site-1",null,1,20).getIntValue("total"));assertEquals(0,store.records(actor(false),"site-1",null,1,20).getIntValue("total"));assertFalse(db.queryForObject("SELECT body FROM external_data_record",String.class).contains("secret"));assertFalse(JSONObject.toJSONString(ExternalDataStore.redact(payload)).contains("secret"));}
    @Test void legacyConfigurationAndAdapterHistorySurviveRestartWithReadScopeIntact(){
        JdbcTemplate db=jdbc();ExternalDataStore first=new ExternalDataStore(db);
        JSONObject legacy=object("id","legacy-config","siteId","site-1","kind","WORK_TICKET","name","历史登记","version",2,"status","NOT_CONNECTED");
        db.update("INSERT INTO external_integration(id,site_id,kind,version,body) VALUES(?,?,?,?,?)","legacy-config","site-1","WORK_TICKET",2,legacy.toJSONString());
        first.record("helmet-platform","厂家设备平台","site-1","DEVICE","helmet-1",object("online",true),"local-helmet");
        ExternalDataStore restarted=new ExternalDataStore(db);
        assertEquals(2,restarted.integrations(actor(true),"site-1").size());
        assertTrue(restarted.integrations(actor(false),"site-1").isEmpty());
        assertEquals(legacy.toJSONString(),db.queryForObject("SELECT body FROM external_integration WHERE id='legacy-config'",String.class));
        JSONObject received=restarted.records(actor(true),"site-1",null,1,20).getJSONArray("items").getJSONObject(0);
        assertEquals("local-helmet",received.getString("localId"));
        assertEquals("RECEIVED",received.getString("status"));
        assertEquals(0,restarted.records(actor(true),"site-2",null,1,20).getIntValue("total"));
    }
}
