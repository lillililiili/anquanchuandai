package com.ruoyi.melhat;

import java.util.Arrays;
import java.util.Collections;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.mockito.ArgumentCaptor;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.web.InspectionAccessConfig;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class ContactReadAccessTest {
    private final SiteAccessService sites = spy(new SiteAccessService());

    private HandlerInterceptor inspector() {
        SysUser account = new SysUser();
        account.setUserId(100L);
        account.setRoles(Collections.emptyList());
        LoginUser user = new LoginUser();
        user.setUserId(100L);
        user.setUser(account);
        doReturn(user).when(sites).requireLogin();
        doReturn(1L).when(sites).resolveRequestSiteId();
        InspectionAccessConfig config = new InspectionAccessConfig();
        ReflectionTestUtils.setField(config, "sites", sites);
        InterceptorRegistry registry = mock(InterceptorRegistry.class);
        when(registry.addInterceptor(any())).thenAnswer(invocation ->
                new InterceptorRegistration(invocation.getArgument(0)));
        config.addInterceptors(registry);
        ArgumentCaptor<HandlerInterceptor> captured = ArgumentCaptor.forClass(HandlerInterceptor.class);
        verify(registry).addInterceptor(captured.capture());
        return captured.getValue();
    }

    @Test void inspectorCanReadStationContactsAndOwnEquipmentWithoutManagementAccess() throws Exception {
        HandlerInterceptor access = inspector();
        for (String path : Arrays.asList("/api/v1/people", "/api/v1/people/options", "/api/v1/people/2",
                "/api/v1/devices", "/api/v1/devices/10", "/api/v1/me/equipment")) {
            assertTrue(access.preHandle(new MockHttpServletRequest("GET", path),
                    new MockHttpServletResponse(), new Object()), path);
        }
        for (String path : Arrays.asList("/api/v1/work-tasks", "/api/v1/duty/operators",
                "/api/v1/devices/10/ingest", "/api/v1/calls/1/credentials", "/api/v1/lab/state",
                "/api/v1/people/2/equipment", "/api/v1/people/2/assignments", "/api/v1/locations")) {
            assertThrows(ServiceException.class, () -> access.preHandle(new MockHttpServletRequest("GET", path),
                    new MockHttpServletResponse(), new Object()), path);
        }
        for (String path : Arrays.asList("/api/v1/people", "/api/v1/devices", "/api/v1/work-tasks",
                "/api/v1/calls", "/api/v1/lab/calls", "/api/v1/commands/tts", "/api/v1/events/1/close")) {
            for (String method : Arrays.asList("POST", "PUT", "DELETE")) {
                assertThrows(ServiceException.class, () -> access.preHandle(new MockHttpServletRequest(method, path),
                        new MockHttpServletResponse(), new Object()), method + " " + path);
            }
        }
    }

    @Test void contactReadsRequireCurrentStationAndRetainDeviceStationChecks() throws Exception {
        HandlerInterceptor access = inspector();
        WearDevice own = new WearDevice(); own.setSiteId(1L);
        WearDevice coworker = new WearDevice(); coworker.setSiteId(1L);
        WearDevice otherStation = new WearDevice(); otherStation.setSiteId(2L);
        assertDoesNotThrow(() -> sites.assertDeviceReadable(own));
        assertDoesNotThrow(() -> sites.assertDeviceReadable(coworker));
        assertThrows(ServiceException.class, () -> sites.assertDeviceReadable(otherStation));
        doReturn(null).when(sites).resolveRequestSiteId();
        for (String path : Arrays.asList("/api/v1/people", "/api/v1/devices/10")) {
            assertThrows(ServiceException.class, () -> access.preHandle(new MockHttpServletRequest("GET", path),
                    new MockHttpServletResponse(), new Object()));
        }
    }

    @Test void normalIdentityAdvertisesContactReadsWithoutControlOrManagement() {
        inspector();
        Set<String> permissions = sites.permissions();
        for (String permission : Arrays.asList("wear:person:list", "wear:person:query",
                "wear:device:list", "wear:device:query", "wear:inspection:report")) {
            assertTrue(permissions.contains(permission), permission);
        }
        for (String permission : Arrays.asList("wear:person:edit", "wear:device:edit", "wear:task:edit",
                "wear:event:review", "wear:event:claim", "wear:call:start", "wear:command:tts", "wear:duty:handover")) {
            assertFalse(permissions.contains(permission), permission);
        }
        assertFalse(sites.canStartCall());
        assertFalse(sites.canSendTts());
    }
}
