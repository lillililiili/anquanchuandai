package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.handler.MappedInterceptor;
import java.util.*;
import java.util.concurrent.*;
import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class WearableMaintenanceTest {
    JdbcTemplate jdbc(){JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));new WearableBusinessStore(jdbc);return jdbc;}
    JSONObject admin(){return object("id","demo-system");}
    @Test void modePersistsWithoutSeedingBusinessAndReportsContinueWhilePaused(){
        JdbcTemplate db=jdbc();WearableMaintenance gate=new WearableMaintenance(db);
        assertFalse(gate.paused());assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM wearable_business_meta",Integer.class));
        gate.setPaused(true,admin());new WearableBusinessStore(db).appendDeviceReport("paused-receipt","direct-belt","866652023095053",object("raw",object()));
        WearableMaintenance restarted=new WearableMaintenance(db);assertTrue(restarted.paused());
        JSONObject status=restarted.status();assertEquals("PAUSED",status.getString("mode"));assertEquals(1,status.getIntValue("pendingReports"));assertEquals(1,status.getLongValue("lastSequence"));assertTrue(status.getBooleanValue("quiescent"));
        assertEquals("MAINTENANCE_PAUSED",assertThrows(AdminQueryService.QueryFailed.class,restarted::beginWrite).errorCode);
        restarted.setPaused(false,admin());assertTrue(restarted.tryBeginWrite());restarted.endWrite();assertEquals(0,restarted.status().getIntValue("activeWrites"));
    }
    @Test void onlySystemMaySwitchAndPauseWaitsForPreviouslyAdmittedWrites() throws Exception {
        WearableMaintenance gate=new WearableMaintenance(jdbc());
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->gate.setPaused(true,object("id","demo-duty"))).code);assertFalse(gate.paused());
        gate.beginWrite();ExecutorService executor=Executors.newSingleThreadExecutor();
        try {
            Future<JSONObject> pause=executor.submit(()->gate.setPaused(true,admin()));
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(3);
            while(!gate.paused()&&System.nanoTime()<deadline)Thread.sleep(5);
            assertTrue(gate.paused());assertFalse(pause.isDone());assertFalse(gate.tryBeginWrite());
            assertFalse(gate.status().getBooleanValue("quiescent"));gate.endWrite();
            assertTrue(pause.get(3,TimeUnit.SECONDS).getBooleanValue("quiescent"));
        } finally {gate.endWrite();executor.shutdownNow();}
    }
    @RestController static class Probe {
        int writes;
        @PostMapping("/api/guardian/v1/business/probe") JSONObject write(){writes++;return object("ok",true);}
        @GetMapping("/api/guardian/v1/business/probe") JSONObject read(){return object("writes",writes);}
        @PostMapping("/api/admin/v1/query") JSONObject query(){return object("data",object());}
        @PostMapping("/api/admin/v1/logout") JSONObject logout(){return object("ok",true);}
    }
    @Test void httpRejectsPausedWritesAllowsReadsAndChecksMaintenanceAuthorization() throws Exception {
        WearableMaintenance gate=new WearableMaintenance(jdbc());WearableSessions sessions=mock(WearableSessions.class);
        when(sessions.require(any(),anyString())).thenReturn(admin());
        WearableWebSecurity security=new WearableWebSecurity(sessions);ReflectionTestUtils.setField(security,"maintenance",gate);
        InterceptorRegistry registry=new InterceptorRegistry();security.addInterceptors(registry);
        List<?> interceptors=ReflectionTestUtils.invokeMethod(registry,"getInterceptors");
        HandlerInterceptor interceptor=((MappedInterceptor)interceptors.get(0)).getInterceptor();
        Probe probe=new Probe();MockMvc http=MockMvcBuilders.standaloneSetup(new WearableMaintenanceController(gate),probe).setControllerAdvice(new GuardianError()).addInterceptors(interceptor).build();
        http.perform(post("/api/guardian/v1/business/probe")).andExpect(status().isOk());assertEquals(1,probe.writes);assertEquals(0,gate.status().getIntValue("activeWrites"));
        http.perform(post("/api/admin/v1/maintenance").contentType("application/json").content("{\"mode\":\"PAUSED\"}")).andExpect(status().isOk());
        String rejected=http.perform(post("/api/guardian/v1/business/probe")).andExpect(status().isServiceUnavailable()).andReturn().getResponse().getContentAsString();
        assertEquals("MAINTENANCE_PAUSED",JSONObject.parseObject(rejected).getString("errorCode"));assertEquals(1,probe.writes);
        http.perform(get("/api/guardian/v1/business/probe")).andExpect(status().isOk());
        http.perform(post("/api/admin/v1/query")).andExpect(status().isOk());http.perform(post("/api/admin/v1/logout")).andExpect(status().isOk());
        http.perform(post("/api/admin/v1/maintenance").contentType("application/json").content("{\"mode\":\"INVALID\"}")).andExpect(status().isBadRequest());
        when(sessions.require(any(),anyString())).thenReturn(object("id","demo-duty"));
        http.perform(get("/api/admin/v1/maintenance")).andExpect(status().isForbidden());
        http.perform(post("/api/admin/v1/maintenance").contentType("application/json").content("{\"mode\":\"ACTIVE\"}")).andExpect(status().isForbidden());assertTrue(gate.paused());
        when(sessions.require(any(),anyString())).thenReturn(admin());
        http.perform(post("/api/admin/v1/maintenance").contentType("application/json").content("{\"mode\":\"ACTIVE\"}")).andExpect(status().isOk());
        http.perform(post("/api/guardian/v1/business/probe")).andExpect(status().isOk());assertEquals(2,probe.writes);
    }
}
