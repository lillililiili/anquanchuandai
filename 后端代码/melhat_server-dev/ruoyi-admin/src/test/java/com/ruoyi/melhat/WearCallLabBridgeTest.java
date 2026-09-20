package com.ruoyi.melhat;

import java.io.ByteArrayOutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import com.sun.net.httpserver.HttpServer;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.calllab.WearCallLabBridgeService;
import com.ruoyi.wear.web.v1.WearCallLabBridgeController;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class WearCallLabBridgeTest
{
    private static final String CALL = "/calls/45d640ce-a7bc-4dcd-991b-d4c0d11e4911";
    private final AtomicInteger hits = new AtomicInteger();
    private HttpServer upstream;
    private WearCallLabBridgeService bridge;
    private SiteAccessService access;
    private MockHttpServletRequest request;
    private LoginUser login;
    private volatile String receivedPath, receivedToken, receivedSite, receivedBody, receivedCookie, receivedRedirectHeader;
    private volatile int upstreamStatus = 200;
    private volatile String upstreamBody = "{\"code\":200,\"data\":{\"simulation\":true}}";
    private volatile long delayMs;

    @BeforeEach
    void setup() throws Exception
    {
        upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        upstream.createContext("/", exchange -> {
            hits.incrementAndGet();
            receivedPath = exchange.getRequestURI().toString();
            receivedToken = exchange.getRequestHeaders().getFirst("Authorization");
            receivedSite = exchange.getRequestHeaders().getFirst("X-Site-Id");
            receivedCookie = exchange.getRequestHeaders().getFirst("Cookie");
            receivedRedirectHeader = exchange.getRequestHeaders().getFirst("X-Forwarded-Host");
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[1024];
            int n;
            while ((n = exchange.getRequestBody().read(buffer)) != -1) bytes.write(buffer, 0, n);
            receivedBody = new String(bytes.toByteArray(), StandardCharsets.UTF_8);
            try { if (delayMs > 0) Thread.sleep(delayMs); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            exchange.getResponseHeaders().set("Content-Type", "application/json;charset=UTF-8");
            exchange.getResponseHeaders().set("Location", "http://127.0.0.1:" + upstream.getAddress().getPort() + "/token-leak");
            exchange.getResponseHeaders().set("Set-Cookie", "upstream=untrusted");
            byte[] reply = upstreamBody.getBytes(StandardCharsets.UTF_8);
            try {
                exchange.sendResponseHeaders(upstreamStatus, reply.length);
                exchange.getResponseBody().write(reply);
            } finally { exchange.close(); }
        });
        upstream.start();
        access = mock(SiteAccessService.class);
        SysUser user = new SysUser();
        user.setUserId(12L);
        login = new LoginUser(user, Collections.emptySet());
        when(access.requireLogin()).thenReturn(login);
        when(access.roleKeys(login)).thenReturn(Collections.singleton(WearRoleKeys.DUTY));
        when(access.permissions()).thenReturn(new HashSet<String>(Arrays.asList(
                WearRoleKeys.PERM_CALL_LIST, WearRoleKeys.PERM_CALL_START, WearRoleKeys.PERM_COMMAND_TTS)));
        bridge = new WearCallLabBridgeService();
        ReflectionTestUtils.setField(bridge, "siteAccessService", access);
        ReflectionTestUtils.setField(bridge, "environment", new MockEnvironment().withProperty("spring.profiles.active", "dev"));
        ReflectionTestUtils.setField(bridge, "enabled", true);
        ReflectionTestUtils.setField(bridge, "upstreamBaseUrl", "http://127.0.0.1:" + upstream.getAddress().getPort());
        request = new MockHttpServletRequest();
        request.addHeader("Authorization", "Bearer unit-test-token");
        request.addHeader("X-Site-Id", "1");
    }

    @AfterEach
    void stop() { if (upstream != null) upstream.stop(0); }

    @Test
    void voiceVideoAndConsoleActionsUseBusinessIdentityAndFixedOrigin()
    {
        request.addHeader("Host", "attacker.invalid");
        request.addHeader("X-Forwarded-Host", "attacker.invalid");
        request.addHeader("Cookie", "unrelated-secret");
        ResponseEntity<byte[]> response = bridge.forward(request, "POST", CALL + "/video", Collections.singletonMap("enabled", true));
        assertEquals(200, response.getStatusCodeValue());
        assertEquals("/api/v1/lab" + CALL + "/video", receivedPath);
        assertEquals("Bearer unit-test-token", receivedToken);
        assertEquals("1", receivedSite);
        assertEquals("{\"enabled\":true}", receivedBody);
        assertNull(receivedCookie);
        assertNull(receivedRedirectHeader);
        assertNull(response.getHeaders().getFirst("Set-Cookie"));
        assertNull(response.getHeaders().getFirst("Location"));
        verify(access).assertAuthorized(1L);
    }

    @Test
    void preservesUpstreamFailureCodeAndBodyRatherThanReportingSuccess()
    {
        upstreamStatus = 409;
        upstreamBody = "{\"code\":409,\"msg\":\"设备已离线\"}";
        ResponseEntity<byte[]> result = bridge.forward(request, "POST", "/calls", Collections.singletonMap("deviceIds", Arrays.asList("12")));
        assertEquals(409, result.getStatusCodeValue());
        assertEquals(upstreamBody, new String(result.getBody(), StandardCharsets.UTF_8));
    }

    @Test
    void rejectsRedirectWithoutFollowingOrExposingLocation()
    {
        upstreamStatus = 302;
        ResponseEntity<byte[]> result = bridge.forward(request, "GET", "/state", null);
        assertEquals(502, result.getStatusCodeValue());
        assertEquals(1, hits.get());
        assertNull(result.getHeaders().getLocation());
        assertFalse(new String(result.getBody(), StandardCharsets.UTF_8).contains("unit-test-token"));
    }

    @Test
    void timeoutReportsUnknownExecutionAndDoesNotBecomeSuccess()
    {
        delayMs = 600;
        ReflectionTestUtils.setField(bridge, "readTimeoutMs", 100);
        ResponseEntity<byte[]> result = bridge.forward(request, "POST", "/calls", Collections.emptyMap());
        assertEquals(504, result.getStatusCodeValue());
        assertTrue(new String(result.getBody(), StandardCharsets.UTF_8).contains("执行状态未确认"));
    }

    @Test
    void deniesUnauthenticatedOrUnauthorizedSiteBeforeContactingAdapter()
    {
        when(access.requireLogin()).thenThrow(new ServiceException("未登录", 401));
        assertEquals(401, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        doReturn(login).when(access).requireLogin();
        doThrow(new ServiceException("无厂站权限", 403)).when(access).assertAuthorized(1L);
        assertEquals(403, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        assertEquals(0, hits.get());
    }

    @Test
    void enforcesCallTtsAndConsolePermissionsSeparately()
    {
        when(access.permissions()).thenReturn(Collections.singleton(WearRoleKeys.PERM_CALL_LIST));
        when(access.roleKeys(login)).thenReturn(Collections.singleton(WearRoleKeys.READONLY));
        assertEquals(403, bridge.forward(request, "POST", "/calls", Collections.emptyMap()).getStatusCodeValue());
        assertEquals(403, bridge.forward(request, "POST", "/tts", Collections.emptyMap()).getStatusCodeValue());
        assertEquals(403, bridge.forward(request, "POST", "/presence", Collections.emptyMap()).getStatusCodeValue());
        assertEquals(403, bridge.forward(request, "POST", CALL + "/accept", Collections.singletonMap("deviceId", "1")).getStatusCodeValue());
        assertEquals(403, bridge.forward(request, "POST", "/tts/ack", Collections.emptyMap()).getStatusCodeValue());
        request.setParameter("client", "console");
        assertEquals(403, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        assertEquals(0, hits.get());
        request.removeParameter("client");
        assertEquals(200, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
    }

    @Test
    void consoleStateWhitelistsOnlyConsoleQueryAndPreservesIt()
    {
        request.setParameter("client", "console");
        assertEquals(200, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        assertEquals("/api/v1/lab/state?client=console", receivedPath);
        request.setParameter("host", "http://attacker.invalid");
        assertEquals(400, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        assertEquals(1, hits.get());
    }

    @Test
    void onlyExplicitMethodsPathsAndUuidCallIdsCanReachAdapter()
    {
        for (String path : Arrays.asList("/reset-passwords", "/../me", "/calls/not-a-uuid/end", "/calls//end", "/calls/abc/credentials", "http://attacker.invalid", "/state?client=console"))
            assertEquals(404, bridge.forward(request, "POST", path, Collections.emptyMap()).getStatusCodeValue());
        assertEquals(404, bridge.forward(request, "DELETE", "/state", null).getStatusCodeValue());
        assertEquals(404, bridge.forward(request, "GET", "/calls", null).getStatusCodeValue());
        assertEquals(0, hits.get());
    }

    @Test
    void malformedOrMissingStationAndBearerAreRejected()
    {
        request.removeHeader("X-Site-Id");
        assertEquals(400, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        request.addHeader("X-Site-Id", "9223372036854775808");
        assertEquals(400, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        request.removeHeader("X-Site-Id"); request.addHeader("X-Site-Id", "1");
        request.removeHeader("Authorization");
        assertEquals(401, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        assertEquals(0, hits.get());
    }

    @Test
    void defaultDisabledAndProdNeverRegisterBridgeBeans()
    {
        for (boolean production : new boolean[]{false, true})
        {
            try (AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext())
            {
                if (production)
                {
                    context.getEnvironment().setActiveProfiles("prod");
                    context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test", Collections.<String, Object>singletonMap("melhat.call-lab.enabled", true)));
                }
                context.register(WearCallLabBridgeController.class, WearCallLabBridgeService.class);
                context.refresh();
                assertTrue(context.getBeansOfType(WearCallLabBridgeController.class).isEmpty());
                assertTrue(context.getBeansOfType(WearCallLabBridgeService.class).isEmpty());
            }
        }
        ReflectionTestUtils.setField(bridge, "enabled", false);
        assertEquals(404, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
    }

    @Test
    void bridgeInfoProvesJavaSignallingHopWithoutExposingUpstreamOrToken()
    {
        ResponseEntity<byte[]> response = bridge.info(request);
        String body = new String(response.getBody(), StandardCharsets.UTF_8);
        assertEquals(200, response.getStatusCodeValue());
        assertTrue(body.contains("java-business-backend"));
        assertTrue(body.contains("\"realMedia\":false"));
        assertFalse(body.contains("127.0.0.1"));
        assertFalse(body.contains("unit-test-token"));
        assertEquals(0, hits.get());
    }

    @Test
    void invalidConfiguredOriginAndOversizedBodyNeverSendRequests()
    {
        for (String uri : Arrays.asList("file:///tmp/x", "http://user:secret@localhost", "http://localhost/?target=x", "http://localhost/api/v1"))
        {
            ReflectionTestUtils.setField(bridge, "upstreamBaseUrl", uri);
            assertEquals(503, bridge.forward(request, "GET", "/state", null).getStatusCodeValue());
        }
        assertEquals(413, bridge.forward(request, "POST", "/tts", Collections.singletonMap("text", new String(new char[70000]).replace('\0', 'x'))).getStatusCodeValue());
        assertEquals(0, hits.get());
    }

    @Test
    void forwardsInviteOnlyForAnAuthorizedDutyCaller()
    {
        ResponseEntity<byte[]> result = bridge.forward(request, "POST", CALL + "/invite", Collections.singletonMap("deviceIds", Arrays.asList("42", "43")));
        assertEquals(200, result.getStatusCodeValue());
        assertEquals("/api/v1/lab" + CALL + "/invite", receivedPath);
        assertEquals("{\"deviceIds\":[\"42\",\"43\"]}", receivedBody);
        when(access.roleKeys(login)).thenReturn(Collections.emptySet());
        assertEquals(403, bridge.forward(request, "POST", CALL + "/invite", Collections.singletonMap("deviceIds", Arrays.asList("42"))).getStatusCodeValue());
        assertEquals(1, hits.get());
    }

    @Test
    void mvcRoutesExposeOnlyDeclaredBusinessEndpoints() throws Exception
    {
        WearCallLabBridgeController controller = new WearCallLabBridgeController();
        ReflectionTestUtils.setField(controller, "bridge", bridge);
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(get("/api/v1/lab/bridge-info").header("Authorization", "Bearer unit-test-token").header("X-Site-Id", "1"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.bridge").value("java-business-backend"));
        mvc.perform(post("/api/v1/lab" + CALL + "/video").header("Authorization", "Bearer unit-test-token").header("X-Site-Id", "1")
                .contentType("application/json").content("{\"enabled\":true}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/v1/lab/reset-passwords").contentType("application/json").content("{}"))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/v1/lab" + CALL + "/invite").header("Authorization", "Bearer unit-test-token").header("X-Site-Id", "1")
                .contentType("application/json").content("{\"deviceIds\":[\"42\"]}"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/v1/lab/calls/arbitrary/credentials"))
                .andExpect(status().isNotFound());
    }
}
