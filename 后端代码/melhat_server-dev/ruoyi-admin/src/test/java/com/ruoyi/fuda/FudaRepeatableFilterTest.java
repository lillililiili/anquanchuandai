package com.ruoyi.fuda;

import com.ruoyi.common.filter.RepeatableFilter;
import com.ruoyi.common.filter.RepeatedlyRequestWrapper;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import javax.servlet.ServletInputStream;
import java.io.BufferedReader;
import java.nio.charset.StandardCharsets;
import static org.junit.jupiter.api.Assertions.*;

class FudaRepeatableFilterTest {
    @Test void exactSignedRoutesReachTheirBoundedReadersWithoutAnyEagerBodyRead()throws Exception {
        String[][] routes={
                {"POST","/openapi/wearables/v2/positions/query"},
                {"POST","/openapi/wearables/v2/statuses/query"},
                {"POST","/openapi/wearables/v2/alarms/query"},
                {"GET","/internal/fuda-gb/v1/devices/helmet-a/status"},
                {"PUT","/internal/fuda-gb/v1/leases/lease-test-00000001"},
                {"GET","/internal/fuda-gb/v1/leases/lease-test-00000001"},
                {"DELETE","/internal/fuda-gb/v1/leases/lease-test-00000001"}};
        for(String[] route:routes){
            MockHttpServletRequest request=new MockHttpServletRequest(route[0],route[1]){
                @Override public ServletInputStream getInputStream(){throw new AssertionError("Filter must not consume signed body");}
                @Override public BufferedReader getReader(){throw new AssertionError("Filter must not decode signed body");}
            };
            request.setContentType("application/json");
            new RepeatableFilter().doFilter(request,new MockHttpServletResponse(),(passed,response)->assertSame(request,passed));
        }
    }
    @Test void unrelatedPathsNearMatchesAndWrongMethodsKeepLegacyBehavior()throws Exception {
        String[][] routes={{"POST","/api/guardian/v1/example"},{"POST","/openapi/other"},
                {"POST","/openapi/wearables/v2/positions/query/"},{"POST","/openapi/wearables/v2/positions/query/extra"},
                {"GET","/openapi/wearables/v2/positions/query"},{"POST","/internal/fuda-gb/v1/leases/lease-test-00000001"},
                {"PUT","/internal/fuda-gb/v1/leases/lease-test-00000001/extra"},{"GET","/internal/fuda-gb/v1/devices/helmet-a/status/extra"}};
        for(String[] route:routes){MockHttpServletRequest request=new MockHttpServletRequest(route[0],route[1]);request.setContentType("application/json");request.setContent("{\r\n  \"legacy\":true\r\n}".getBytes(StandardCharsets.UTF_8));
            new RepeatableFilter().doFilter(request,new MockHttpServletResponse(),(passed,response)->assertTrue(passed instanceof RepeatedlyRequestWrapper));}
    }
}
