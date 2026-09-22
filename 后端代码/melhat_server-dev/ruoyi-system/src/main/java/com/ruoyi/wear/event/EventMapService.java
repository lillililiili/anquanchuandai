package com.ruoyi.wear.event;

import java.util.Base64;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;

/** Event-authorized tile access. Only fixed OSM tile URLs are accepted, never
 * client-supplied URLs. No credentials or event/person data go upstream. */
@Service
public class EventMapService
{
    private final EventCommandService events;
    private final RedisCache cache;
    private final RestTemplate http;
    @Autowired private com.ruoyi.wear.auth.SiteAccessService siteAccess;

    @Autowired
    public EventMapService(EventCommandService events, RedisCache cache)
    {
        this(events, cache, client());
    }

    public EventMapService(EventCommandService events, RedisCache cache, RestTemplate http)
    {
        this.events = events;
        this.cache = cache;
        this.http = http;
    }

    private static RestTemplate client()
    {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(4000);
        factory.setReadTimeout(6000);
        return new RestTemplate(factory);
    }

    public String tile(Long eventId, int z, int x, int y)
    {
        // This check must precede every cache read, including cross-site hits.
        events.requireReadable(eventId);
        return loadTile(z, x, y);
    }

    public String siteTile(int z, int x, int y)
    {
        siteAccess.requireCurrentSiteForWrite();
        return loadTile(z, x, y);
    }

    private String loadTile(int z, int x, int y)
    {
        if (z < 3 || z > 19 || x < 0 || y < 0 || x >= (1 << z) || y >= (1 << z))
        {
            throw new ServiceException("地图范围无效", 400);
        }
        String tile = z + "/" + x + "/" + y;
        String key = "wear:map:osm:" + tile;
        String cached = cache.getCacheObject(key);
        if (cached != null) return cached;
        try
        {
            HttpHeaders headers = new HttpHeaders();
            headers.set(HttpHeaders.USER_AGENT, "RollingWearablePlatform/1.3 (event-location)");
            ResponseEntity<byte[]> response = http.exchange(
                    "https://tile.openstreetmap.org/" + tile + ".png",
                    HttpMethod.GET, new HttpEntity<Void>(headers), byte[].class);
            byte[] bytes = response.getBody();
            if (!response.getStatusCode().is2xxSuccessful() || bytes == null || bytes.length < 8
                    || bytes.length > 1024 * 1024 || bytes[0] != (byte) 0x89
                    || bytes[1] != 'P' || bytes[2] != 'N' || bytes[3] != 'G')
            {
                throw new IllegalStateException("Invalid tile response");
            }
            String encoded = Base64.getEncoder().encodeToString(bytes);
            // OSM minimum cache lifetime; stored in persistent Redis across restarts.
            cache.setCacheObject(key, encoded, 7, TimeUnit.DAYS);
            return encoded;
        }
        catch (Exception ex)
        {
            throw new ServiceException("地图底图暂时不可用，请稍后重试", 503);
        }
    }
}
