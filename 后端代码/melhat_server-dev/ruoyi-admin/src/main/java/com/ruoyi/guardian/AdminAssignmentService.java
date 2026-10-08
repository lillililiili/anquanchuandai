package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;

@Service
public class AdminAssignmentService {
    private static final List<String> QUERIES = Arrays.asList("assignments", "assignmentHistory", "assignmentCandidates", "repairAssignees", "maintenanceSummary");
    private static final List<String> TYPES = Arrays.asList("HELMET", "BELT", "WATCH");
    private static final List<String> COMMAND_KEYS = Arrays.asList("siteId", "personId", "personVersion", "items", "operationId", "acknowledged");
    private static final List<String> ISSUE_KEYS = Arrays.asList("deviceId", "deviceVersion");
    private static final List<String> RETURN_KEYS = Arrays.asList("deviceId", "deviceVersion", "assignmentId", "assignmentVersion", "condition", "reason", "handlerId", "handlerVersion");
    private final AdminLedgerStore ledger;
    private final GuardianStore guardian;
    private final AdminQueryService queries;

    public AdminAssignmentService(AdminLedgerStore ledger, GuardianStore guardian, AdminQueryService queries) {
        this.ledger = ledger;
        this.guardian = guardian;
        this.queries = queries;
    }

    public boolean handlesQuery(String kind) { return QUERIES.contains(kind); }

    public Map<String, Object> query(String accountId, String kind, JSONObject input) {
        JSONObject state = ledger.read();
        if (state == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        JSONObject actor = account(state, accountId);
        if (actor == null) throw AdminQueryService.fail(401, "IDENTITY_INVALID", "请先登录");
        if (input == null) input = new JSONObject();
        queries.requireRead(state, actor, input);
        String type = input.getString("type");
        if (type != null && !type.isEmpty() && !TYPES.contains(type)) throw AdminQueryService.fail(400, "INVALID_FILTER", "设备类型无效");
        String action = input.getString("action");
        if (action != null && !action.isEmpty() && !Arrays.asList("ISSUE", "RETURN").contains(action)) throw AdminQueryService.fail(400, "INVALID_FILTER", "历史动作无效");
        if ("assignmentCandidates".equals(kind)) return candidates(state, actor, input);
        if ("assignments".equals(kind) || "assignmentHistory".equals(kind)) return list(state, actor, kind, input);
        if ("repairAssignees".equals(kind)) return assignees(state, actor, input);
        return summary(state, actor, input);
    }

    public JSONObject execute(String accountId, String type, JSONObject input) {
        RemovedAssetFeatures.requireCommand(type, input);
        if (!"assignments.issue".equals(type) && !"assignments.return".equals(type)) throw AdminQueryService.fail(400, "COMMAND_NOT_AVAILABLE", "不支持此领用操作");
        JSONObject state = ledger.read();
        if (state == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        JSONObject actor = account(state, accountId);
        if (actor == null) throw AdminQueryService.fail(401, "IDENTITY_INVALID", "请先登录");
        if (input == null) input = new JSONObject();
        String operationId = input.getString("operationId");
        if (operationId == null || operationId.trim().isEmpty() || operationId.length() > 100) throw AdminQueryService.fail(400, "OPERATION_REQUIRED", "操作标识无效");
        String key = accountId + "\n" + type + "\n" + operationId;
        JSONObject memory = state.getJSONObject("idempotency");
        if (memory == null) { memory = new JSONObject(); state.put("idempotency", memory); }
        JSONObject previous = memory.getJSONObject(key);
        String fingerprint = input.toJSONString();
        if (previous != null) {
            if (!fingerprint.equals(previous.getString("fingerprint"))) throw AdminQueryService.fail(409, "IDEMPOTENCY_CONFLICT", "相同操作标识不能用于不同内容");
            return previous.getJSONObject("result");
        }
        JSONObject output = apply(state, actor, type, input);
        // The ledger is authoritative. GuardianStore projects this committed data on its next read;
        // a failed DB transaction must never publish a successful issue/return into a second store.
        WearableModel.migrate(state);
        state.put("revision", state.getIntValue("revision") + 1);
        JSONObject envelope = new JSONObject();
        envelope.put("code", 200);
        envelope.put("data", output);
        JSONObject stored = new JSONObject();
        stored.put("fingerprint", fingerprint);
        stored.put("result", envelope);
        memory.put(key, stored);
        ledger.write(state);
        return envelope;
    }

    private JSONObject apply(JSONObject state, JSONObject actor, String type, JSONObject input) {
        boolean issue = "assignments.issue".equals(type);
        queries.requireRead(state, actor, input);
        rejectExtra(input, COMMAND_KEYS, "不允许指定生命周期、时间或经办人");
        if (!Boolean.TRUE.equals(input.getBoolean("acknowledged"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请确认本地办理边界");
        JSONArray items = input.getJSONArray("items");
        if (items == null || items.size() < 1 || items.size() > 3) throw AdminQueryService.fail(400, "INVALID_ITEMS", "请选择1至3件装备");
        JSONObject person = find(state, "people", input.getString("personId"));
        if (person == null || !input.getString("siteId").equals(person.getString("siteId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "人员不存在或不可见");
        if (!queries.allows(state, actor, "assets:write", person.getString("siteId"), person.getString("areaId"))) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "人员及每台设备均须在资产办理授权范围内");
        if (person.getIntValue("version") != input.getIntValue("personVersion")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "人员或关系已变化，请重新读取");
        if (issue && !person.getBooleanValue("enabled")) throw AdminQueryService.fail(409, "ASSIGNMENT_CONFLICT", "停用人员不能新领用");
        List<Prepared> prepared = new ArrayList<Prepared>();
        List<String> seenId = new ArrayList<String>();
        List<String> seenType = new ArrayList<String>();
        for (int i = 0; i < items.size(); i++) {
            JSONObject item = items.getJSONObject(i);
            if (item == null || item.getString("deviceId") == null) throw AdminQueryService.fail(400, "INVALID_ITEMS", "请选择1至3件装备");
            rejectExtra(item, issue ? ISSUE_KEYS : RETURN_KEYS, "不支持的设备办理字段");
            JSONObject device = find(state, "devices", item.getString("deviceId"));
            if (device == null || !input.getString("siteId").equals(device.getString("siteId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "设备不存在或不可见");
            if (!queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "人员及每台设备均须在资产办理授权范围内");
            if (device.getIntValue("version") != item.getIntValue("deviceVersion")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "设备已变化，请重新读取");
            if (!TYPES.contains(device.getString("type")) || seenId.contains(device.getString("id")) || seenType.contains(device.getString("type"))) throw AdminQueryService.fail(409, "ASSIGNMENT_CONFLICT", "设备或类型重复，不能整单办理");
            seenId.add(device.getString("id"));
            seenType.add(device.getString("type"));
            Prepared row = new Prepared();
            row.device = device;
            row.item = item;
            if (issue) {
                if (!"UNASSIGNED".equals(slot(state, person, device.getString("type"))) || !queries.issueAvailable(state, device)) throw AdminQueryService.fail(409, "ASSIGNMENT_CONFLICT", "人员槽位或设备不满足明确可领条件");
            } else {
                JSONObject assignment = find(state, "assignments", item.getString("assignmentId"));
                JSONObject link = queries.relationshipOf(state, device);
                JSONObject linked = link.getJSONObject("person");
                if (assignment == null || !assignment.getBooleanValue("active") || !device.getString("id").equals(assignment.getString("deviceId")) || !person.getString("id").equals(assignment.getString("personId")) || !"ASSIGNED".equals(link.getString("state")) || !"ASSIGNED".equals(slot(state, person, device.getString("type"))) || linked == null || !person.getString("id").equals(linked.getString("id"))) {
                    throw AdminQueryService.fail(409, "ASSIGNMENT_CONFLICT", "有效领用关系不存在、未知或冲突，不能强制归还");
                }
                if (assignment.getIntValue("version") != item.getIntValue("assignmentVersion")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "关系已变化，请重新读取");
                if (openOrder(state, device.getString("id"))) throw AdminQueryService.fail(409, "ASSIGNMENT_CONFLICT", "存在未完成维修单，不能重复建单");
                if (!"GOOD".equals(item.getString("condition")) && !"REPAIR".equals(item.getString("condition"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择完好或需检修");
                if ("REPAIR".equals(item.getString("condition"))) {
                    String reason = item.getString("reason");
                    if (reason == null || reason.trim().isEmpty() || reason.trim().length() > 500) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "需检修必须填写故障说明（最多500字）");
                    JSONObject handler = account(state, item.getString("handlerId"));
                    if (handler == null || !queries.allows(state, handler, "assets:write", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(409, "ASSIGNMENT_CONFLICT", "处理人不存在、已停用或无本设备办理权限");
                    if (handler.getIntValue("version") != item.getIntValue("handlerVersion")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "处理人账号已变化，请重新读取");
                    row.handler = handler;
                }
                row.assignment = assignment;
            }
            prepared.add(row);
        }
        int next = state.getIntValue("nextId");
        String now = new Date().toInstant().toString();
        String batchId = "handling-" + (++next);
        JSONArray history = new JSONArray();
        JSONArray orderIds = new JSONArray();
        for (Prepared row : prepared) {
            JSONObject device = row.device;
            JSONObject item = row.item;
            JSONObject assignment = row.assignment;
            String orderId = null;
            if (issue) {
                assignment = new JSONObject();
                assignment.put("id", "assignment-" + (++next));
                assignment.put("siteId", input.getString("siteId"));
                assignment.put("personId", person.getString("id"));
                assignment.put("deviceId", device.getString("id"));
                assignment.put("active", true);
                assignment.put("startedAt", now);
                assignment.put("endedAt", null);
                assignment.put("version", 1);
                assignment.put("source", "MOCK_OPERATION");
                assignment.put("batchId", batchId);
                state.getJSONArray("assignments").add(assignment);
                device.put("lifecycle", "IN_USE");
                device.put("relation", "ASSIGNED");
            } else {
                assignment.put("active", false);
                assignment.put("endedAt", now);
                assignment.put("version", assignment.getIntValue("version") + 1);
                device.put("relation", "UNASSIGNED");
                device.put("lifecycle", "GOOD".equals(item.getString("condition")) ? "STOCK" : "MAINTENANCE");
                if (row.handler != null) {
                    JSONObject order = new JSONObject();
                    orderId = "repair-" + (++next);
                    order.put("id", orderId);
                    order.put("deviceId", device.getString("id"));
                    order.put("siteId", device.getString("siteId"));
                    order.put("areaId", device.getString("areaId"));
                    order.put("status", "OPEN");
                    order.put("phase", "WAITING");
                    order.put("reason", item.getString("reason").trim());
                    order.put("handlerId", row.handler.getString("id"));
                    order.put("handlerName", row.handler.getString("name"));
                    order.put("createdAt", now);
                    order.put("batchId", batchId);
                    order.put("assignmentId", assignment.getString("id"));
                    order.put("version", 1);
                    order.put("source", "MOCK_RETURN");
                    add(state, "maintenanceOrders", order);
                    orderIds.add(orderId);
                    next = appendRepair(state, next, device, actor, now, order);
                }
            }
            device.put("version", device.getIntValue("version") + 1);
            if (device.getString("code") != null && !device.getString("code").isEmpty()) device.put("portalDeviceId", device.getString("code"));
            JSONObject record = new JSONObject();
            record.put("id", "history-" + (++next));
            record.put("siteId", device.getString("siteId"));
            record.put("areaId", device.getString("areaId"));
            record.put("personAreaId", person.getString("areaId"));
            record.put("batchId", batchId);
            record.put("assignmentId", assignment.getString("id"));
            record.put("action", issue ? "ISSUE" : "RETURN");
            record.put("deviceId", device.getString("id"));
            record.put("deviceCode", device.getString("code"));
            record.put("deviceName", device.getString("name"));
            record.put("type", device.getString("type"));
            record.put("personId", person.getString("id"));
            record.put("personName", person.getString("name"));
            record.put("personCode", person.getString("code"));
            record.put("actorId", actor.getString("id"));
            record.put("actorName", actor.getString("name"));
            record.put("occurredAt", now);
            record.put("startedAt", assignment.getString("startedAt"));
            record.put("condition", issue ? null : item.getString("condition"));
            record.put("maintenanceOrderId", orderId);
            record.put("source", "前端内存本地");
            add(state, "history", record);
            history.add(record);
        }
        state.put("nextId", next);
        person.put("version", person.getIntValue("version") + 1);
        JSONObject output = new JSONObject();
        output.put("batchId", batchId);
        output.put("history", history);
        output.put("maintenanceOrderIds", orderIds);
        return output;
    }

    private int appendRepair(JSONObject state, int next, JSONObject device, JSONObject actor, String now, JSONObject order) {
        JSONObject maintenance = recordShell(state, "maintenanceRecords", ++next, device, actor, now);
        maintenance.put("orderId", order.getString("id"));
        maintenance.put("action", "RETURN_REPAIR");
        maintenance.put("description", order.getString("reason"));
        maintenance.put("handlerName", order.getString("handlerName"));
        maintenance.put("batchId", order.getString("batchId"));
        add(state, "maintenanceRecords", maintenance);
        JSONObject life = recordShell(state, "lifecycleHistory", ++next, device, actor, now);
        life.put("orderId", order.getString("id"));
        life.put("action", "SEND_REPAIR");
        life.put("from", "IN_USE");
        life.put("to", "MAINTENANCE");
        life.put("description", order.getString("reason"));
        life.put("handlerName", order.getString("handlerName"));
        life.put("batchId", order.getString("batchId"));
        add(state, "lifecycleHistory", life);
        return next;
    }

    private static JSONObject recordShell(JSONObject state, String key, int id, JSONObject device, JSONObject actor, String now) {
        JSONObject record = new JSONObject();
        record.put("id", key + "-" + id);
        record.put("siteId", device.getString("siteId"));
        record.put("areaId", device.getString("areaId"));
        record.put("deviceId", device.getString("id"));
        record.put("deviceCode", device.getString("code"));
        record.put("deviceName", device.getString("name"));
        record.put("type", device.getString("type"));
        record.put("actorId", actor.getString("id"));
        record.put("actorName", actor.getString("name"));
        record.put("occurredAt", now);
        record.put("source", "前端内存本地");
        return record;
    }

    public void publish(JSONObject admin) {
        syncPortal(admin);
    }

    private void syncPortal(JSONObject admin) {
        final JSONObject snapshot = guardian.snapshot();
        if (snapshot == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "监护数据尚未保存");
        guardian.update(new GuardianStore.Edit() {
            @Override
            public boolean apply(JSONObject next) {
                GuardianMasterProjection.apply(next, admin);
                  next.put("seq", next.getIntValue("seq") + 1);
                return true;
            }
        });
    }

    private Map<String, Object> candidates(JSONObject state, JSONObject actor, JSONObject input) {
        String resource = input.getString("resource");
        if (!Arrays.asList("people", "devices", "selection").contains(resource)) throw AdminQueryService.fail(400, "INVALID_RESOURCE", "请选择候选资源");
        if ("people".equals(resource)) {
            JSONObject device = null;
            if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty()) {
                device = deviceOnSite(state, input);
            }
            boolean returning = "return".equals(input.getString("purpose"));
            List<JSONObject> rows = new ArrayList<JSONObject>();
            for (JSONObject person : rows(state, "people")) {
                if (!input.getString("siteId").equals(person.getString("siteId"))) continue;
                if (!queries.allows(state, actor, "people:read", person.getString("siteId"), person.getString("areaId"))) continue;
                if (!queries.allows(state, actor, "assets:write", person.getString("siteId"), person.getString("areaId"))) continue;
                if (returning) {
                    if (!returnable(state, actor, person)) continue;
                } else if (!person.getBooleanValue("enabled")) continue;
                if (device != null && (!queries.issueAvailable(state, device) || !"UNASSIGNED".equals(slot(state, person, device.getString("type"))) || !queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId")))) continue;
                JSONObject view = new JSONObject();
                view.put("id", person.getString("id"));
                view.put("name", person.getString("name"));
                view.put("code", person.getString("code"));
                view.put("version", person.getIntValue("version"));
                rows.add(view);
            }
            return paged(rows, input, true);
        }
        JSONObject person = find(state, "people", input.getString("personId"));
        if (person == null || !input.getString("siteId").equals(person.getString("siteId")) || !queries.allows(state, actor, "people:read", person.getString("siteId"), person.getString("areaId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "人员不存在或不可见");
        if ("selection".equals(resource)) {
            Map<String, Object> body = new LinkedHashMap<String, Object>();
            body.put("availability", "AVAILABLE");
            JSONObject view = new JSONObject();
            view.put("id", person.getString("id"));
            view.put("code", person.getString("code"));
            view.put("name", person.getString("name"));
            view.put("version", person.getIntValue("version"));
            view.put("enabled", person.getBooleanValue("enabled"));
            body.put("person", view);
            JSONObject slots = new JSONObject();
            for (String type : TYPES) slots.put(type, slot(state, person, type));
            body.put("slots", slots);
            body.put("current", current(state, actor, input.getString("siteId"), person.getString("id")));
            body.put("writable", queries.allows(state, actor, "assets:write", person.getString("siteId"), person.getString("areaId")));
            return body;
        }
        List<JSONObject> rows = new ArrayList<JSONObject>();
        if (person.getBooleanValue("enabled")) {
            for (JSONObject device : rows(state, "devices")) {
                if (!input.getString("siteId").equals(device.getString("siteId"))) continue;
                if (input.getString("type") != null && !input.getString("type").isEmpty() && !input.getString("type").equals(device.getString("type"))) continue;
                if (!queries.allows(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) continue;
                if (!queries.allows(state, actor, "assets:write", person.getString("siteId"), person.getString("areaId")) || !queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId"))) continue;
                if (!"UNASSIGNED".equals(slot(state, person, device.getString("type"))) || !queries.issueAvailable(state, device)) continue;
                JSONObject view = new JSONObject();
                view.put("id", device.getString("id"));
                view.put("code", device.getString("code"));
                view.put("name", device.getString("name"));
                view.put("type", device.getString("type"));
                view.put("version", device.getIntValue("version"));
                view.put("warnings", warnings(device));
                rows.add(view);
            }
        }
        return paged(rows, input, true);
    }

    private Map<String, Object> assignees(JSONObject state, JSONObject actor, JSONObject input) {
        JSONObject device = deviceOnSite(state, input);
        if (!queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "没有办理权限");
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject account : rows(state, "accounts")) {
            if (!account.getBooleanValue("enabled") || !queries.allows(state, account, "assets:write", device.getString("siteId"), device.getString("areaId"))) continue;
            JSONObject view = new JSONObject();
            view.put("id", account.getString("id"));
            view.put("name", account.getString("name"));
            view.put("version", account.getIntValue("version"));
            rows.add(view);
        }
        return paged(rows, input, true);
    }

    private Map<String, Object> summary(JSONObject state, JSONObject actor, JSONObject input) {
        JSONObject order = find(state, "maintenanceOrders", input.getString("id"));
        if (order == null || !input.getString("siteId").equals(order.getString("siteId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "维修单不存在或不可见");
        JSONObject device = find(state, "devices", order.getString("deviceId"));
        if (device == null || !queries.allows(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "设备不存在或不可见");
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("id", order.getString("id"));
        body.put("deviceId", device.getString("id"));
        body.put("deviceCode", device.getString("code"));
        body.put("reason", order.getString("reason"));
        body.put("handlerName", order.getString("handlerName"));
        body.put("status", order.getString("status"));
        body.put("createdAt", order.getString("createdAt"));
        body.put("batchId", order.getString("batchId"));
        body.put("version", order.getIntValue("version"));
        return body;
    }

    private Map<String, Object> list(JSONObject state, JSONObject actor, String kind, JSONObject input) {
        if (input.getString("personId") != null && !input.getString("personId").isEmpty()) {
            JSONObject person = find(state, "people", input.getString("personId"));
            if (person == null || !input.getString("siteId").equals(person.getString("siteId")) || !queries.allows(state, actor, "people:read", person.getString("siteId"), person.getString("areaId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "人员不存在或不可见");
        }
        if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty()) deviceOnSite(state, input);
        List<JSONObject> rows = "assignments".equals(kind) ? current(state, actor, input.getString("siteId"), null) : history(state, actor, input);
        List<JSONObject> filtered = new ArrayList<JSONObject>();
        String keyword = input.getString("keyword");
        if (keyword != null && keyword.length() > 100) throw AdminQueryService.fail(400, "INVALID_KEYWORD", "关键词最多100字");
        String needle = keyword == null ? "" : keyword.trim().toLowerCase();
        for (JSONObject row : rows) {
            if (input.getString("type") != null && !input.getString("type").isEmpty() && !input.getString("type").equals(row.getString("type"))) continue;
            if (input.getString("personId") != null && !input.getString("personId").isEmpty() && !input.getString("personId").equals(row.getString("personId"))) continue;
            if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty() && !input.getString("deviceId").equals(row.getString("deviceId"))) continue;
            if (input.getString("action") != null && !input.getString("action").isEmpty() && !input.getString("action").equals(row.getString("action"))) continue;
            if (input.getString("batchId") != null && !input.getString("batchId").isEmpty() && !input.getString("batchId").equals(row.getString("batchId"))) continue;
            String hay = text(row, "code") + " " + text(row, "deviceCode") + " " + text(row, "personName") + " " + text(row, "personCode");
            if (!needle.isEmpty() && !hay.toLowerCase().contains(needle)) continue;
            filtered.add(row);
        }
        return paged(filtered, input, false);
    }

    private List<JSONObject> history(JSONObject state, JSONObject actor, JSONObject input) {
        List<JSONObject> rows = new ArrayList<JSONObject>();
        List<JSONObject> history = rows(state, "history");
        for (int i = history.size() - 1; i >= 0; i--) {
            JSONObject row = history.get(i);
            if (!input.getString("siteId").equals(row.getString("siteId"))) continue;
            String areaId = row.getString("areaId");
            if (!queries.allows(state, actor, "assets:read", row.getString("siteId"), areaId)) continue;
            rows.add(row);
        }
        return rows;
    }

    private boolean returnable(JSONObject state, JSONObject actor, JSONObject person) {
        for (JSONObject row : current(state, actor, person.getString("siteId"), person.getString("id"))) {
            if ("ASSIGNED".equals(row.getString("relation")) && row.getBooleanValue("writable")) return true;
        }
        return false;
    }

    private String slot(JSONObject state, JSONObject person, String type) {
        int count = 0;
        JSONObject only = null;
        for (JSONObject assignment : rows(state, "assignments")) {
            if (!assignment.getBooleanValue("active") || !person.getString("id").equals(assignment.getString("personId"))) continue;
            JSONObject device = find(state, "devices", assignment.getString("deviceId"));
            if (device != null && type.equals(device.getString("type"))) {
                count++;
                only = device;
            }
        }
        if (count > 1) return "CONFLICT";
        if (count == 1) return "ASSIGNED".equals(queries.relationshipOf(state, only).getString("state")) ? "ASSIGNED" : "CONFLICT";
        JSONObject evidence = person.getJSONObject("equipmentEvidence");
        return evidence != null && "COMPLETE".equals(evidence.getString(type)) ? "UNASSIGNED" : "UNKNOWN";
    }

    private List<JSONObject> current(JSONObject state, JSONObject actor, String siteId, String personId) {
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject device : rows(state, "devices")) {
            if (!siteId.equals(device.getString("siteId")) || !queries.allows(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) continue;
            JSONObject link = queries.relationshipOf(state, device);
            if ("UNASSIGNED".equals(link.getString("state"))) continue;
            JSONObject person = link.getJSONObject("person");
            if (personId != null && (person == null || !personId.equals(person.getString("id")))) continue;
            if (person != null && !queries.allows(state, actor, "people:read", person.getString("siteId"), person.getString("areaId"))) person = null;
            JSONObject assignment = link.getJSONObject("assignment");
            JSONObject row = new JSONObject();
            row.put("id", assignment == null ? "uncertain-" + device.getString("id") : assignment.getString("id"));
            row.put("deviceId", device.getString("id"));
            row.put("code", device.getString("code"));
            row.put("name", device.getString("name"));
            row.put("type", device.getString("type"));
            row.put("deviceVersion", device.getIntValue("version"));
            row.put("relation", link.getString("state"));
            row.put("personId", person == null ? null : person.getString("id"));
            row.put("personName", person == null ? null : person.getString("name"));
            row.put("personCode", person == null ? null : person.getString("code"));
            row.put("personVersion", person == null ? null : person.getIntValue("version"));
            row.put("version", assignment == null ? null : assignment.getIntValue("version"));
            row.put("startedAt", assignment == null ? null : assignment.getString("startedAt"));
            row.put("source", assignment == null || assignment.getString("source") == null ? "INITIAL_SNAPSHOT" : assignment.getString("source"));
            boolean writable = person != null && queries.allows(state, actor, "assets:write", person.getString("siteId"), person.getString("areaId")) && queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId"));
            row.put("writable", writable);
            row.put("warnings", warnings(device));
            rows.add(row);
        }
        return rows;
    }

    private JSONArray warnings(JSONObject device) {
        JSONArray list = new JSONArray();
        String communication = device.getString("communication");
        String freshness = device.getString("freshness");
        JSONObject remote = snapshotDevice(device);
        if (remote != null && remote.containsKey("online")) {
            communication = remote.getBooleanValue("online") ? "ONLINE" : "OFFLINE";
            freshness = "CURRENT";
        }
        if (!"ONLINE".equals(communication)) list.add("通信离线、未知或未接入");
        if ("STALE".equals(freshness)) list.add("设备数据过期");
        String manufacturer = device.getString("manufacturer");
        String sn = device.getString("sn");
        String modelId = device.getString("modelId");
        if (manufacturer == null || manufacturer.isEmpty() || sn == null || sn.isEmpty() || (modelId != null && modelId.startsWith("unknown-"))) list.add("资料或型号待补充");
        if (!"VERIFIED".equals(device.getString("verification"))) list.add("能力未经过真实验证");
        return list;
    }

    private JSONObject snapshotDevice(JSONObject device) {
        JSONObject snapshot = guardian.snapshot();
        if (snapshot == null) return null;
        String portalId = device.getString("portalDeviceId");
        if (portalId == null || portalId.isEmpty()) portalId = device.getString("code");
        JSONObject remote = find(snapshot, "devices", portalId);
        if (remote == null) remote = find(snapshot, "devices", device.getString("id"));
        return remote;
    }

    private Map<String, Object> paged(List<JSONObject> rows, JSONObject input, boolean useKeyword) {
        int pageNum = input.getIntValue("pageNum");
        int pageSize = input.getIntValue("pageSize");
        if (pageNum == 0) pageNum = 1;
        if (pageSize == 0) pageSize = 20;
        if (pageNum < 1 || pageSize < 1 || pageSize > 100) throw AdminQueryService.fail(400, "INVALID_PAGE", "分页参数无效");
        String keyword = useKeyword ? input.getString("keyword") : "";
        if (keyword == null) keyword = "";
        if (keyword.length() > 100) throw AdminQueryService.fail(400, "INVALID_KEYWORD", "关键词最多100字");
        List<JSONObject> filtered = rows;
        if (useKeyword && !keyword.trim().isEmpty()) {
            String needle = keyword.trim().toLowerCase();
            filtered = new ArrayList<JSONObject>();
            for (JSONObject row : rows) {
                String hay = text(row, "code") + " " + text(row, "loginName") + " " + text(row, "personName") + " " + text(row, "name");
                if (hay.toLowerCase().contains(needle)) filtered.add(row);
            }
        }
        int from = (pageNum - 1) * pageSize;
        List<JSONObject> slice = from >= filtered.size() ? new ArrayList<JSONObject>() : new ArrayList<JSONObject>(filtered.subList(from, Math.min(from + pageSize, filtered.size())));
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.put("rows", slice);
        body.put("total", filtered.size());
        body.put("pageNum", pageNum);
        body.put("pageSize", pageSize);
        return body;
    }

    private static JSONObject activeAssignment(JSONObject state, String deviceId) {
        for (JSONObject assignment : rows(state, "assignments")) {
            if (assignment.getBooleanValue("active") && deviceId.equals(assignment.getString("deviceId"))) return assignment;
        }
        return null;
    }

    private static boolean openOrder(JSONObject state, String deviceId) {
        for (JSONObject order : rows(state, "maintenanceOrders")) {
            if (deviceId.equals(order.getString("deviceId")) && "OPEN".equals(order.getString("status"))) return true;
        }
        return false;
    }

    private static JSONObject deviceOnSite(JSONObject state, JSONObject input) {
        JSONObject device = find(state, "devices", input.getString("deviceId"));
        if (device == null || !input.getString("siteId").equals(device.getString("siteId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "设备不存在或不可见");
        return device;
    }

    private static JSONObject account(JSONObject state, String id) {
        JSONObject account = find(state, "accounts", id);
        return account != null && account.getBooleanValue("enabled") ? account : null;
    }

    private static void rejectExtra(JSONObject object, List<String> allowed, String message) {
        for (String key : object.keySet()) if (!allowed.contains(key)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", message);
    }

    private static void add(JSONObject state, String key, JSONObject row) {
        JSONArray list = state.getJSONArray(key);
        if (list == null) { list = new JSONArray(); state.put(key, list); }
        list.add(row);
    }

    private static String text(JSONObject row, String key) {
        String value = row.getString(key);
        return value == null ? "" : value;
    }

    private static String stamp(Date date) {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        format.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        return format.format(date);
    }

    private static String stamp(String value) {
        if (value == null || value.trim().isEmpty()) return stamp(new Date());
        try { return stamp(Date.from(java.time.Instant.parse(value))); }
        catch (RuntimeException error) { return value; }
    }

    private static JSONObject find(JSONObject state, String key, String id) {
        if (id == null) return null;
        for (JSONObject row : rows(state, key)) if (id.equals(row.getString("id"))) return row;
        return null;
    }

    private static List<JSONObject> rows(JSONObject state, String key) {
        List<JSONObject> list = new ArrayList<JSONObject>();
        JSONArray raw = state.getJSONArray(key);
        if (raw == null) return list;
        for (int i = 0; i < raw.size(); i++) {
            JSONObject row = raw.getJSONObject(i);
            if (row != null) list.add(row);
        }
        return list;
    }

    private static final class Prepared {
        private JSONObject device;
        private JSONObject item;
        private JSONObject assignment;
        private JSONObject handler;
    }
}
