package com.ruoyi.melhat;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicInteger;
import com.sun.net.httpserver.HttpServer;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.calllab.WearCallLabBridgeService;
import org.junit.jupiter.api.*;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WearCallLabVideoTest {
    private static final String CALL = "45d640ce-a7bc-4dcd-991b-d4c0d11e4911";
    private HttpServer upstream;
    private WearCallLabBridgeService bridge;
    private SiteAccessService access;
    private LoginUser login;
    private MockHttpServletRequest request;
    private String owner = "12", state = "connected";
    private boolean enabled = true, redirect;
    private final AtomicInteger mediaHits = new AtomicInteger();
    private String range, token, site;

    @BeforeEach void setup() throws Exception {
        upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        upstream.createContext("/", exchange -> {
            boolean media = exchange.getRequestURI().getPath().endsWith("/video/stream");
            byte[] bytes;
            int code = 200;
            if (media) {
                mediaHits.incrementAndGet();
                range = exchange.getRequestHeaders().getFirst("Range");
                token = exchange.getRequestHeaders().getFirst("Authorization");
                site = exchange.getRequestHeaders().getFirst("X-Site-Id");
                bytes = new byte[]{1,2,3,4};
                code = redirect ? 302 : 206;
                exchange.getResponseHeaders().set("Content-Type", "video/mp4");
                exchange.getResponseHeaders().set("Content-Range", "bytes 2-5/12");
                exchange.getResponseHeaders().set("Accept-Ranges", "bytes");
                exchange.getResponseHeaders().set("Location", "http://untrusted.invalid/video");
            } else {
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                String json = "{\"code\":200,\"data\":{\"calls\":[{\"id\":\""+CALL+"\",\"userId\":\""+owner+
                        "\",\"state\":\""+state+"\",\"videoEnabled\":"+enabled+",\"participants\":[{\"deviceId\":\"7\",\"state\":\"connected\"}]}]}}";
                bytes = json.getBytes(StandardCharsets.UTF_8);
            }
            exchange.sendResponseHeaders(code, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        upstream.start();
        access = mock(SiteAccessService.class);
        SysUser user = new SysUser(); user.setUserId(12L);
        login = new LoginUser(user, Collections.emptySet());
        when(access.requireLogin()).thenReturn(login);
        when(access.roleKeys(login)).thenReturn(Collections.singleton(WearRoleKeys.DUTY));
        when(access.permissions()).thenReturn(Collections.singleton(WearRoleKeys.PERM_CALL_START));
        bridge = new WearCallLabBridgeService();
        ReflectionTestUtils.setField(bridge, "siteAccessService", access);
        ReflectionTestUtils.setField(bridge, "environment", new MockEnvironment());
        ReflectionTestUtils.setField(bridge, "enabled", true);
        ReflectionTestUtils.setField(bridge, "upstreamBaseUrl", "http://127.0.0.1:"+upstream.getAddress().getPort());
        request = new MockHttpServletRequest();
        request.addHeader("Authorization", "Bearer test");
        request.addHeader("X-Site-Id", "1");
        request.addHeader("Range", "bytes=2-5");
        request.setParameter("deviceId", "7");
    }
    @AfterEach void close() { upstream.stop(0); }
    private MockHttpServletResponse fetch() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        bridge.videoStream(request,response,CALL);
        return response;
    }
    @Test void authenticatedRangeIsStreamedWithoutRedirectOrSecretsInUrl() throws Exception {
        MockHttpServletResponse response = fetch();
        assertEquals(206,response.getStatus());
        assertEquals("bytes 2-5/12",response.getHeader("Content-Range"));
        assertArrayEquals(new byte[]{1,2,3,4},response.getContentAsByteArray());
        assertEquals("bytes=2-5",range); assertEquals("Bearer test",token); assertEquals("1",site);
        assertNull(response.getHeader("Location"));
        verify(access).assertAuthorized(1L);
    }
    @Test void ownershipAndConnectedCameraAreRequiredBeforeMedia() throws Exception {
        owner="19"; assertEquals(403,fetch().getStatus());
        owner="12"; state="ringing"; assertEquals(409,fetch().getStatus());
        state="connected"; enabled=false; assertEquals(409,fetch().getStatus());
        enabled=true; request.setParameter("deviceId","8"); assertEquals(403,fetch().getStatus());
        assertEquals(0,mediaHits.get());
    }
    @Test void arbitraryUrlsAndUnprivilegedUsersNeverReachMedia() throws Exception {
        request.setParameter("url","http://untrusted.invalid"); assertEquals(400,fetch().getStatus());
        request.removeParameter("url");
        when(access.roleKeys(login)).thenReturn(Collections.singleton(WearRoleKeys.READONLY));
        assertEquals(403,fetch().getStatus()); assertEquals(0,mediaHits.get());
    }
    @Test void upstreamRedirectIsNotFollowed() throws Exception {
        redirect=true; assertEquals(502,fetch().getStatus()); assertEquals(1,mediaHits.get());
    }
}
