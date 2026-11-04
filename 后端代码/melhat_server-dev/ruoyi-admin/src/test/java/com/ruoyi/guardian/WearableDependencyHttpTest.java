package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.framework.web.exception.GlobalExceptionHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.jdbc.CannotGetJdbcConnectionException;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.CannotCreateTransactionException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.handler.MappedInterceptor;

import java.util.List;

import static com.ruoyi.guardian.WearableModel.object;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class WearableDependencyHttpTest {
    private static final String TOKEN = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    private final RedisCache redis = mock(RedisCache.class);
    private final AdminLedgerStore ledger = mock(AdminLedgerStore.class);
    private final GuardianEvents events = mock(GuardianEvents.class);
    private final WearableMaintenance maintenance = mock(WearableMaintenance.class);
    private MockMvc http;

    @RestController static class LegacyProbe {
        @GetMapping("/legacy/probe") void fail() { throw new QueryTimeoutException("legacy failure"); }
    }

    @BeforeEach void setup() {
        WearableSessions sessions = new WearableSessions(redis, ledger);
        WearableWebSecurity security = new WearableWebSecurity(sessions);
        ReflectionTestUtils.setField(security, "maintenance", maintenance);
        InterceptorRegistry registry = new InterceptorRegistry();
        security.addInterceptors(registry);
        List<?> interceptors = ReflectionTestUtils.invokeMethod(registry, "getInterceptors");
        http = MockMvcBuilders.standaloneSetup(new GuardianController(sessions, null, null, events, null, null),
                new WearableMaintenanceController(maintenance),
                new AdminLedgerController(ledger, null, null, null, null, null, null), new LegacyProbe())
                .setControllerAdvice(new GlobalExceptionHandler(), new GuardianError(), new WearableDependencyError())
                .addMappedInterceptors(new String[]{"/api/admin/**", "/api/guardian/**"},
                        ((MappedInterceptor) interceptors.get(0)).getInterceptor()).build();
    }

    @Test void redisFailureInSessionInterceptorIs503BeforeUpload() throws Exception {
        when(redis.getCacheObject(anyString())).thenThrow(new RedisConnectionFailureException("redis credential detail"));
        http.perform(put("/api/guardian/v1/files/upload-1").header(WearableSessions.HEADER, TOKEN)
                .contentType("image/png").content(new byte[]{1, 2}))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value(503))
                .andExpect(jsonPath("$.errorCode").value("SERVICE_UNAVAILABLE"))
                .andExpect(jsonPath("$.message").value("服务暂不可用，请稍后重试"));
        verifyNoInteractions(events, maintenance, ledger);
    }

    @Test void databaseFailureInAdminSessionInterceptorIs503() throws Exception {
        when(redis.getCacheObject(anyString())).thenReturn("{\"accountId\":\"demo-admin\",\"audience\":\"admin\"}");
        when(ledger.read()).thenThrow(new CannotCreateTransactionException("private database",
                new CannotGetJdbcConnectionException("private connection")));
        http.perform(get("/api/admin/v1/state").header(WearableSessions.HEADER, TOKEN))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value(503))
                .andExpect(jsonPath("$.message").value("服务暂不可用，请稍后重试"));
    }

    @Test void uploadSuccessKeepsAcknowledgmentAndControllerDbFailureReturns503() throws Exception {
        authenticate("guardian");
        http.perform(put("/api/guardian/v1/files/upload-1").header(WearableSessions.HEADER, TOKEN)
                .contentType("image/png").content(new byte[]{1}))
                .andExpect(status().isOk()).andExpect(jsonPath("$.ok").value(true)).andExpect(jsonPath("$.id").value("upload-1"));
        when(events.snapshot(any(JSONObject.class))).thenThrow(new QueryTimeoutException("private SQL"));
        http.perform(get("/api/guardian/v1/snapshot").header(WearableSessions.HEADER, TOKEN))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value(503));
    }

    @Test void maintenanceAndLegacyKeepTheirExistingSuccessAndDomainContracts() throws Exception {
        authenticate("admin");
        when(maintenance.status()).thenReturn(object("paused", false, "quiescent", false));
        http.perform(get("/api/admin/v1/maintenance").header(WearableSessions.HEADER, TOKEN))
                .andExpect(status().isOk()).andExpect(jsonPath("$.paused").value(false));
        http.perform(post("/api/admin/v1/maintenance").header(WearableSessions.HEADER, TOKEN)
                .contentType("application/json").content("{\"mode\":\"INVALID\"}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.errorCode").value("INVALID_MAINTENANCE_MODE"));
        http.perform(get("/api/guardian/v1/snapshot")).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.errorCode").value("SESSION_EXPIRED"));
        http.perform(get("/legacy/probe")).andExpect(status().isOk()).andExpect(jsonPath("$.code").value(500));
    }

    private void authenticate(String audience) {
        when(redis.getCacheObject(anyString())).thenReturn(object("accountId", "demo-system",
                "audience", audience, "credentialVersion", 1).toJSONString());
        when(ledger.read()).thenReturn(object("accounts", java.util.Collections.singletonList(
                object("id", "demo-system", "enabled", true, "credentialVersion", 1))));
    }
}
