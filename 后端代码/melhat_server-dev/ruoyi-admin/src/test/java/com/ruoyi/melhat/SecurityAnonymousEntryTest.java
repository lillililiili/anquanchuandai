package com.ruoyi.melhat;

import com.ruoyi.framework.config.SecurityPathRules;
import com.ruoyi.framework.security.filter.DeviceCallbackAuthFilter;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SecurityAnonymousEntryTest {

    @Test
    void publicPathsDoNotIncludeFormerAnonymousBusinessEntries() {
        List<String> publicPaths = Arrays.asList(SecurityPathRules.PUBLIC);
        assertTrue(publicPaths.contains("/login"));
        assertTrue(publicPaths.contains("/captchaImage"));
        assertTrue(publicPaths.contains("/actuator/health"));
        assertFalse(publicPaths.contains("/api/melhat/**"));
        assertFalse(publicPaths.contains("/monitor/job/**"));
        assertFalse(publicPaths.contains("/test/**"));
        assertFalse(publicPaths.contains("/ext/**"));
        assertFalse(publicPaths.contains("/ws/**"));
    }

    @Test
    void callbackWithoutTokenIsUnauthorized() throws Exception {
        DeviceCallbackAuthFilter filter = new DeviceCallbackAuthFilter();
        filter.setExpectedToken("s0-callback-secret");
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/ext/helmetAlarm");
        request.setRequestURI("/ext/helmetAlarm");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        assertEquals(401, response.getStatus());
        assertTrue(response.getContentAsString().contains("设备回调未认证"));
        assertFalse(response.getContentAsString().contains("s0-callback-secret"));
    }

    @Test
    void callbackWithMatchingTokenContinues() throws Exception {
        DeviceCallbackAuthFilter filter = new DeviceCallbackAuthFilter();
        filter.setExpectedToken("s0-callback-secret");
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/ext/helmetAlarm");
        request.setRequestURI("/ext/helmetAlarm");
        request.addHeader(DeviceCallbackAuthFilter.HEADER, "s0-callback-secret");
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();
        filter.doFilter(request, response, chain);
        assertEquals(200, response.getStatus());
        assertTrue(SecurityPathRules.isDeviceCallback("/ext/helmetAlarm"));
        assertTrue(SecurityPathRules.isDeviceCallback("/aip/head/band/location"));
        assertFalse(SecurityPathRules.isDeviceCallback("/hat/safety/info/save"));
    }

    @Test
    void emptyConfiguredTokenRejectsAllCallbacks() throws Exception {
        DeviceCallbackAuthFilter filter = new DeviceCallbackAuthFilter();
        filter.setExpectedToken("");
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/ext/helmetAlarm");
        request.setRequestURI("/ext/helmetAlarm");
        request.addHeader(DeviceCallbackAuthFilter.HEADER, "anything");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        assertEquals(401, response.getStatus());
    }
}
