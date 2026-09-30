package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.util.Arrays;

/** Public business boundary: retain historical records without allowing new maintenance work. */
final class RemovedAssetFeatures {
    static void requireCommand(String type, JSONObject input) {
        if (type != null && (type.startsWith("maintenance.") || Arrays.asList("devices.disable", "devices.restore", "devices.scrap").contains(type))) removed();
        if ("assignments.return".equals(type) && input != null) {
            JSONArray items = input.getJSONArray("items");
            if (items != null) for (int i = 0; i < items.size(); i++) {
                if (!(items.get(i) instanceof java.util.Map)) continue;
                JSONObject item = items.getJSONObject(i);
                if ("REPAIR".equals(item.getString("condition")) || item.containsKey("reason") || item.containsKey("handlerId") || item.containsKey("handlerVersion")) removed();
            }
        }
    }

    static void requireQuery(String kind, JSONObject input) {
        if (kind != null && (kind.startsWith("maintenance") || Arrays.asList("repairAssignees", "deviceLifecycleHistory").contains(kind))) removed();
        if ("details".equals(kind) && input != null && "maintenance".equals(input.getString("metric"))) removed();
    }

    private static void removed() { throw AdminQueryService.fail(410, "FEATURE_REMOVED", "维修与退役功能已移除，请通过厂家或现有资产管理流程处理"); }
}
