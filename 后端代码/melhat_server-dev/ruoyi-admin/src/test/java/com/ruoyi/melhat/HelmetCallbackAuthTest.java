package com.ruoyi.melhat;

import com.ruoyi.wear.helmet.HelmetCallbackAuth;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import com.ruoyi.framework.security.filter.DeviceCallbackAuthFilter;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class HelmetCallbackAuthTest {

    @Test
    void hmacRejectsBadSignatureExpiredTimestamp() {
        String secret = "unit-secret";
        byte[] body = "{\"helmetSn\":\"MH-1\"}".getBytes();
        long now = 1_700_000_000L;
        String ts = String.valueOf(now);
        String nonce = "n-1";
        String sig = HelmetCallbackAuth.hmacHex(secret, ts, nonce, body);
        assertNull(HelmetCallbackAuth.verifyHmac(secret, ts, nonce, body, sig, now, 300));
        assertEquals("bad signature", HelmetCallbackAuth.verifyHmac(secret, ts, nonce, body, "deadbeef", now, 300));
        assertEquals("timestamp skew", HelmetCallbackAuth.verifyHmac(secret, String.valueOf(now - 301), nonce, body, sig, now, 300));
        assertNotNull(HelmetCallbackAuth.verifyHmac(secret, ts, "", body, sig, now, 300));
    }

    @Test
    void filterRejectsWhenHmacConfiguredAndMissing() throws Exception {
        DeviceCallbackAuthFilter filter = new DeviceCallbackAuthFilter();
        filter.setExpectedToken("s0-callback-secret");
        filter.setHmacSecret("unit-secret");
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/ext/sosCall");
        request.setRequestURI("/ext/sosCall");
        request.addHeader(DeviceCallbackAuthFilter.HEADER, "s0-callback-secret");
        request.setContent("{\"helmetSn\":\"MH-1\"}".getBytes());
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        assertEquals(401, response.getStatus());
        assertTrue(response.getContentAsString().contains("设备回调未认证"));
    }
}
