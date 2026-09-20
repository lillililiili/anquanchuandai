package com.ruoyi.portal;
import com.ruoyi.portal.demo.DemoBoundary;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.junit.jupiter.api.Assertions.*;
class DemoBoundaryTest {
    private boolean allowed(String method,String path)throws Exception{
        MockHttpServletRequest request=new MockHttpServletRequest(method,path);MockHttpServletResponse response=new MockHttpServletResponse();AtomicBoolean passed=new AtomicBoolean();
        new DemoBoundary().doFilter(request,response,(q,s)->passed.set(true));
        if(!passed.get())assertEquals(403,response.getStatus());return passed.get();
    }
    @Test void authCanReachRealSecurityChain()throws Exception{assertTrue(allowed("POST","/login"));assertTrue(allowed("GET","/getInfo"));assertTrue(allowed("POST","/logout"));}
    @Test void portalCanReachRealSecurityChain()throws Exception{assertTrue(allowed("GET","/api/portal/v1/context"));assertTrue(allowed("POST","/api/portal/v1/equipment-assignments"));}
    @Test void legacyCommandsBlocked()throws Exception{for(String path:new String[]{"/hat/alarm/handle","/hat/safety/info/platform/sync","/api/melhat/test","/ext/receive","/wsHat"})assertFalse(allowed("POST",path));}
    @Test void registrationAndManagementBlocked()throws Exception{for(String path:new String[]{"/register","/monitor/job/list","/system/user/list","/common/upload","/profile/example.png","/druid/index.html"})assertFalse(allowed("GET",path));}
    @Test void alternateAuthMethodsBlocked()throws Exception{assertFalse(allowed("GET","/login"));assertFalse(allowed("POST","/getInfo"));}
    @Test void encodedAndTraversalPathsBlocked()throws Exception{for(String path:new String[]{"/api/portal/v1/../hat","/api/portal/v1/%2e%2e/hat","/api/portal/v1/a;b"})assertFalse(allowed("GET",path));}
}
