package com.ruoyi.wear.event;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.math.BigDecimal;
import java.util.Collections;
import java.util.Map;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.core.io.ClassPathResource;
import org.springframework.util.StreamUtils;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.event.dto.SimulateRequest;

/** Test fixtures only: values do not evaluate production alarm rules. */
public final class SimulationScenarios
{
    private static final String CATALOG = load();
    private SimulationScenarios() {}

    private static String load()
    {
        try (InputStream in = new ClassPathResource("wear/simulation-scenarios.json").getInputStream())
        {
            return StreamUtils.copyToString(in, StandardCharsets.UTF_8);
        }
        catch (IOException ex) { throw new IllegalStateException("Missing simulation scenarios", ex); }
    }

    public static JSONArray list() { return JSON.parseArray(CATALOG); }

    public static String detail(SimulateRequest request, String deviceType)
    {
        JSONObject scenario = null;
        for (Object item : list())
        {
            JSONObject candidate = (JSONObject) item;
            if (candidate.getString("id").equals(request.getScenarioCode())) scenario = candidate;
        }
        if (scenario == null || !scenario.getString("deviceType").equals(deviceType)
                || !scenario.getString("type").equals(request.getType()))
            throw bad("场景、设备类型或事件类型不匹配");
        Map<String, BigDecimal> values = request.getMeasurements() == null
                ? Collections.<String, BigDecimal>emptyMap() : request.getMeasurements();
        JSONArray fields = scenario.getJSONArray("fields");
        if (values.size() != fields.size()) throw bad("测试参数不完整或包含未知字段");
        for (Object item : fields)
        {
            JSONObject field = (JSONObject) item;
            BigDecimal value = values.get(field.getString("key"));
            if (value == null || value.compareTo(field.getBigDecimal("min")) < 0
                    || value.compareTo(field.getBigDecimal("max")) > 0
                    || value.scale() > 3)
                throw bad("测试参数越界或超过三位小数：" + field.getString("label"));
        }
        JSONObject result = new JSONObject();
        result.put("tool", "call-lab");
        result.put("scenarioCode", scenario.getString("id"));
        result.put("label", scenario.getString("label"));
        StringBuilder description = new StringBuilder(scenario.getString("label"));
        for (Object item : fields)
        {
            JSONObject field = (JSONObject) item;
            description.append("；").append(field.getString("label")).append("：")
                    .append(values.get(field.getString("key")).stripTrailingZeros().toPlainString())
                    .append(field.getString("unit") == null ? "" : field.getString("unit"));
        }
        result.put("description", description.toString());
        result.put("measurements", values);
        String detail = result.toJSONString();
        if (detail.length() > 500) throw bad("测试说明过长");
        return detail;
    }

    private static ServiceException bad(String message)
    {
        return new ServiceException(message, HttpStatus.BAD_REQUEST);
    }
}
