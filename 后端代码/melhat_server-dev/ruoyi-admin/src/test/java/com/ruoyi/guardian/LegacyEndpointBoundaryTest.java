package com.ruoyi.guardian;

import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.framework.config.SecurityConfig;
import com.ruoyi.framework.config.properties.PermitAllUrlProperties;
import com.ruoyi.framework.security.filter.JwtAuthenticationTokenFilter;
import com.ruoyi.framework.security.filter.LegacyEndpointBoundaryFilter;
import com.ruoyi.framework.security.handle.AuthenticationEntryPointImpl;
import com.ruoyi.framework.security.handle.LogoutSuccessHandlerImpl;
import com.ruoyi.framework.web.service.TokenService;
import com.ruoyi.system.websocket.WebSocketSever;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.*;
import org.springframework.core.env.MapPropertySource;
import org.springframework.mock.web.MockServletContext;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import javax.servlet.Filter;
import javax.servlet.http.HttpServletRequest;
import javax.websocket.CloseReason;
import javax.websocket.Session;
import java.io.IOException;
import java.net.URI;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class LegacyEndpointBoundaryTest {
    private static final String KEY = "test-only-callback-service-key-000000000";
    private AnnotationConfigWebApplicationContext context(boolean enabled) {
        AnnotationConfigWebApplicationContext ctx = new AnnotationConfigWebApplicationContext();
        ctx.setServletContext(new MockServletContext());
        Map<String,Object> properties = new HashMap<>();
        properties.put("melhat.legacy-callback.enabled", enabled);
        properties.put("melhat.legacy-callback.key", KEY);
        ctx.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test", properties));
        // Register the legacy dependencies as ready singletons: Spring must not inject
        // production @Value/Redis fields into Mockito's TokenService subclass.
        ctx.addBeanFactoryPostProcessor(factory -> {
            factory.registerSingleton("tokenService", App.tokenService());
            factory.registerSingleton("logoutSuccessHandler", mock(LogoutSuccessHandlerImpl.class));
            PermitAllUrlProperties propertiesBean = mock(PermitAllUrlProperties.class);
            when(propertiesBean.getUrls()).thenReturn(Collections.singletonList("/hat/**"));
            factory.registerSingleton("permitAllUrlProperties", propertiesBean);
        });
        ctx.register(App.class); ctx.refresh(); return ctx;
    }
    private MockMvc mvc(AnnotationConfigWebApplicationContext ctx) {
        return MockMvcBuilders.webAppContextSetup(ctx).addFilters(ctx.getBean("springSecurityFilterChain", Filter.class)).build();
    }
    @Test void retiredHumanRoutesRejectEvenLegacyAdministratorAndAnnotationPermitAll() throws Exception {
        try (AnnotationConfigWebApplicationContext ctx = context(false)) {
            MockMvc http = mvc(ctx);
            for (String path : Arrays.asList("/hat/safety/info/list", "/hat/safety/info/list/", "/ws/1/1", "/test/user/list",
                    "/test2/test", "/system/user/list", "/monitor/job/list", "/common/download", "/profile/upload/file.png",
                    "/aip/head/band/list", "/tool/gen/list", "/druid/sql.json", "/login", "/logout", "/api/melhat/unreviewed",
                    "/hat/data/statistics", "/hat/electronic/fence/list", "/hat/fence/alarm/list", "/hat/file/record/list",
                    "/hat/group/info/list", "/hat/intercom/record/createSingleCall", "/hat/tts/broadcast/createSingleBroadcast",
                    "/hat/safety/info/platform/sync", "/hat/alarm/list", "/hat/location/record/list",
                    "/system/role/list", "/system/dept/list", "/system/menu/list", "/system/config/list",
                    "/system/dict/data/list", "/system/dict/type/list", "/system/post/list", "/system/notice/list",
                    "/system/user/profile", "/monitor/cache", "/monitor/logininfor/list", "/monitor/operlog/list",
                    "/monitor/online/list", "/monitor/server", "/common/upload", "/register", "/captchaImage", "/getInfo", "/getRouters")) {
                // DispatcherServlet's '/' mapping retains the full servlet path, including
                // a trailing slash. The builder helper forbids that slash, so model the
                // container request directly without changing its URI or the assertion.
                http.perform(get(path).with(request -> { request.setServletPath(path); return request; })
                                .header("Authorization", "Bearer valid-legacy-admin"))
                        .andExpect(status().isGone()).andExpect(jsonPath("$.errorCode").value("LEGACY_ENDPOINT_RETIRED"));
                http.perform(post(path).with(request -> { request.setServletPath(path); return request; })).andExpect(status().isGone());
            }
            assertEquals(0, ctx.getBean(Probe.class).invocations);
        }
    }
    @Test void encodedAndParameterizedRetiredPathsNeverReachControllers() throws Exception {
        try (AnnotationConfigWebApplicationContext ctx = context(false)) {
            MockMvc http = mvc(ctx);
            for (String path : Arrays.asList("/%68at/safety/info/list", "/hat%2Fsafety/info/list", "/hat;x=1/safety/info/list",
                    "/%2568at/safety/info/list", "/hat//safety/info/list", "/hat/../hat/safety/info/list")) {
                try {
                    int status = http.perform(get(URI.create(path)).header("Authorization", "Bearer valid-legacy-admin"))
                            .andReturn().getResponse().getStatus();
                    assertTrue(status >= 400 && status < 500, path);
                } catch (org.springframework.security.web.firewall.RequestRejectedException expected) {
                    // StrictHttpFirewall may reject before our boundary filter runs.
                }
            }
            assertEquals(0, ctx.getBean(Probe.class).invocations);
        }
    }
    @Test void exactDeviceEntrypointsAndUnrelatedPrefixesArePreserved() throws Exception {
        try (AnnotationConfigWebApplicationContext ctx = context(false)) {
            MockMvc http = mvc(ctx);
            for (String path : Arrays.asList("/wsHat", "/wsBelt", "/api/index.php", "/api/melhat/index.php",
                    "/api/melhat/config/index.php", "/api/belt/index.php", "/api/belt/config/index.php")) {
                http.perform(get(path).servletPath(path)).andExpect(status().isOk());
                http.perform(post(path).servletPath(path)).andExpect(status().isOk());
            }
            for (String path : Arrays.asList("/hatchet", "/wsHatExtra"))
                http.perform(get(path).servletPath(path).header("Authorization", "Bearer valid-legacy-admin")).andExpect(status().isOk());
            http.perform(get("/")).andExpect(status().isOk());
            for (String path : Arrays.asList("/api/admin/v1/login", "/api/guardian/v1/login", "/api/guardian/v1/mobile/login"))
                http.perform(post(path).servletPath(path)).andExpect(status().isOk());
        }
    }
    @Test void callbackDefaultsClosedAndUsesSeparateCredentialWithExactPostAllowlist() throws Exception {
        try (AnnotationConfigWebApplicationContext ctx = context(false)) {
            mvc(ctx).perform(post("/ext/helmetAlarm").servletPath("/ext/helmetAlarm").header(LegacyEndpointBoundaryFilter.CALLBACK_HEADER, KEY))
                    .andExpect(status().isGone());
        }
        try (AnnotationConfigWebApplicationContext ctx = context(true)) {
            MockMvc http = mvc(ctx);
            http.perform(post("/ext/helmetAlarm").servletPath("/ext/helmetAlarm").header("Authorization", "Bearer valid-legacy-admin"))
                    .andExpect(status().isUnauthorized());
            http.perform(post("/ext/helmetAlarm").servletPath("/ext/helmetAlarm").header(LegacyEndpointBoundaryFilter.CALLBACK_HEADER, "wrong"))
                    .andExpect(status().isUnauthorized());
            http.perform(get("/ext/helmetAlarm").servletPath("/ext/helmetAlarm").header(LegacyEndpointBoundaryFilter.CALLBACK_HEADER, KEY))
                    .andExpect(status().isMethodNotAllowed());
            http.perform(post("/ext/unknown").servletPath("/ext/unknown").header(LegacyEndpointBoundaryFilter.CALLBACK_HEADER, KEY))
                    .andExpect(status().isGone());
            for (String path : Arrays.asList("/ext/helmetAlarm", "/ext/notifyGnss", "/ext/sosCall"))
                http.perform(post(path).servletPath(path).header(LegacyEndpointBoundaryFilter.CALLBACK_HEADER, KEY))
                        .andExpect(status().isOk()).andExpect(content().string("authenticated-callback"));
        }
    }
    @Test void websocketContainerCannotBypassHttpRetirement() throws Exception {
        assertFalse(WebSocketSever.class.isAnnotationPresent(javax.websocket.server.ServerEndpoint.class));
        assertFalse(WebSocketSever.class.isAnnotationPresent(org.springframework.stereotype.Component.class));
        Session session = mock(Session.class);
        WebSocketSever socket = new WebSocketSever();
        WebSocketSever.sessionPool.clear();
        socket.onOpen(session, "legacy-user", "1");
        assertTrue(WebSocketSever.sessionPool.isEmpty());
        socket.onMessage("ping", session);
        verify(session, times(2)).close(argThat(reason -> reason.getCloseCode() == CloseReason.CloseCodes.VIOLATED_POLICY));
        verifyNoMoreInteractions(session);
    }
    @Test void retiredBinaryCompatibilityShimsCannotUseEvenExternallyPopulatedSessions() {
        Session session = mock(Session.class);
        WebSocketSever.sessionPool.put("legacy-user_1", session);
        try {
            WebSocketSever.sendMessageByUser("legacy-user_1", "sensitive");
            WebSocketSever.sendAllMessage("sensitive");
            WebSocketSever.sendAllPcMessage("sensitive");
            WebSocketSever socket = new WebSocketSever();
            socket.onClose(session, new CloseReason(CloseReason.CloseCodes.NORMAL_CLOSURE, "closed"));
            socket.onError(session, new IOException("error"));
            verifyNoInteractions(session);
        } finally { WebSocketSever.sessionPool.clear(); }
    }
    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({SecurityConfig.class, Probe.class})
    static class App {
        @Bean UserDetailsService userDetailsService() { return mock(UserDetailsService.class); }
        static TokenService tokenService() {
            TokenService service = mock(TokenService.class);
            SysUser user = new SysUser();user.setUserId(1L);user.setUserName("admin");
            LoginUser login = new LoginUser(1L, 1L, user, new HashSet<>(Collections.singletonList("*:*:*")));
            when(service.getLoginUser(any(HttpServletRequest.class))).thenAnswer(i ->
                    "Bearer valid-legacy-admin".equals(((HttpServletRequest)i.getArgument(0)).getHeader("Authorization")) ? login : null);
            return service;
        }
        @Bean JwtAuthenticationTokenFilter tokenFilter() { return new JwtAuthenticationTokenFilter(); }
        @Bean AuthenticationEntryPointImpl unauthorizedHandler() { return new AuthenticationEntryPointImpl(); }
        @Bean CorsFilter corsFilter() { return new CorsFilter(new UrlBasedCorsConfigurationSource()); }
    }
    @RestController static class Probe {
        int invocations;
        @RequestMapping("/**") String invoke(HttpServletRequest request) {
            invocations++;
            return Boolean.TRUE.equals(request.getAttribute(LegacyEndpointBoundaryFilter.CALLBACK_AUTHENTICATED)) ? "authenticated-callback" : "ok";
        }
    }
}
