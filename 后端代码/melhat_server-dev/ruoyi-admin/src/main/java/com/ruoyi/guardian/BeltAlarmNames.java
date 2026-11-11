package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Display-only ca_sos names from 对接设备端接口文档250916.pdf, page 16. */
final class BeltAlarmNames {
    private static final Pattern GENERIC = Pattern.compile("^安全带告警(?:[（(]([^）)]+)[）)])?$");
    private static final Map<String, String> NAMES;
    static {
        Map<String, String> names = new LinkedHashMap<>();
        names.put("2", "离开工作区域告警"); names.put("3", "温度告警");
        names.put("4", "跌落（撞击）告警"); names.put("5", "进入禁区告警");
        names.put("6", "静默告警"); names.put("7", "SOS 告警");
        names.put("11", "近电告警"); names.put("12", "登高告警");
        names.put("17", "进入蓝牙信标告警"); names.put("18", "离开蓝牙信标告警");
        NAMES = Collections.unmodifiableMap(names);
    }

    static String title(JSONObject event) {
        String title = event.getString("title");
        if (!"direct-belt".equals(event.getString("protocol")) || title == null) return title;
        Matcher match = GENERIC.matcher(title);
        if (!match.matches()) return title;
        String code = event.getString("rawAlarmType");
        if (code == null) code = match.group(1);
        if (code == null) return title;
        code = code.trim();
        if (match.group(1) != null && !match.group(1).equals(code)) return title;
        return NAMES.getOrDefault(code, title);
    }

    // Call on response copies only; the recorded event and receipt remain unchanged.
    static void present(JSONObject response) {
        if (response.containsKey("title")) response.put("title", title(response));
    }
}
