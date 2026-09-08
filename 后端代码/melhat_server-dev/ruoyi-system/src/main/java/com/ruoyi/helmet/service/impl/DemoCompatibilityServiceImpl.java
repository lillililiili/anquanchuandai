package com.ruoyi.helmet.service.impl;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.mapper.DemoCompatRecordMapper;
import com.ruoyi.helmet.pojo.po.DemoCompatRecord;
import com.ruoyi.helmet.service.DemoCompatibilityService;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * 从 demo_compat_record 读取 JSON，并将其展平为旧页面可直接使用的字段。
 */
@Service
public class DemoCompatibilityServiceImpl implements DemoCompatibilityService {

    private static final List<String> ALLOWED_MODULES = Arrays.asList("space", "module", "headBand", "systemHat");
    private static final List<String> PAGE_FILTERS = Arrays.asList("pageNum", "pageSize", "current", "size");

    private final DemoCompatRecordMapper recordMapper;

    public DemoCompatibilityServiceImpl(DemoCompatRecordMapper recordMapper) {
        this.recordMapper = recordMapper;
    }

    @Override
    public Map<String, Object> page(String moduleKey, Map<String, String> filters, int pageNum, int pageSize) {
        validateModule(moduleKey);
        int normalizedPage = Math.max(1, pageNum);
        int normalizedSize = Math.min(100, Math.max(1, pageSize));
        List<Map<String, Object>> all = recordMapper.selectList(new LambdaQueryWrapper<DemoCompatRecord>()
                        .eq(DemoCompatRecord::getModuleKey, moduleKey)
                        .orderByAsc(DemoCompatRecord::getId))
                .stream()
                .map(this::flatten)
                .filter(item -> matches(item, filters))
                .collect(Collectors.toList());
        int from = Math.min((normalizedPage - 1) * normalizedSize, all.size());
        int to = Math.min(from + normalizedSize, all.size());
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("rows", new ArrayList<>(all.subList(from, to)));
        result.put("total", all.size());
        return result;
    }

    @Override
    public Map<String, Object> detail(String moduleKey, Long id) {
        validateModule(moduleKey);
        DemoCompatRecord record = recordMapper.selectOne(new LambdaQueryWrapper<DemoCompatRecord>()
                .eq(DemoCompatRecord::getModuleKey, moduleKey)
                .eq(DemoCompatRecord::getId, id));
        if (record == null) {
            throw new ServiceException("演示记录不存在：" + id);
        }
        return flatten(record);
    }

    @Override
    public Long create(String moduleKey, Map<String, Object> payload) {
        validateModule(moduleKey);
        Map<String, Object> safePayload = new LinkedHashMap<>(payload == null ? Collections.emptyMap() : payload);
        String businessKey = asText(safePayload.remove("businessKey"));
        safePayload.remove("id");
        DemoCompatRecord record = new DemoCompatRecord();
        record.setModuleKey(moduleKey);
        record.setBusinessKey(isBlank(businessKey) ? moduleKey + "-" + UUID.randomUUID() : businessKey);
        record.setPayload(JSON.toJSONString(safePayload));
        recordMapper.insert(record);
        return record.getId();
    }

    @Override
    public boolean update(String moduleKey, Long id, Map<String, Object> payload) {
        validateModule(moduleKey);
        DemoCompatRecord current = find(moduleKey, id);
        Map<String, Object> mergedPayload = new LinkedHashMap<>(parsePayload(current));
        Map<String, Object> submittedPayload = new LinkedHashMap<>(payload == null ? Collections.emptyMap() : payload);
        removeControlFields(submittedPayload);
        mergedPayload.putAll(submittedPayload);
        current.setPayload(JSON.toJSONString(mergedPayload));
        return recordMapper.updateById(current) > 0;
    }

    @Override
    public boolean delete(String moduleKey, Long id) {
        validateModule(moduleKey);
        return recordMapper.deleteById(find(moduleKey, id).getId()) > 0;
    }

    private DemoCompatRecord find(String moduleKey, Long id) {
        if (id == null) {
            throw new ServiceException("演示记录 id 不能为空");
        }
        DemoCompatRecord record = recordMapper.selectOne(new LambdaQueryWrapper<DemoCompatRecord>()
                .eq(DemoCompatRecord::getModuleKey, moduleKey)
                .eq(DemoCompatRecord::getId, id));
        if (record == null) {
            throw new ServiceException("演示记录不存在：" + id);
        }
        return record;
    }

    private Map<String, Object> flatten(DemoCompatRecord record) {
        Map<String, Object> result = new LinkedHashMap<>(parsePayload(record));
        result.put("id", record.getId());
        result.put("businessKey", record.getBusinessKey());
        result.put("demo", true);
        applyPageAliases(record.getModuleKey(), result);
        return result;
    }

    private Map<String, Object> parsePayload(DemoCompatRecord record) {
        try {
            JSONObject json = JSON.parseObject(record.getPayload());
            if (json == null) {
                throw new ServiceException("演示记录 JSON 为空：" + record.getId());
            }
            return new LinkedHashMap<>(json);
        } catch (ServiceException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ServiceException("演示记录 JSON 解析失败，id=" + record.getId());
        }
    }

    private void removeControlFields(Map<String, Object> payload) {
        payload.remove("id");
        payload.remove("businessKey");
        payload.remove("demo");
        payload.remove("moduleKey");
    }

    private void applyPageAliases(String moduleKey, Map<String, Object> item) {
        if ("module".equals(moduleKey)) {
            item.putIfAbsent("moduleName", item.get("name"));
            item.putIfAbsent("revealOrNo", "0");
            item.putIfAbsent("displayPosition", "1");
        } else if ("headBand".equals(moduleKey)) {
            item.putIfAbsent("deviceName", item.get("hatNumber"));
            item.putIfAbsent("deviceFlashid", item.get("hatNumber"));
            item.putIfAbsent("hatDescription", "本地模拟安全帽");
            item.putIfAbsent("bindRecordList", Collections.emptyList());
        } else if ("systemHat".equals(moduleKey)) {
            item.putIfAbsent("deviceNumber", item.get("hatNumber"));
            item.putIfAbsent("deviceName", item.get("hatNumber"));
            item.putIfAbsent("status", "模拟在线");
        } else if ("space".equals(moduleKey)) {
            item.putIfAbsent("deviceNum", 0);
            item.putIfAbsent("alarmFrequency", 0);
            item.putIfAbsent("latitudes", Collections.emptyList());
            item.putIfAbsent("deviceRelations", Collections.emptyList());
        }
    }

    private boolean matches(Map<String, Object> item, Map<String, String> filters) {
        if (filters == null) {
            return true;
        }
        return filters.entrySet().stream()
                .filter(entry -> !PAGE_FILTERS.contains(entry.getKey()))
                .filter(entry -> !isBlank(entry.getValue()))
                .allMatch(entry -> String.valueOf(item.getOrDefault(entry.getKey(), ""))
                        .toLowerCase().contains(entry.getValue().toLowerCase()));
    }

    private void validateModule(String moduleKey) {
        if (!ALLOWED_MODULES.contains(moduleKey)) {
            throw new ServiceException("不支持的演示模块：" + moduleKey);
        }
    }

    private String asText(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
