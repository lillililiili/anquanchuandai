package com.ruoyi.melhat;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.event.SimulationScenarios;
import com.ruoyi.wear.event.dto.SimulateRequest;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class SimulationScenariosTest
{
    @Test
    void everyCatalogFixtureValidatesAndFitsAuditColumn()
    {
        HashSet<String> ids = new HashSet<>();
        for (Object raw : SimulationScenarios.list())
        {
            JSONObject s = (JSONObject) raw;
            assertTrue(ids.add(s.getString("id")));
            SimulateRequest request = request(s);
            Map<String, BigDecimal> values = new HashMap<>();
            for (Object f : s.getJSONArray("fields"))
            {
                JSONObject field = (JSONObject) f;
                values.put(field.getString("key"), field.getBigDecimal("value"));
            }
            request.setMeasurements(values);
            String detail = SimulationScenarios.detail(request, s.getString("deviceType"));
            assertTrue(detail.length() <= 500);
            assertEquals(s.getString("id"), JSONObject.parseObject(detail).getString("scenarioCode"));
        }
        assertEquals(26, ids.size());
    }

    @Test
    void rejectsWrongDeviceTypeWrongEventUnknownMissingAndOutOfRangeValues()
    {
        JSONObject scenario = null;
        for (Object raw : SimulationScenarios.list())
            if ("watch.heart_high".equals(((JSONObject) raw).getString("id"))) scenario = (JSONObject) raw;
        SimulateRequest r = request(scenario);
        r.setMeasurements(new HashMap<>());
        r.getMeasurements().put("heartRate", new BigDecimal("130"));
        assertThrows(ServiceException.class, () -> SimulationScenarios.detail(r, "helmet"));
        r.setType("sos");
        assertThrows(ServiceException.class, () -> SimulationScenarios.detail(r, "watch"));
        r.setType("realtime");
        r.getMeasurements().put("extra", BigDecimal.ONE);
        assertThrows(ServiceException.class, () -> SimulationScenarios.detail(r, "watch"));
        r.getMeasurements().clear();
        assertThrows(ServiceException.class, () -> SimulationScenarios.detail(r, "watch"));
        r.getMeasurements().put("heartRate", new BigDecimal("301"));
        assertThrows(ServiceException.class, () -> SimulationScenarios.detail(r, "watch"));
    }

    private SimulateRequest request(JSONObject s)
    {
        SimulateRequest r = new SimulateRequest();
        r.setScenarioCode(s.getString("id"));
        r.setType(s.getString("type"));
        return r;
    }
}
