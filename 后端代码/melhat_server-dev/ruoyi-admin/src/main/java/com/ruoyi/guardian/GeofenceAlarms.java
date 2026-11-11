package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import static com.ruoyi.guardian.WearableModel.*;

/** A confirmed geographic crossing and its alarm are saved in the same store update. */
final class GeofenceAlarms {
    private GeofenceAlarms() {}

    static void append(JSONObject state, JSONObject record, JSONObject point, JSONObject device, JSONObject fence) {
        String sourceKey = "geofence:" + JSONArray.of(record.get("fenceId"), record.get("personId"),
                record.get("bindingId"), record.get("locationId")).toJSONString();
        for (Object raw : rows(state, "events")) {
            JSONObject existing = (JSONObject) raw;
            if (sourceKey.equals(existing.getString("sourceKey"))) {
                record.put("eventId", existing.getString("id"));
                return;
            }
        }
        Instant occurred = Instant.parse(record.getString("locationReportedAt"));
        String stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.of("Asia/Shanghai")).format(occurred);
        String id = "GF-" + record.getString("id");
        String direction = record.getString("type");
        String title = direction + "围栏：" + record.getString("fenceName");
        Object site = point.get("siteId") == null ? device.get("siteId") : point.get("siteId");
        Object area = point.get("areaId") == null ? device.get("areaId") : point.get("areaId");
        JSONObject work = WorkBusiness.match(state, record.getString("personId"), record.getString("station"), occurred);
        JSONObject snapshot = object("personId", record.get("personId"), "personName", record.get("personName"),
                "deviceId", record.get("deviceId"), "siteId", site, "station", record.get("station"),
                "deviceNumber", device.get("deviceNumber"), "code", device.get("code"), "sn", device.get("sn"),
                "fenceId", record.get("fenceId"), "fenceName", record.get("fenceName"),
                "fencePoints", JSONArray.parseArray(fence.getJSONArray("points").toJSONString()),
                "workName", work == null ? "待分配" : work.getString("name"));
        JSONObject event = object("id", id, "personId", record.get("personId"), "deviceId", record.get("deviceId"),
                "siteId", site, "areaId", area, "station", record.get("station"), "bindingId", record.get("bindingId"),
                "title", title, "type", "电子围栏", "status", "待认领", "version", 1,
                "source", "PLATFORM_GEOFENCE", "protocol", "platform-geofence", "sourceKey", sourceKey,
                "createdAt", Instant.now().toString(), "occurredAt", occurred.toString(), "date", stamp.substring(0, 10), "time", stamp.substring(11),
                "fenceId", record.get("fenceId"), "fenceName", record.get("fenceName"), "fenceDirection", direction,
                "fenceRecordId", record.get("id"), "locationId", record.get("locationId"), "previousLocationId", record.get("previousLocationId"),
                "previousDeviceId", record.get("previousDeviceId"), "locationLng", record.get("longitude"), "locationLat", record.get("latitude"),
                "coordinateSystem", record.get("coordinateSystem"), "locationQuality", point.get("locationQuality"),
                "accuracyMeters", record.get("accuracyMeters"), "locationSource", point.get("locationSource"),
                "locationReportedAt", occurred.toString(), "locationDescription", record.getString("personName") + "" + title,
                "workId", work == null ? "" : work.getString("id"), "externalStatus", "未关联外部工单", "externalId", "",
                "snapshot", snapshot, "draft", null, "verification", null,
                "timeline", JSONArray.of(object("time", occurred.toString(), "text", record.getString("personName") + "" + title + "，已生成围栏进出告警")));
        WorkBusiness.capture(state, event, work);
        rows(state, "events").add(0, event);
        GuardianEvents.normalize(state);
        record.put("siteId", site);
        record.put("areaId", area);
        record.put("eventId", id);
    }
}
