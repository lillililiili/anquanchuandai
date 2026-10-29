package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.framework.config.SecurityConfig;
import com.ruoyi.framework.config.properties.PermitAllUrlProperties;
import com.ruoyi.framework.security.filter.JwtAuthenticationTokenFilter;
import com.ruoyi.framework.security.handle.AuthenticationEntryPointImpl;
import com.ruoyi.framework.security.handle.LogoutSuccessHandlerImpl;
import com.ruoyi.framework.web.service.TokenService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.mock.web.MockServletContext;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;

import javax.servlet.Filter;
import java.net.URI;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class DirectHelmetConfigControllerTest {
    private DirectHelmetProperties properties;
    private DirectHelmetGateway gateway;
    private DirectHelmetConfigController controller;

    @BeforeEach void setup() {
        properties = new DirectHelmetProperties();
        properties.setEnabled(true);
        properties.setPublicBaseUrl("https://helmet.example.test");
        gateway = mock(DirectHelmetGateway.class);
        when(gateway.supports("registered-helmet")).thenReturn(true);
        controller = new DirectHelmetConfigController(properties, gateway);
    }

    @Test void documentBootstrapAndLegacyPathsRemainAnonymousWithoutOpeningOtherApiPaths() throws Exception {
        AnnotationConfigWebApplicationContext context = new AnnotationConfigWebApplicationContext();
        context.setServletContext(new MockServletContext());
        context.addBeanFactoryPostProcessor(factory -> {
            factory.registerSingleton("directHelmetProperties", properties);
            factory.registerSingleton("directHelmetGateway", gateway);
            factory.registerSingleton("userDetailsService", mock(UserDetailsService.class));
            factory.registerSingleton("tokenService", mock(TokenService.class));
            factory.registerSingleton("logoutSuccessHandler", mock(LogoutSuccessHandlerImpl.class));
            PermitAllUrlProperties urls = mock(PermitAllUrlProperties.class);
            when(urls.getUrls()).thenReturn(Collections.emptyList());
            factory.registerSingleton("permitAllUrlProperties", urls);
        });
        context.register(SecurityApp.class);
        try {
            context.refresh();
            MockMvc mvc = MockMvcBuilders.webAppContextSetup(context)
                    .addFilters(context.getBean("springSecurityFilterChain", Filter.class)).build();
            for (String path : new String[]{"/api/index.php", "/api/melhat/config/index.php", "/api/melhat/index.php"}) {
                JSONObject response = json(mvc.perform(get(path).servletPath(path)
                        .param("ctl", "config").param("act", "get_config").param("device_id", "registered-helmet")
                        .param("ca_ver", "test-firmware").param("app_version", "test-version"))
                        .andExpect(status().isOk()).andReturn());
                assertTrue(response.getBooleanValue("status"), path);
                assertTrue(response.getJSONObject("data").get("config") instanceof String);
                JSONObject config = JSONObject.parseObject(response.getJSONObject("data").getString("config"));
                assertEquals("https://helmet.example.test/api/", config.getString("api_url"));
                assertEquals("https://helmet.example.test/api/index.php", URI.create(config.getString("api_url")).resolve("index.php").toString());
                assertEquals("wss://helmet.example.test/wsHat", config.getString("ws_url"));
                assertFalse(response.getJSONObject("data").containsKey("extra"),
                        "Absent accessory configuration must not overwrite the firmware's paired wristband");
            }
            for (String path : new String[]{"/api/private", "/api/index.php/other", "/api/index.php.extra"}) {
                JSONObject response = json(mvc.perform(get(path).servletPath(path)).andReturn());
                assertEquals(401, response.getIntValue("code"), path);
            }
            JSONObject unsupportedGet = json(mvc.perform(get("/api/index.php").servletPath("/api/index.php")
                    .param("ctl", "unknown").param("act", "get_config").param("device_id", "registered-helmet"))
                    .andExpect(status().isOk()).andReturn());
            assertFalse(unsupportedGet.getBooleanValue("status"));
            for (String path : new String[]{"/api/index.php", "/api/melhat/index.php"}) {
                JSONObject unsupportedPost = json(mvc.perform(post(path).servletPath(path)
                        .param("ctl", "image").param("act", "save_image"))
                        .andExpect(status().isOk()).andReturn());
                assertFalse(unsupportedPost.getBooleanValue("status"));
                assertEquals("Unsupported", unsupportedPost.getString("msg_code"));
            }
            mvc.perform(get("/api/index.php").servletPath("/api/index.php").param("ctl", "config"))
                    .andExpect(status().isBadRequest());
        } finally {
            context.close();
        }
    }

    @Test void explicitApiScriptConfigurationIsNormalizedForFirmwareAppendingIndexPhp() {
        for (String configured : new String[]{"https://upload.example.test/device", "https://upload.example.test/device/",
                "https://upload.example.test/device/index.php", "https://upload.example.test/device/index.php/"}) {
            properties.setApiUrl(configured);
            JSONObject response = controller.configuration("config", "get_config", "registered-helmet");
            assertTrue(response.getBooleanValue("status"));
            JSONObject config = JSONObject.parseObject(response.getJSONObject("data").getString("config"));
            assertEquals("https://upload.example.test/device/", config.getString("api_url"));
        }
    }

    @Test void configurationCannotSucceedForUnknownActionsUnregisteredDevicesOrDisabledGateway() {
        assertFalse(controller.configuration("config", "unknown", "registered-helmet").getBooleanValue("status"));
        assertFalse(controller.configuration("unknown", "get_config", "registered-helmet").getBooleanValue("status"));
        assertFalse(controller.configuration("config", "get_config", "unregistered").getBooleanValue("status"));
        assertFalse(controller.configuration("config", "get_config", null).getBooleanValue("status"));
        assertFalse(controller.deviceRequest("unknown", "unknown").getBooleanValue("status"));
        properties.setEnabled(false);
        assertFalse(controller.configuration("config", "get_config", "registered-helmet").getBooleanValue("status"));
    }

    @Test void invalidApiOverridesFailWithoutReturningConfiguredAddresses() {
        for (String invalid : new String[]{"ftp://upload.example.test/device/", "https://user:secret@upload.example.test/api/",
                "https://upload.example.test/api/?key=value", "https://upload.example.test/api/#fragment"}) {
            properties.setApiUrl(invalid);
            JSONObject response = controller.configuration("config", "get_config", "registered-helmet");
            assertFalse(response.getBooleanValue("status"));
            assertFalse(response.containsKey("data"));
        }
    }

    private static JSONObject json(MvcResult result) throws Exception {
        return JSONObject.parseObject(result.getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
    }

    @Configuration
    @EnableWebMvc
    @EnableWebSecurity
    @Import({SecurityConfig.class, DirectHelmetConfigController.class})
    static class SecurityApp {
        @Bean JwtAuthenticationTokenFilter tokenFilter() { return new JwtAuthenticationTokenFilter(); }
        @Bean AuthenticationEntryPointImpl unauthorizedHandler() { return new AuthenticationEntryPointImpl(); }
        @Bean CorsFilter corsFilter() { return new CorsFilter(new UrlBasedCorsConfigurationSource()); }
    }
}
