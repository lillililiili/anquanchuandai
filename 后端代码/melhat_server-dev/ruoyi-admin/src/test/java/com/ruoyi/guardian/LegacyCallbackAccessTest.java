package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.framework.security.filter.LegacyEndpointBoundaryFilter;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class LegacyCallbackAccessTest {
    @AfterEach void cleanup() { RequestContextHolder.resetRequestAttributes(); }
    @Test void duplicateIdentityCannotSelectAnAuthorizedRecordOverAnotherStationsAlias() {
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        JSONObject allowed = object("sn","registered","portalDeviceId","portal-1","siteId","site-1","source","PLATFORM","type","HELMET","lifecycle","IN_USE");
        JSONObject other = object("sn","other","portalDeviceId","registered","siteId","site-2","source","DIRECT_HELMET","type","HELMET","lifecycle","DISABLED");
        JSONObject state = object("devices",JSONArray.of(allowed,other),"sites",JSONArray.of(object("id","site-1","enabled",true)));
        when(ledger.read()).thenReturn(state);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(LegacyEndpointBoundaryFilter.CALLBACK_AUTHENTICATED, Boolean.TRUE);
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request));
        LegacyCallbackAccess access = new LegacyCallbackAccess(ledger, "site-1");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        state.put("devices",JSONArray.of(other,allowed));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        other.put("siteId","site-1");other.put("source","PLATFORM");other.put("lifecycle","IN_USE");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        state.put("devices",JSONArray.of(allowed));
        assertDoesNotThrow(() -> access.requireDevice("registered"));
    }
    @Test void authenticatedServiceCannotTargetAnotherStationDirectHardwareOrUnassignedDevice() {
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        JSONObject device = object("sn","registered","portalDeviceId","registered","siteId","site-1","source","PLATFORM","type","HELMET","lifecycle","IN_USE");
        JSONObject site = object("id","site-1","enabled",true);
        when(ledger.read()).thenReturn(object("devices",JSONArray.of(device),"sites",JSONArray.of(site)));
        LegacyCallbackAccess access = new LegacyCallbackAccess(ledger, "site-1");
        assertEquals(401, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        verifyNoInteractions(ledger);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(LegacyEndpointBoundaryFilter.CALLBACK_AUTHENTICATED, Boolean.TRUE);
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request));
        assertDoesNotThrow(() -> access.requireDevice("registered"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("unknown")).code);
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> new LegacyCallbackAccess(ledger, "").requireDevice("registered")).code);
        device.put("siteId","site-2");assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        device.put("siteId","site-1");device.put("source","DIRECT_HELMET");assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        device.put("source","PLATFORM");device.put("lifecycle","DISABLED");assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
        device.put("lifecycle","IN_USE");site.put("enabled",false);assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> access.requireDevice("registered")).code);
    }
}
