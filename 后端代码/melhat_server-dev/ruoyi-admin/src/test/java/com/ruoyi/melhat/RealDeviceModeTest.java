package com.ruoyi.melhat;

import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.headband.client.OkHttpService;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.service.DemoCompatibilityService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import com.ruoyi.melhat.controller.DemoCompatibilityController;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RealDeviceModeTest {
    @Test
    void readRetriesOnceAfterUnauthorizedAndRefreshesCache() throws Exception {
        RedisCache cache = mock(RedisCache.class);
        OkHttpService http = mock(OkHttpService.class);
        when(cache.getCacheObject(anyString())).thenReturn("Bearer stale", "Bearer fresh");
        when(http.doGet(eq("http://example.invalid/devices"), anyMap(), anyMap()))
                .thenThrow(new ServiceException("HTTP 401", 401))
                .thenReturn("{\"code\":200,\"data\":[]}");
        HeadbandService service = service(cache, http, "test-secret");
        ReflectionTestUtils.setField(service, "headbandDeviceApi", "/devices");
        assertTrue(service.getHeadBandList(new java.util.HashMap<>()).isEmpty());
        verify(cache, times(1)).deleteObject(anyString());
        verify(http, times(2)).doGet(anyString(), anyMap(), anyMap());
    }

    @Test
    void readStopsAfterSecondUnauthorized() throws Exception {
        RedisCache cache = mock(RedisCache.class);
        OkHttpService http = mock(OkHttpService.class);
        when(cache.getCacheObject(anyString())).thenReturn("Bearer invalid");
        when(http.doGet(anyString(), anyMap(), anyMap())).thenThrow(new ServiceException("HTTP 401", 401));
        HeadbandService service = service(cache, http, "test-secret");
        ReflectionTestUtils.setField(service, "headbandDeviceApi", "/devices");
        assertThrows(ServiceException.class, () -> service.getHeadBandList(new java.util.HashMap<>()));
        verify(cache, times(1)).deleteObject(anyString());
        verify(http, times(2)).doGet(anyString(), anyMap(), anyMap());
    }
    private final ApplicationContextRunner context = new ApplicationContextRunner()
            .withBean(DemoCompatibilityService.class, () -> mock(DemoCompatibilityService.class))
            .withBean(ISafetyHatInfoService.class, () -> mock(ISafetyHatInfoService.class))
            .withBean(ISafetyHatLocationRecordService.class, () -> mock(ISafetyHatLocationRecordService.class))
            .withUserConfiguration(DemoCompatibilityController.class);

    @Test
    void mockEndpointsAreOptInOnly() {
        context.run(c -> assertThat(c).doesNotHaveBean(DemoCompatibilityController.class));
        context.withPropertyValues("melhat.demo-mode=false")
                .run(c -> assertThat(c).doesNotHaveBean(DemoCompatibilityController.class));
        context.withPropertyValues("melhat.demo-mode=true")
                .run(c -> assertThat(c).hasSingleBean(DemoCompatibilityController.class));
    }

    @Test
    void missingCredentialsFailBeforeCacheAndNetwork() {
        RedisCache cache = mock(RedisCache.class);
        OkHttpService http = mock(OkHttpService.class);
        HeadbandService service = service(cache, http, "");
        assertThat(assertThrows(ServiceException.class, service::getToken).getMessage())
                .contains("TOKEN_SERVICE_PASSWORD");
        verifyNoInteractions(cache, http);
    }

    @Test
    void rejectsAuthenticationErrorWithoutCaching() throws Exception {
        RedisCache cache = mock(RedisCache.class);
        OkHttpService http = mock(OkHttpService.class);
        when(http.doGet(anyString(), isNull(), isNull()))
                .thenReturn("{\"code\":401,\"msg\":\"Token required\",\"data\":[]}");
        assertThrows(ServiceException.class, () -> service(cache, http, "test-secret").getToken());
        verify(cache, never()).setCacheObject(anyString(), any(), anyInt(), any(TimeUnit.class));
    }

    @Test
    void encodesCredentialsAndCachesOnlyValidatedToken() throws Exception {
        RedisCache cache = mock(RedisCache.class);
        OkHttpService http = mock(OkHttpService.class);
        when(http.doGet(anyString(), isNull(), isNull())).thenReturn(
                "{\"code\":200,\"data\":{\"accessToken\":\"test-token\",\"tokenType\":\"Bearer\",\"expireTime\":120}}");
        assertThat(service(cache, http, "a&b").getToken()).isEqualTo("Bearer test-token");
        verify(http).doGet(contains("client_secret=a%26b"), isNull(), isNull());
        verify(cache).setCacheObject(anyString(), eq("Bearer test-token"), eq(1), eq(TimeUnit.SECONDS));
    }

    private HeadbandService service(RedisCache cache, OkHttpService http, String password) {
        HeadbandService service = new HeadbandService();
        ReflectionTestUtils.setField(service, "redisCache", cache);
        ReflectionTestUtils.setField(service, "okHttpService", http);
        ReflectionTestUtils.setField(service, "server", "http://example.invalid");
        ReflectionTestUtils.setField(service, "tokenurl", "/api/auth/token");
        ReflectionTestUtils.setField(service, "username", "test-client");
        ReflectionTestUtils.setField(service, "password", password);
        return service;
    }
}
