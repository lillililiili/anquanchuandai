package com.ruoyi.common.utils;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.type.TypeReference;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class JacksonUtil {

    private static final ObjectMapper objectMapper = new ObjectMapper();
    public static Map<String, Object> toMapByJackson(Object obj) {
        if (obj == null) {
            return Collections.emptyMap();
        }

        // 1. 已经是 Map 类型，直接返回（避免再次转换）
        if (obj instanceof Map) {
            return (Map<String, Object>) obj;
        }

        // 2. 基本数据类型（含包装类）或 String
        if (isPrimitiveOrWrapper(obj.getClass()) || obj instanceof String) {
            Map<String, Object> map = new HashMap<>();
            map.put("value", obj);
            return map;
        }

        // 3. List 类型：包装为 {"list": 原列表}
        if (obj instanceof List) {
            Map<String, Object> map = new HashMap<>();
            map.put("list", obj);
            return map;
        }

        // 4. 其他对象（POJO、数组等）：使用 Jackson 转换为 Map
        try {
            return objectMapper.convertValue(obj, new TypeReference<Map<String, Object>>() {});
        } catch (IllegalArgumentException e) {
            // 转换失败时返回空 Map，并记录日志（可替换为日志框架）
            System.err.println("对象转 Map 失败: " + e.getMessage());
            return Collections.emptyMap();
        }
    }

    /**
     * 判断是否为基本类型或包装类
     */
    private static boolean isPrimitiveOrWrapper(Class<?> clazz) {
        return clazz.isPrimitive() ||
                clazz == Boolean.class ||
                clazz == Byte.class ||
                clazz == Character.class ||
                clazz == Short.class ||
                clazz == Integer.class ||
                clazz == Long.class ||
                clazz == Float.class ||
                clazz == Double.class ||
                clazz == Void.class;
    }

}
