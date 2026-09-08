package com.ruoyi.helmet.service;

import java.util.Map;

/** 为保留的旧页面提供本地演示数据。 */
public interface DemoCompatibilityService {

    Map<String, Object> page(String moduleKey, Map<String, String> filters, int pageNum, int pageSize);

    Map<String, Object> detail(String moduleKey, Long id);

    Long create(String moduleKey, Map<String, Object> payload);

    boolean update(String moduleKey, Long id, Map<String, Object> payload);

    boolean delete(String moduleKey, Long id);
}
