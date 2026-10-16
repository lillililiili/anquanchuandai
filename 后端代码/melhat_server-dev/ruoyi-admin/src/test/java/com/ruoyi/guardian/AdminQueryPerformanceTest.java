package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminQueryPerformanceTest {
    JSONObject state, snapshot;
    GuardianStore guardian;
    AdminQueryService service;

    JSONObject seed(String name) throws Exception {
        return JSON.parseObject(StreamUtils.copyToString(new ClassPathResource(name).getInputStream(), StandardCharsets.UTF_8));
    }
    JSONObject input() { return JSON.parseObject("{\"siteId\":\"site-1\",\"pageSize\":100}"); }

    @BeforeEach void setup() throws Exception {
        state = seed("admin-seed.json"); snapshot = seed("guardian-seed.json");
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> JSON.parseObject(state.toJSONString()));
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(i -> JSON.parseObject(snapshot.toJSONString()));
        service = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
    }

    @Test void overviewDoesNotReadTelemetryAndMatchesEachDetailTotal() {
        for (String actor : Arrays.asList("demo-system", "demo-asset", "demo-audit")) {
            clearInvocations(guardian);
            Map<String, Object> counts = (Map<String, Object>) service.query(actor, "overview", input()).get("counts");
            verifyNoInteractions(guardian);
            assertEquals(32, counts.get("assets")); assertEquals(4, counts.get("available")); assertEquals(24, counts.get("assigned"));
            for (String metric : counts.keySet()) {
                JSONObject query = input(); query.put("metric", metric);
                assertEquals(counts.get(metric), service.query(actor, "details", query).get("total"), metric);
            }
        }
    }

    @Test void aDeviceListReadsOneFreshSnapshotPerRequest() {
        service.query("demo-system", "devices", input());
        verify(guardian, times(1)).snapshot();
        JSONObject remote = snapshot.getJSONArray("devices").getJSONObject(0);
        remote.put("online", false); remote.put("battery", 17);
        List<JSONObject> rows = (List<JSONObject>) service.query("demo-system", "devices", input()).get("rows");
        verify(guardian, times(2)).snapshot();
        JSONObject changed = rows.stream().filter(r -> remote.getString("id").equals(r.getString("code"))).findFirst().get();
        assertEquals("OFFLINE", changed.getString("communication")); assertEquals(17, changed.getIntValue("battery"));
    }

    @Test void absentTelemetryIsNotRetriedForEveryDevice() {
        when(guardian.snapshot()).thenReturn(null);
        assertFalse(((List<?>) service.query("demo-system", "devices", input()).get("rows")).isEmpty());
        verify(guardian, times(1)).snapshot();
    }

    @Test void deniedScopeStillFailsBeforeTelemetry() {
        JSONObject query = input(); query.put("siteId", "unassigned-site");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> service.query("demo-asset", "overview", query)).code);
        verifyNoInteractions(guardian);
    }
}
