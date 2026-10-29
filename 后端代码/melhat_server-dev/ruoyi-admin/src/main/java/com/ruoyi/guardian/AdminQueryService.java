package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class AdminQueryService {
    private static final List<String> READ_ENTITIES = Arrays.asList("people", "organizations", "sites", "dutyShifts", "accounts", "roles");
    private static final List<String> DELEGATE_ROLES = Arrays.asList("viewer", "people-editor", "asset-operator", "mobile-user");
    private final AdminLedgerStore ledger;
    private final GuardianStore guardian;
    private final ObjectProvider<AdminMaintenanceService> maintenance;
    @org.springframework.beans.factory.annotation.Value("${melhat.demo-mode:false}") private boolean demoMode;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableBusinessPolicy businessPolicy;

    public AdminQueryService(AdminLedgerStore ledger, GuardianStore guardian, ObjectProvider<AdminMaintenanceService> maintenance) {
        this.ledger = ledger;
        this.guardian = guardian;
        this.maintenance = maintenance;
    }

    public Map<String, Object> query(String accountId, String kind, JSONObject input) {
        JSONObject state = GuardianDemoData.operationalLedger(ledger.read(), demoMode);
        if (state == null) throw fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        if(businessPolicy!=null)businessPolicy.decorate(state,true);
        JSONObject actor = account(state, accountId);
        if (actor == null) throw fail(401, "IDENTITY_INVALID", "请先登录");
        if (input == null) input = new JSONObject();
        if ("context".equals(kind)) return context(state, actor);
        if ("devices".equals(kind) || "device".equals(kind) || "deviceOptions".equals(kind) || "deviceHistory".equals(kind) || "deviceChanges".equals(kind) || "deviceEvents".equals(kind)) return devices(state, actor, kind, input);
        if ("master".equals(kind) || "person".equals(kind) || "record".equals(kind) || "options".equals(kind) || "impacts".equals(kind)) return master(state, actor, kind, input);
        throw fail(400, "UNKNOWN_QUERY", "未实现此查询");
    }

    private Map<String, Object> devices(JSONObject state, JSONObject actor, String kind, JSONObject input) {
        String siteId = requiredSite(state, actor, input, "assets:read");
        Telemetry telemetry = new Telemetry();
        if ("deviceOptions".equals(kind)) {
            Map<String, Object> body = new LinkedHashMap<String, Object>();
            body.put("availability", "AVAILABLE");
            body.put("models", models());
            return body;
        }
        List<JSONObject> visible = new ArrayList<JSONObject>();
        for (JSONObject device : array(state, "devices")) {
            if (siteId.equals(device.getString("siteId")) && can(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) visible.add(device);
        }
        if ("devices".equals(kind)) {
            String keyword = input.getString("keyword");
            if (keyword != null && keyword.length() > 100) throw fail(400, "INVALID_KEYWORD", "关键词最多100字");
            for (String key : Arrays.asList("type", "lifecycle", "relation", "communication")) {
                String value = input.getString(key);
                if (value != null && !value.isEmpty() && !allowedFilter(key, value)) throw fail(400, "INVALID_FILTER", "设备筛选参数无效");
            }
            List<JSONObject> rows = new ArrayList<JSONObject>();
            String needle = keyword == null ? "" : keyword.trim().toLowerCase();
            for (JSONObject device : visible) {
                JSONObject row = project(state, actor, device, telemetry);
                if(input.getString("source") != null && !input.getString("source").isEmpty() && !input.getString("source").equals(row.getString("source")))continue;
                if (!matches(input, row)) continue;
                String hay = (row.getString("code") + " " + row.getString("sn") + " " + row.getString("deviceNumber")).toLowerCase();
                if (!needle.isEmpty() && !hay.contains(needle)) continue;
                rows.add(row);
            }
            JSONObject paging = new JSONObject();
            paging.put("pageNum", input.get("pageNum"));
            paging.put("pageSize", input.get("pageSize"));
            paging.put("keyword", "");
            Map<String, Object> body = new LinkedHashMap<String, Object>();
            body.put("availability", "AVAILABLE");
            rows.sort((left,right)->Boolean.compare("PLATFORM".equals(right.getString("source")),"PLATFORM".equals(left.getString("source"))));
            body.put("platformSync",state.getJSONObject("platformSync")==null?null:state.getJSONObject("platformSync").get(siteId));
            body.putAll(page(rows, paging, false));
            return body;
        }
        JSONObject device = null;
        for (JSONObject item : visible) if (input.getString("id") != null && input.getString("id").equals(item.getString("id"))) device = item;
        if (device == null) throw fail(404, "OBJECT_NOT_FOUND", "设备不存在或不可见");
        if ("device".equals(kind)) return project(state, actor, device, telemetry);
        if ("deviceEvents".equals(kind)) return deviceEvents(state, actor, device, input);
        if ("deviceChanges".equals(kind)) {
            if (!can(state, actor, "audit:read", device.getString("siteId"), device.getString("areaId"))) throw fail(403, "SECTION_DENIED", "没有资料变更审计权限");
            List<JSONObject> rows = new ArrayList<JSONObject>();
            List<JSONObject> audit = array(state, "audit");
            for (int i = audit.size() - 1; i >= 0; i--) {
                JSONObject row = audit.get(i);
                if (device.getString("id").equals(row.getString("objectId")) && device.getString("siteId").equals(row.getString("siteId"))) rows.add(row);
            }
            Map<String, Object> body = new LinkedHashMap<String, Object>();
            body.put("availability", "AVAILABLE");
            body.putAll(page(rows, input, false));
            return body;
        }
        if ("deviceHistory".equals(kind)) {
            List<JSONObject> rows = new ArrayList<JSONObject>();
            List<JSONObject> history = array(state, "history");
            for (int i = history.size() - 1; i >= 0; i--) {
                JSONObject row = history.get(i);
                if (device.getString("id").equals(row.getString("deviceId")) && siteId.equals(row.getString("siteId"))) rows.add(row);
            }
            Map<String, Object> body = new LinkedHashMap<String, Object>();
            body.put("availability", "AVAILABLE");
            body.putAll(page(rows, input, false));
            return body;
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.putAll(page(new ArrayList<JSONObject>(), input, false));
        return body;
    }

    /** Read the same durable device events as the portal, with independent admin authorization. */
    private Map<String, Object> deviceEvents(JSONObject state, JSONObject actor, JSONObject device, JSONObject input) {
        String siteId = device.getString("siteId");
        if (!can(state, actor, "events:read", siteId, device.getString("areaId")))
            throw fail(403, "SECTION_DENIED", "没有此设备的报警查看权限");
        String deviceId = device.getString("portalDeviceId");
        boolean helmet = "DIRECT_HELMET".equals(device.getString("source")) && "HELMET".equals(device.getString("type"));
        boolean belt = "DIRECT_BELT".equals(device.getString("source")) && "BELT".equals(device.getString("type"));
        if ((!helmet && !belt)
                || deviceId == null || deviceId.isEmpty() || !deviceId.equals(device.getString("deviceNumber")))
            throw fail(400, "UNSUPPORTED_DEVICE", "此设备尚未接入真实设备报警查询");
        String protocol = helmet ? "direct-helmet" : "direct-belt";
        // Validate pagination before reading the shared business snapshot.
        page(new ArrayList<JSONObject>(), input, false);
        JSONObject snapshot = guardian.snapshot();
        if (snapshot == null) throw fail(503, "SOURCE_FAILURE", "设备报警数据暂不可用");
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject event : array(snapshot, "events")) {
            if (!deviceId.equals(event.getString("deviceId")) || !siteId.equals(event.getString("siteId"))
                    || !deviceEventSource(event, deviceId, protocol)) continue;
            String areaId = event.getString("areaId");
            if (areaId == null) {
                JSONObject person = WearableModel.person(state, event.getString("personId"));
                if (person != null) areaId = person.getString("areaId");
            }
            if (!can(state, actor, "events:read", siteId, areaId)) continue;
            JSONObject row = new JSONObject();
            // The summary intentionally excludes location, personnel details, uploads and private notes.
            for (String field : Arrays.asList("id", "deviceId", "protocol", "rawAlarmType", "title", "type",
                    "status", "date", "time", "createdAt", "updatedAt", "source"))
                if (event.containsKey(field)) row.put(field, event.get(field));
            row.put("protocol", protocol);
            row.put("sourceEventId", event.getString("id"));
            row.put("alarmCode", event.getString("rawAlarmType"));
            row.put("alarmName", event.getString("title") == null ? (helmet ? "安全帽设备告警" : "安全带设备告警") : event.getString("title"));
            rows.add(row);
        }
        rows.sort((left, right) -> {
            String leftTime = left.getString("createdAt"), rightTime = right.getString("createdAt");
            if (leftTime == null) leftTime = String.valueOf(left.get("date")) + String.valueOf(left.get("time"));
            if (rightTime == null) rightTime = String.valueOf(right.get("date")) + String.valueOf(right.get("time"));
            int compared = rightTime.compareTo(leftTime);
            return compared != 0 ? compared : String.valueOf(right.get("id")).compareTo(String.valueOf(left.get("id")));
        });
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.putAll(page(rows, input, false));
        return body;
    }

    private static boolean deviceEventSource(JSONObject event, String deviceId, String protocol) {
        if (!"device".equals(event.getString("source")) || event.getBooleanValue("demo")) return false;
        String recordedProtocol = event.getString("protocol");
        if (recordedProtocol != null && !recordedProtocol.isEmpty()) return protocol.equals(recordedProtocol);
        if (!"direct-helmet".equals(protocol)) return false;
        // Before durable helmet envelopes, GuardianIngest.directAlarm/sos wrote these
        // device-specific deduplication keys without a protocol. Missing protocol alone
        // is never sufficient evidence: manual, seed and unrelated events stay excluded.
        String sourceKey = event.getString("sourceKey");
        if (sourceKey == null) return false;
        String prefix;
        if ("人员求助".equals(event.getString("type"))) prefix = deviceId + ":sos:";
        else if ("设备通信".equals(event.getString("type")) && event.getString("rawAlarmType") != null)
            prefix = deviceId + ":alarm:" + event.getString("rawAlarmType") + ":";
        else return false;
        if (!sourceKey.startsWith(prefix)) return false;
        String sourceTime = sourceKey.substring(prefix.length());
        try {
            java.time.Instant.parse(sourceTime);
            return true;
        } catch (java.time.format.DateTimeParseException invalidSourceTime) {
            // The original direct ingress stored server-local yyyy-MM-dd HH:mm:ss.
            // Validate its exact shape and calendar date without guessing a time zone.
            if (sourceTime.length() != 19) return false;
            try {
                java.time.LocalDateTime.parse(sourceTime, java.time.format.DateTimeFormatter
                        .ofPattern("uuuu-MM-dd HH:mm:ss").withResolverStyle(java.time.format.ResolverStyle.STRICT));
                return true;
            } catch (java.time.format.DateTimeParseException invalidLegacyTime) {
                return false;
            }
        }
    }

    private Map<String, Object> master(JSONObject state, JSONObject actor, String kind, JSONObject input) {
        if ("options".equals(kind)) return options(state, actor, input);
        String entity = input.getString("entity");
        if ("person".equals(kind)) entity = "people";
        if ("areas".equals(entity)) throw fail(410, "FEATURE_REMOVED", "行政区域功能已取消");
        if (!READ_ENTITIES.contains(entity)) throw fail(400, "INVALID_ENTITY", "不支持的资料类型");
        boolean accessEntity = "accounts".equals(entity) || "roles".equals(entity);
        String permission = accessEntity ? "access:read" : "sites".equals(entity) ? "sites:read" : "dutyShifts".equals(entity) ? "duty:read" : "people".equals(entity) ? "people:read" : "organization:read";
        String siteId = input.getString("siteId");
        if (!system(actor)) {
            if (accessEntity) {
                if (siteId == null || siteId.isEmpty() || !accessHasSite(state, actor, siteId, "access:read")) throw fail(403, "PERMISSION_DENIED", "当前身份没有此工作区权限");
            } else requiredSite(state, actor, input, permission);
        }
        boolean siteWide = "sites".equals(entity) || "roles".equals(entity);
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject row : array(state, entity)) {
            if (!siteWide && (siteId == null || !siteId.equals(row.getString("siteId")))) continue;
            if (canReadMaster(state, actor, entity, row)) {
                if ("people".equals(entity)) {
                    JSONObject view = JSONObject.parseObject(row.toJSONString());
                    PersonDutyStatus.project(view, row);
                    rows.add(view);
                } else rows.add(row);
            }
        }
        if ("person".equals(kind) || "record".equals(kind) || "impacts".equals(kind)) {
            JSONObject row = null;
            for (JSONObject item : rows) if (input.getString("id") != null && input.getString("id").equals(item.getString("id"))) row = item;
            if (row == null) throw fail(404, "OBJECT_NOT_FOUND", "对象不存在或不可见");
            if ("impacts".equals(kind)) {
                Map<String, Object> body = new LinkedHashMap<String, Object>();
                body.put("rows", impacts(state, entity, row, input.getBooleanValue("all")));
                body.put("availability", "AVAILABLE");
                return body;
            }
            JSONObject data = JSONObject.parseObject(row.toJSONString());
            if ("people".equals(entity)) {
                data.put("organizationName", nameOf(state, "organizations", row.getString("organizationId"), "未关联"));
                data.put("equipment", equipment(state, actor, row));
                data.put("slots", personSlots(state, row));
                data.put("accountName", linkedAccountName(state, actor, row));
            }
            return data;
        }
        String status = "organizations".equals(entity) ? null : input.getString("status");
        if (status != null && !status.isEmpty() && !"enabled".equals(status) && !"disabled".equals(status)) throw fail(400, "INVALID_FILTER", "无效状态筛选");
        if (status != null && !status.isEmpty()) {
            boolean enabled = "enabled".equals(status);
            List<JSONObject> filtered = new ArrayList<JSONObject>();
            for (JSONObject row : rows) if (row.getBooleanValue("enabled") == enabled) filtered.add(row);
            rows = filtered;
        }
        if ("people".equals(entity) && input.containsKey("dutyStatus")) {
            Object dutyStatus = input.get("dutyStatus");
            if (!(dutyStatus instanceof String) || !Arrays.asList("", "ON_DUTY", "OFF_DUTY", "UNKNOWN").contains(dutyStatus))
                throw fail(400, "INVALID_FILTER", "无效在岗状态筛选");
            if (!"".equals(dutyStatus)) rows = keep(rows, "dutyStatus", (String) dutyStatus);
        }
        String organizationId = input.getString("organizationId");
        if ("people".equals(entity) && input.containsKey("includeDescendants") && !(input.get("includeDescendants") instanceof Boolean)) throw fail(400, "INVALID_FILTER", "包含下级组织须为布尔值");
        if (organizationId != null && !organizationId.isEmpty()) {
            if ("people".equals(entity) && Boolean.TRUE.equals(input.get("includeDescendants"))) {
                Set<String> organizationIds = descendantOrganizationIds(state, actor, siteId, organizationId);
                List<JSONObject> filtered = new ArrayList<JSONObject>();
                for (JSONObject row : rows) if (organizationIds.contains(row.getString("organizationId"))) filtered.add(row);
                rows = filtered;
            } else rows = keep(rows, "organizationId", organizationId);
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.putAll(page(rows, input, true));
        return body;
    }

    private Set<String> descendantOrganizationIds(JSONObject state, JSONObject actor, String siteId, String rootId) {
        Set<String> localIds = new HashSet<String>();
        List<JSONObject> organizations = array(state, "organizations");
        for (JSONObject organization : organizations) {
            if (siteId != null && siteId.equals(organization.getString("siteId")) && organization.getString("id") != null && canReadMaster(state, actor, "organizations", organization)) localIds.add(organization.getString("id"));
        }
        Set<String> included = new HashSet<String>();
        if (!localIds.contains(rootId)) return included;
        Map<String, List<String>> children = new LinkedHashMap<String, List<String>>();
        for (JSONObject organization : organizations) {
            if (!siteId.equals(organization.getString("siteId")) || !localIds.contains(organization.getString("id")) || !localIds.contains(organization.getString("parentId"))) continue;
            String parentId = organization.getString("parentId");
            if (!children.containsKey(parentId)) children.put(parentId, new ArrayList<String>());
            children.get(parentId).add(organization.getString("id"));
        }
        List<String> pending = new ArrayList<String>();
        included.add(rootId);pending.add(rootId);
        for (int index = 0; index < pending.size(); index++) {
            List<String> descendants = children.get(pending.get(index));
            if (descendants == null) continue;
            for (String id : descendants) if (id != null && included.add(id)) pending.add(id);
        }
        return included;
    }

    private Map<String, Object> options(JSONObject state, JSONObject actor, JSONObject input) {
        Map<String, Object> data = new LinkedHashMap<String, Object>();
        for (String key : Arrays.asList("sites", "organizations", "people", "roles")) {
            List<JSONObject> rows = new ArrayList<JSONObject>();
            for (JSONObject row : array(state, key)) {
                if (!"organizations".equals(key) && !row.getBooleanValue("enabled") && row.containsKey("enabled")) continue;
                if (!"sites".equals(key) && !"roles".equals(key) && input.getString("siteId") != null && !input.getString("siteId").equals(row.getString("siteId"))) continue;
                rows.add(row);
            }
            data.put(key, rows);
        }
        return data;
    }

    private JSONObject project(JSONObject state, JSONObject actor, JSONObject device, Telemetry telemetry) {
        JSONObject copy = JSONObject.parseObject(device.toJSONString());
        JSONObject relation = relationship(state, device);
        JSONObject person = relation.getJSONObject("person");
        copy.put("relation", relation.getString("state"));
        copy.put("person", person == null ? null : personView(person));
        copy.put("personName", person == null ? null : person.getString("name"));
        JSONObject assignment = relation.getJSONObject("assignment");
        copy.put("startedAt", assignment == null ? null : assignment.getString("startedAt"));
        copy.put("assignmentSource", assignment == null || assignment.getString("source") == null ? "INITIAL_SNAPSHOT" : assignment.getString("source"));
        copy.put("modelName", deviceModelName(device));
        copy.put("declaration", declaration(device.getString("type")));
        if ("DIRECT_BELT".equals(device.getString("source")))
            copy.put("declaration", "状态来自安全带实际连接与上报；挂钩及佩戴原始值须按本批固件确认，未确认时不判定安全。");


        copy.put("writable", !"SCRAPPED".equals(device.getString("lifecycle")));
        applyTelemetry(copy, telemetry);
        if(businessPolicy!=null)businessPolicy.decorateDevice(copy);
        return copy;
    }

    private void applyTelemetry(JSONObject device, Telemetry telemetry) {
        if ("DIRECT_HELMET".equals(device.getString("source")) || "DIRECT_BELT".equals(device.getString("source"))) {
            JSONObject remote = telemetry.find(device.getString("deviceNumber"));
            device.put("communicationProtocol", "DIRECT_BELT".equals(device.getString("source")) ? "WEBSOCKET" : "SIP");
            device.put("capabilities", new JSONArray());
            device.put("online", null);
            device.put("communication", "UNKNOWN");
            device.put("freshness", "UNKNOWN");
            if ("DIRECT_HELMET".equals(device.getString("source"))) {
                device.put("batteryFreshness", "UNKNOWN");
                device.put("isWearedFreshness", "UNKNOWN");
            }
            if (remote == null || !device.getString("source").equals(remote.getString("source"))) return;
            for (String key : Arrays.asList("online", "battery", "batteryReportedAt", "batteryFreshness", "freshness", "isWeared", "isWearedReportedAt", "isWearedFreshness", "worn", "latitude", "longitude", "lat", "lng", "locationReportedAt", "locationFreshness", "sourceTime", "capabilities", "hangerAStatus", "hangerBStatus", "relativeAltitude", "relativeAltitudeReportedAt", "relativeAltitudeFreshness", "altitude", "gpsAltitude", "ignoreHookAlarm", "deviceReportedAt", "lastSeenAt", "inUse", "inUseReportedAt", "inUseFreshness", "networkType", "networkTypeReportedAt", "networkTypeFreshness", "networkStrength", "networkStrengthReportedAt", "networkStrengthFreshness", "hookState", "hookAEngaged", "hookBEngaged", "wearMappingConfirmed", "hookMappingConfirmed", "telemetryReportedAt", "telemetryFreshness","mediaAvailable","voiceAvailable","broadcastAvailable","mediaStatus","mediaVerification")) {
                if (remote.containsKey(key)) device.put(key, remote.get(key));
            }
            if (device.get("sourceTime") == null) device.put("sourceTime", remote.get("lastSeenAt") != null ? remote.get("lastSeenAt") : remote.get("telemetryReportedAt") != null ? remote.get("telemetryReportedAt") : remote.get("updated"));
            Boolean online = remote.getBoolean("online");
            device.put("communication", online == null ? "UNKNOWN" : online ? "ONLINE" : "OFFLINE");
            if ("DIRECT_BELT".equals(device.getString("source")) && !Boolean.TRUE.equals(online)
                    && device.get("sourceTime") == null) device.put("communication", "NOT_CONNECTED");
            return;
        }
        if ("PLATFORM".equals(device.getString("source"))) {
            try { if(java.time.Instant.parse(device.getString("sourceTime")).isBefore(java.time.Instant.now().minusSeconds(300))) {
                device.put("communication","UNKNOWN");device.put("freshness","STALE");
            }} catch(Exception error) { device.put("communication","UNKNOWN"); }
            return;
        }
        JSONObject remote = telemetry.find(device.getString("portalDeviceId") != null ? device.getString("portalDeviceId") : device.getString("code"));
        if (remote == null) remote = telemetry.find(device.getString("id"));
        if (remote == null || !remote.containsKey("online")) return;
        device.put("communication", remote.getBooleanValue("online") ? "ONLINE" : "OFFLINE");
        device.put("battery", remote.get("battery"));
        device.put("freshness", "CURRENT");
        if (remote.getString("updated") != null) device.put("sourceTime", remote.getString("updated"));
    }

    /** One lazy snapshot per query; never reuse telemetry across requests or users. */
    private final class Telemetry {
        private Map<String, JSONObject> devices;
        JSONObject find(String id) {
            if (id == null) return null;
            if (devices == null) {
                devices = new LinkedHashMap<String, JSONObject>();
                JSONObject snapshot = guardian.snapshot();
                if (snapshot != null) for (JSONObject device : array(snapshot, "devices")) devices.putIfAbsent(device.getString("id"), device);
            }
            return devices.get(id);
        }
    }

    private JSONObject relationship(JSONObject state, JSONObject device) {
        List<JSONObject> links = new ArrayList<JSONObject>();
        for (JSONObject assignment : array(state, "assignments")) {
            if (assignment.getBooleanValue("active") && device.getString("id").equals(assignment.getString("deviceId"))) links.add(assignment);
        }
        JSONObject result = new JSONObject();
        if ("CONFLICT".equals(device.getString("relation")) || links.size() > 1) return relation("CONFLICT", null, null);
        if ("UNKNOWN".equals(device.getString("relation"))) return relation("UNKNOWN", null, null);
        if ("UNASSIGNED".equals(device.getString("relation")) && links.isEmpty() && !"IN_USE".equals(device.getString("lifecycle"))) return relation("UNASSIGNED", null, null);
        JSONObject person = links.size() == 1 ? find(state, "people", links.get(0).getString("personId")) : null;
        if (person != null && !device.getString("siteId").equals(person.getString("siteId"))) person = null;
        int sameType = 0;
        if (person != null) {
            for (JSONObject assignment : array(state, "assignments")) {
                if (!assignment.getBooleanValue("active") || !person.getString("id").equals(assignment.getString("personId"))) continue;
                JSONObject other = find(state, "devices", assignment.getString("deviceId"));
                if (other != null && device.getString("type").equals(other.getString("type"))) sameType++;
            }
        }
        if ("ASSIGNED".equals(device.getString("relation")) && "IN_USE".equals(device.getString("lifecycle")) && person != null && sameType == 1) return relation("ASSIGNED", person, links.get(0));
        return relation("CONFLICT", null, null);
    }

    private boolean available(JSONObject state, JSONObject device) {
        if (!"STOCK".equals(device.getString("lifecycle")) || !"UNASSIGNED".equals(relationship(state, device).getString("state"))) return false;
        for (JSONObject assignment : array(state, "assignments")) if (assignment.getBooleanValue("active") && device.getString("id").equals(assignment.getString("deviceId"))) return false;
        for (JSONObject order : array(state, "maintenanceOrders")) if (device.getString("id").equals(order.getString("deviceId")) && "OPEN".equals(order.getString("status"))) return false;
        return true;
    }

    private List<JSONObject> equipment(JSONObject state, JSONObject actor, JSONObject person) {
        List<JSONObject> rows = new ArrayList<JSONObject>();
        Telemetry telemetry = new Telemetry();
        for (JSONObject device : array(state, "devices")) {
            boolean open = false;
            for (JSONObject assignment : array(state, "assignments")) {
                if (assignment.getBooleanValue("active") && person.getString("id").equals(assignment.getString("personId")) && device.getString("id").equals(assignment.getString("deviceId"))) open = true;
            }
            if (open) rows.add(project(state, actor, device, telemetry));
        }
        return rows;
    }

    private List<Map<String, Object>> impacts(JSONObject state, String entity, JSONObject row, boolean all) {
        List<Map<String, Object>> results = new ArrayList<Map<String, Object>>();
        if ("roles".equals(entity) && all) {
            for (JSONObject account : array(state, "accounts")) {
                JSONArray roleIds = account.getJSONArray("roleIds");
                if (roleIds != null && roleIds.contains(row.getString("id"))) results.add(impact(account.getString("id"), account.getString("name"), "绑定账号（请先调整账号角色）"));
            }
        }
        if ("accounts".equals(entity) && all) {
            for (JSONObject order : array(state, "maintenanceOrders")) {
                if (row.getString("id").equals(order.getString("handlerId")) && "OPEN".equals(order.getString("status"))) {
                    results.add(impact(order.getString("id"), order.getString("code") == null ? order.getString("id") : order.getString("code"), "未完成维修工单"));
                }
            }
        }
        if ("people".equals(entity)) {
            for (JSONObject assignment : array(state, "assignments")) if (assignment.getBooleanValue("active") && row.getString("id").equals(assignment.getString("personId"))) results.add(impact(assignment.getString("id"), assignment.getString("id"), "有效领用关系（请到发放回收页面归还或核实）"));
            for (JSONObject shift : array(state, "dutyShifts")) {
                JSONArray members = shift.getJSONArray("personIds");
                if ((!all && !shift.getBooleanValue("enabled")) || members == null || !members.contains(row.getString("id"))) continue;
                if (all) { results.add(impact(shift.getString("id"), shift.getString("name"), "名册成员引用"));continue; }
                String ends = shift.getString("endsAt");
                try {
                    if (ends != null && java.time.Instant.parse(ends).isAfter(java.time.Instant.now())) results.add(impact(shift.getString("id"), shift.getString("name"), "当前或未来名册"));
                } catch (RuntimeException ignored) { /* 无法解析的班次不当作活动引用 */ }
            }
            if (all) {
                for (JSONObject group : array(state, "groups")) if ((group.getJSONArray("personIds") != null && group.getJSONArray("personIds").contains(row.getString("id"))) || row.getString("id").equals(group.getString("leaderId"))) results.add(impact(group.getString("id"), group.getString("name"), "协助组成员（A5维护）"));
                for (JSONObject account : array(state, "accounts")) if (row.getString("id").equals(account.getString("personId")) || account.getString("id").equals(row.getString("accountId"))) results.add(impact(account.getString("id"), account.getString("name"), "绑定账号（请先解除人员关联）"));
                for (JSONObject device : array(state, "devices")) if (row.getString("id").equals(device.getString("personId"))) results.add(impact(device.getString("id"), device.getString("name"), "设备人员关联（请先解除关联）"));
            }
            JSONObject snapshot = guardian.snapshot();
            String portalId = row.getString("portalId");
            if (portalId == null || portalId.isEmpty()) portalId = row.getString("id");
            if (snapshot != null && portalId != null) {
                for (JSONObject work : array(snapshot, "works")) {
                    if (!guardian.isOperational(work) || "已结束".equals(work.getString("status"))) continue;
                    JSONArray members = work.getJSONArray("members");
                    if (members != null && members.contains(portalId)) results.add(impact(work.getString("id"), work.getString("name"), "未结束作业"));
                }
            }
        }
        if ("areas".equals(entity)) {
            for (JSONObject device : array(state, "devices")) if (row.getString("id").equals(device.getString("areaId"))) results.add(impact(device.getString("id"), device.getString("code"), "设备引用"));
            for (JSONObject person : array(state, "people")) if (row.getString("id").equals(person.getString("areaId")) && (all || person.getBooleanValue("enabled"))) results.add(impact(person.getString("id"), person.getString("name"), "人员引用"));
        }
        if ("organizations".equals(entity)) {
            for (JSONObject child : array(state, "organizations")) if (row.getString("id").equals(child.getString("parentId"))) results.add(impact(child.getString("id"), child.getString("name"), "下级组织引用"));
            for (JSONObject person : array(state, "people")) if (row.getString("id").equals(person.getString("organizationId"))) results.add(impact(person.getString("id"), person.getString("name"), "人员引用"));
        }
        if ("sites".equals(entity)) {
            for (JSONObject organization : array(state, "organizations")) if (row.getString("id").equals(organization.getString("siteId"))) results.add(impact(organization.getString("id"), organization.getString("name"), "组织引用"));
        }
        return results;
    }

    private Map<String, Object> page(List<JSONObject> rows, JSONObject input, boolean useKeyword) {
        int pageNum = input.getIntValue("pageNum");
        int pageSize = input.getIntValue("pageSize");
        if (pageNum == 0) pageNum = 1;
        if (pageSize == 0) pageSize = 20;
        if (pageNum < 1 || pageSize < 1 || pageSize > 100) throw fail(400, "INVALID_PAGE", "分页参数无效");
        String keyword = input.getString("keyword");
        if (keyword == null) keyword = "";
        if (keyword.length() > 100) throw fail(400, "INVALID_KEYWORD", "关键词最多100字");
        List<JSONObject> filtered = rows;
        if (useKeyword && !keyword.trim().isEmpty()) {
            String needle = keyword.trim().toLowerCase();
            filtered = new ArrayList<JSONObject>();
            for (JSONObject row : rows) {
                String hay = ((row.getString("code") == null ? "" : row.getString("code")) + " " + (row.getString("loginName") == null ? "" : row.getString("loginName")) + " " + (row.getString("personName") == null ? "" : row.getString("personName")) + " " + (row.getString("name") == null ? "" : row.getString("name"))).toLowerCase();
                if (hay.contains(needle)) filtered.add(row);
            }
        }
        long from = (long) (pageNum - 1) * pageSize;
        List<JSONObject> slice = from >= filtered.size() ? new ArrayList<JSONObject>() : filtered.subList((int) from, (int) Math.min(from + pageSize, filtered.size()));
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("rows", new ArrayList<JSONObject>(slice));
        body.put("total", filtered.size());
        body.put("pageNum", pageNum);
        body.put("pageSize", pageSize);
        return body;
    }

    private String requiredSite(JSONObject state, JSONObject actor, JSONObject input, String operation) {
        String siteId = input.getString("siteId");
        if (siteId == null || siteId.isEmpty()) throw fail(400, "SITE_REQUIRED", "请选择厂站");
        boolean enabled = false;
        for (JSONObject site : array(state, "sites")) if (siteId.equals(site.getString("id")) && site.getBooleanValue("enabled")) enabled = true;
        if (!enabled || !(system(actor) || accessHasSite(state, actor, siteId, operation))) throw fail(403, "PERMISSION_DENIED", "当前身份无此查询权限");
        return siteId;
    }

    private boolean can(JSONObject state, JSONObject actor, String operation, String siteId, String areaId) {
        // Administrative areas are retired; authorization retains operation and site boundaries.
        return system(actor) || scopedCan(state, actor, operation, siteId, areaId);
    }

    private String linkedAccountName(JSONObject state, JSONObject actor, JSONObject person) {
        for (JSONObject account : array(state, "accounts")) {
            boolean linked = account.getString("id") != null && account.getString("id").equals(person.getString("accountId"))
                    || person.getString("id") != null && person.getString("id").equals(account.getString("personId"));
            if (linked && canReadMaster(state, actor, "accounts", account)) return account.getString("name");
        }
        return null;
    }

    private boolean canReadMaster(JSONObject state, JSONObject actor, String entity, JSONObject row) {
        if ("accounts".equals(entity)) return system(actor) || actor.getString("id").equals(row.getString("id")) || accountManageable(state, actor, row);
        if ("roles".equals(entity)) return roleVisible(state, actor, row);
        if ("sites".equals(entity)) return system(actor) || can(state, actor, "sites:read", row.getString("id"), null);
        if ("dutyShifts".equals(entity)) return can(state, actor, "duty:read", row.getString("siteId"), null);
        String operation = "people".equals(entity) ? "people:read" : "organization:read";
        String areaId = "areas".equals(entity) ? row.getString("id") : row.getString("areaId");
        return can(state, actor, operation, row.getString("siteId"), areaId);
    }

    private Map<String, Object> context(JSONObject state, JSONObject actor) {
        List<JSONObject> sites = new ArrayList<JSONObject>();
        for (JSONObject site : array(state, "sites")) {
            if (accessHasSite(state, actor, site.getString("id"), "overview:read")) sites.add(JSONObject.parseObject(site.toJSONString()));
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("sites", sites);
        body.put("identity", JSONObject.parseObject(actor.toJSONString()));
        return body;
    }

    private boolean roleVisible(JSONObject state, JSONObject actor, JSONObject role) {
        if (system(actor)) return true;
        if (!role.getBooleanValue("builtin")) return false;
        JSONArray grants = role.getJSONArray("grants");
        if (grants == null) return false;
        for (int i = 0; i < grants.size(); i++) {
            JSONArray sites = grants.getJSONObject(i).getJSONArray("siteIds");
            if (sites == null) continue;
            for (int s = 0; s < sites.size(); s++) if (accessHasSite(state, actor, sites.getString(s), "access:read")) return true;
        }
        return false;
    }

    private boolean accountManageable(JSONObject state, JSONObject actor, JSONObject account) {
        if (system(actor)) return !"demo-system".equals(account.getString("id"));
        if (account.getBooleanValue("builtin") || actor.getString("id").equals(account.getString("id"))) return false;
        if (!scopedCan(state, actor, "accounts:write", account.getString("siteId"), account.getString("areaId"))) return false;
        JSONArray roleIds = account.getJSONArray("roleIds");
        if (roleIds != null) for (int i = 0; i < roleIds.size(); i++) if (!DELEGATE_ROLES.contains(roleIds.getString(i))) return false;
        for (ScopeGrant grant : grantsOf(state, account)) {
            if (grant.siteIds == null || grant.operations == null) return false;
            for (int s = 0; s < grant.siteIds.size(); s++) {
                String siteId = grant.siteIds.getString(s);
                for (int o = 0; o < grant.operations.size(); o++) {
                    String operation = grant.operations.getString(o);
                    if (!scopedCan(state, actor, operation, siteId, null)) return false;
                }
            }
        }
        return true;
    }

    private boolean accessHasSite(JSONObject state, JSONObject actor, String siteId, String operation) {
        JSONObject site = find(state, "sites", siteId);
        if (site == null || !site.getBooleanValue("enabled")) return false;
        for (ScopeGrant grant : grantsOf(state, actor)) {
            if (grant.siteIds == null || !grant.siteIds.contains(siteId) || grant.operations == null) continue;
            if (!(grant.operations.contains("*") || grant.operations.contains(operation))) continue;
            return true;
        }
        return false;
    }

    private boolean scopedCan(JSONObject state, JSONObject actor, String operation, String siteId, String areaId) {
        JSONObject site = find(state, "sites", siteId);
        if (site != null && !site.getBooleanValue("enabled") && !"sites:write".equals(operation)) return false;
        for (ScopeGrant grant : grantsOf(state, actor)) {
            if (grant.operations == null || grant.siteIds == null || !grant.siteIds.contains(siteId)) continue;
            if (!(grant.operations.contains("*") || grant.operations.contains(operation))) continue;
            return true;
        }
        return false;
    }

    private List<ScopeGrant> grantsOf(JSONObject state, JSONObject actor) {
        List<ScopeGrant> grants = new ArrayList<ScopeGrant>();
        if (actor == null || !actor.getBooleanValue("enabled")) return grants;
        JSONArray roleIds = actor.getJSONArray("roleIds");
        if (roleIds == null) return grants;
        for (int i = 0; i < roleIds.size(); i++) {
            JSONObject role = find(state, "roles", roleIds.getString(i));
            if (role == null || !role.getBooleanValue("enabled")) continue;
            JSONArray roleGrants = role.getJSONArray("grants");
            if (roleGrants == null) continue;
            for (int g = 0; g < roleGrants.size(); g++) {
                JSONObject grant = roleGrants.getJSONObject(g);
                ScopeGrant item = new ScopeGrant();
                item.operations = grant.getJSONArray("operations");
                item.siteIds = grant.getJSONArray("siteIds");
                grants.add(item);
            }
        }
        return grants;
    }

    private static final class ScopeGrant {
        private JSONArray operations;
        private JSONArray siteIds;
    }

    private boolean system(JSONObject actor) { return actor != null && "demo-system".equals(actor.getString("id")) && actor.getBooleanValue("enabled"); }

    private JSONObject account(JSONObject state, String accountId) {
        if (accountId == null || accountId.trim().isEmpty()) return null;
        for (JSONObject account : array(state, "accounts")) if (accountId.equals(account.getString("id")) && account.getBooleanValue("enabled")) return account;
        return null;
    }

    private static JSONObject relation(String name, JSONObject person, JSONObject assignment) {
        JSONObject result = new JSONObject();
        result.put("state", name);
        result.put("person", person);
        result.put("assignment", assignment);
        return result;
    }

    private static Map<String, String> personView(JSONObject person) {
        Map<String, String> view = new LinkedHashMap<String, String>();
        view.put("id", person.getString("id"));
        view.put("name", person.getString("name"));
        return view;
    }

    private static List<String> openOrders(JSONObject state, String deviceId) {
        List<String> ids = new ArrayList<String>();
        for (JSONObject order : array(state, "maintenanceOrders")) if (deviceId.equals(order.getString("deviceId")) && "OPEN".equals(order.getString("status"))) ids.add(order.getString("id"));
        return ids;
    }

    private static boolean matches(JSONObject input, JSONObject row) {
        for (String key : Arrays.asList("type", "lifecycle", "relation", "communication")) {
            String value = input.getString(key);
            if (value != null && !value.isEmpty() && !value.equals(row.getString(key))) return false;
        }
        return true;
    }

    private static boolean allowedFilter(String key, String value) {
        if ("type".equals(key)) return Arrays.asList("HELMET", "BELT", "WATCH").contains(value);
        if ("lifecycle".equals(key)) return Arrays.asList("STOCK", "IN_USE", "MAINTENANCE", "DISABLED", "SCRAPPED").contains(value);
        if ("relation".equals(key)) return Arrays.asList("UNASSIGNED", "ASSIGNED", "UNKNOWN", "CONFLICT").contains(value);
        return Arrays.asList("NOT_CONNECTED", "ONLINE", "OFFLINE", "UNKNOWN").contains(value);
    }

    private static List<JSONObject> areas(JSONObject state, String siteId, boolean include) {
        List<JSONObject> rows = new ArrayList<JSONObject>();
        if (!include) return rows;
        for (JSONObject area : array(state, "areas")) if (siteId.equals(area.getString("siteId")) && area.getBooleanValue("enabled")) rows.add(area);
        return rows;
    }

    private static List<Map<String, Object>> models() {
        List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
        rows.add(model("demo-helmet-basic", "HELMET", "安全帽"));
        rows.add(model("demo-belt", "BELT", "安全带"));
        rows.add(model("demo-watch", "WATCH", "手表"));
        return rows;
    }

    private static Map<String, Object> model(String id, String type, String name) {
        Map<String, Object> row = new LinkedHashMap<String, Object>();
        row.put("id", id);
        row.put("type", type);
        row.put("name", name);
        row.put("declaration", declaration(type));
        row.put("options", new ArrayList<Object>());
        return row;
    }

    static String deviceModelName(JSONObject device) {
        if (device.containsKey("modelName")) return device.getString("modelName") == null ? "" : device.getString("modelName");
        return modelName(device.getString("type"));
    }

    private static String modelName(String type) {
        if ("HELMET".equals(type)) return "安全帽";
        if ("BELT".equals(type)) return "安全带";
        if ("WATCH".equals(type)) return "手表";
        return "型号待确认";
    }

    private static String declaration(String type) {
        if ("HELMET".equals(type)) return "前台使用视频通道和定位。这里只登记资产，上报接入前通信为未接入。";
        if ("BELT".equals(type)) return "没有设备上报，不记录受力或生命体征。";
        if ("WATCH".equals(type)) return "没有设备上报，不记录心率和血氧。";
        return "待确认";
    }

    private static String nameOf(JSONObject state, String key, String id, String fallback) {
        JSONObject row = find(state, key, id);
        return row == null || row.getString("name") == null ? fallback : row.getString("name");
    }

    private static JSONObject find(JSONObject state, String key, String id) {
        for (JSONObject row : array(state, key)) if (id != null && id.equals(row.getString("id"))) return row;
        return null;
    }

    private static List<JSONObject> keep(List<JSONObject> rows, String key, String value) {
        List<JSONObject> filtered = new ArrayList<JSONObject>();
        for (JSONObject row : rows) if (value.equals(row.getString(key))) filtered.add(row);
        return filtered;
    }

    private static Map<String, Object> impact(String id, String name, String label) {
        Map<String, Object> row = new LinkedHashMap<String, Object>();
        row.put("id", id);
        row.put("name", name);
        row.put("label", label);
        return row;
    }

    private static List<JSONObject> array(JSONObject state, String key) {
        List<JSONObject> rows = new ArrayList<JSONObject>();
        JSONArray list = state.getJSONArray(key);
        if (list == null) return rows;
        for (int i = 0; i < list.size(); i++) {
            JSONObject row = list.getJSONObject(i);
            if (row != null) rows.add(row);
        }
        return rows;
    }

    public void requireRead(JSONObject state, JSONObject actor, JSONObject input) {
        requiredSite(state, actor, input, "assets:read");
    }

    public boolean allows(JSONObject state, JSONObject actor, String operation, String siteId, String areaId) {
        return can(state, actor, operation, siteId, areaId);
    }

    public JSONObject relationshipOf(JSONObject state, JSONObject device) {
        return relationship(state, device);
    }

    public boolean issueAvailable(JSONObject state, JSONObject device) {
        return available(state, device);
    }

    private JSONObject personSlots(JSONObject state, JSONObject person) {
        JSONObject evidence = person.getJSONObject("equipmentEvidence");
        JSONObject slots = new JSONObject();
        for (String type : Arrays.asList("HELMET", "BELT", "WATCH")) {
            int count = 0;
            JSONObject only = null;
            for (JSONObject assignment : array(state, "assignments")) {
                if (!assignment.getBooleanValue("active") || !person.getString("id").equals(assignment.getString("personId"))) continue;
                JSONObject device = find(state, "devices", assignment.getString("deviceId"));
                if (device != null && type.equals(device.getString("type"))) {
                    count++;
                    only = device;
                }
            }
            String status;
            if (count > 1) status = "CONFLICT";
            else if (count == 1) status = "ASSIGNED".equals(relationship(state, only).getString("state")) ? "ASSIGNED" : "CONFLICT";
            else status = evidence != null && "COMPLETE".equals(evidence.getString(type)) ? "UNASSIGNED" : "UNKNOWN";
            slots.put(type, status);
        }
        return slots;
    }

    public static QueryFailed fail(int code, String errorCode, String message) { throw new QueryFailed(code, errorCode, message); }

    public static class QueryFailed extends RuntimeException {
        public final int code;
        public final String errorCode;
        public QueryFailed(int code, String errorCode, String message) {
            super(message);
            this.code = code;
            this.errorCode = errorCode;
        }
    }
}
