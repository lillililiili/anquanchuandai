package com.ruoyi.melhat;

import java.util.Base64;
import java.util.concurrent.TimeUnit;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.event.EventCommandService;
import com.ruoyi.wear.event.EventMapService;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestTemplate;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class EventMapTest
{
    private final EventCommandService events = mock(EventCommandService.class);
    private final RedisCache cache = mock(RedisCache.class);
    private final RestTemplate http = mock(RestTemplate.class);
    private final EventMapService maps = new EventMapService(events, cache, http);

    @Test void cachedTilesStillRequireEventSiteAccess()
    {
        when(cache.getCacheObject(anyString())).thenReturn("cached");
        doThrow(new ServiceException("没有权限", 403)).when(events).requireReadable(9L);
        assertThrows(ServiceException.class, () -> maps.tile(9L, 16, 1, 1));
        verifyNoInteractions(cache, http);
    }

    @Test void invalidTileRangeNeverReachesNetwork()
    {
        assertThrows(ServiceException.class, () -> maps.tile(1L, 30, 0, 0));
        assertThrows(ServiceException.class, () -> maps.tile(1L, 16, -1, 0));
        assertThrows(ServiceException.class, () -> maps.tile(1L, 16, 0, 65536));
        verifyNoInteractions(cache, http);
    }

    @Test void reusesCacheWithoutUpstreamRequest()
    {
        when(cache.getCacheObject("wear:map:osm:16/1/2")).thenReturn("cached");
        assertEquals("cached", maps.tile(1L, 16, 1, 2));
        verify(events).requireReadable(1L);
        verifyNoInteractions(http);
    }

    @Test void fetchesOnlyFixedTileUrlAndCachesSevenDaysWithoutCredentials()
    {
        byte[] png = {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10};
        when(http.exchange(eq("https://tile.openstreetmap.org/16/1/2.png"), eq(HttpMethod.GET),
                any(HttpEntity.class), eq(byte[].class))).thenAnswer(call -> {
                    HttpEntity<?> request = call.getArgument(2);
                    assertTrue(request.getHeaders().getFirst("User-Agent").startsWith("RollingWearablePlatform/"));
                    assertNull(request.getHeaders().getFirst("Authorization"));
                    assertNull(request.getHeaders().getFirst("X-Site-Id"));
                    return ResponseEntity.ok(png);
                });
        String encoded = Base64.getEncoder().encodeToString(png);
        assertEquals(encoded, maps.tile(1L, 16, 1, 2));
        verify(cache).setCacheObject("wear:map:osm:16/1/2", encoded, 7, TimeUnit.DAYS);
    }

    @Test void upstreamFailureIsExplicitAndNotCached()
    {
        when(http.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(byte[].class)))
                .thenReturn(ResponseEntity.ok("not a tile".getBytes()));
        assertThrows(ServiceException.class, () -> maps.tile(1L, 16, 1, 2));
        verify(cache, never()).setCacheObject(anyString(), anyString(), anyInt(), any(TimeUnit.class));
    }
}
