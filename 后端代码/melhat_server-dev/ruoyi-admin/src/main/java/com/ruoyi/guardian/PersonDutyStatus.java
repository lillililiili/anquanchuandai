package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;

/** Manual attendance is independent from personnel archive and equipment activation. */
final class PersonDutyStatus {
    private PersonDutyStatus() { }

    static String value(JSONObject person) {
        String value = person == null ? null : person.getString("dutyStatus");
        return "ON_DUTY".equals(value) || "OFF_DUTY".equals(value) ? value : "UNKNOWN";
    }

    static void project(JSONObject target, JSONObject person) {
        String status = value(person);
        target.put("dutyStatus", status);
        for (String key : new String[]{"dutyStatusUpdatedAt", "dutyStatusUpdatedBy", "dutyStatusSource"}) {
            if (!"UNKNOWN".equals(status) && person.containsKey(key)) target.put(key, person.get(key));
            else target.remove(key);
        }
    }
}
