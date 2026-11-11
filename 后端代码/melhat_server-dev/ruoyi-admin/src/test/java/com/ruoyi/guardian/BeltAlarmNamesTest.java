package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;

class BeltAlarmNamesTest {
    private JSONObject alarm(String code) {
        return object("protocol", "direct-belt", "rawAlarmType", code, "title", "安全带告警（" + code + "）",
                "type", "设备通信", "status", "待认领", "version", 3);
    }

    @Test void presentsDocumentedTypesWithoutChangingRecordedEvidenceOrWorkflow() {
        for (String[] pair : new String[][]{{"3", "温度告警"}, {"4", "跌落（撞击）告警"}, {"6", "静默告警"}, {"11", "近电告警"}}) {
            JSONObject stored = alarm(pair[0]), original = copy(stored), response = copy(stored);
            BeltAlarmNames.present(response);
            assertEquals(pair[1], response.getString("title"));
            assertEquals(pair[0], response.getString("rawAlarmType"));
            assertEquals("设备通信", response.getString("type"));
            assertEquals("待认领", response.getString("status"));
            assertEquals(3, response.getIntValue("version"));
            assertEquals(original, stored);
        }
    }

    @Test void leavesUnknownCodesOtherProtocolsAndConfiguredNamesIntact() {
        JSONObject unknown = alarm("77"), other = alarm("6"), conflict = alarm("6"), configured = alarm("6");
        other.put("protocol", "other"); conflict.put("rawAlarmType", "3");
        configured.put("title", "安全带防双解告警（6）");
        for (JSONObject event : new JSONObject[]{unknown, other, conflict, configured})
            assertEquals(event.getString("title"), BeltAlarmNames.title(event));
        JSONObject legacy = alarm("6"); legacy.remove("rawAlarmType");
        assertEquals("静默告警", BeltAlarmNames.title(legacy));
    }
}
