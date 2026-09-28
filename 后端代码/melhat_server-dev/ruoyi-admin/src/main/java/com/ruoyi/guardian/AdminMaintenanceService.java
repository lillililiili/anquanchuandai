package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class AdminMaintenanceService {
    private static final List<String> QUERIES = Arrays.asList("maintenanceOrders", "maintenanceOrder", "maintenanceRecords", "deviceLifecycleHistory");
    private static final List<String> COMMANDS = Arrays.asList("maintenance.create", "maintenance.assign", "maintenance.start", "maintenance.inspect", "devices.disable", "devices.restore", "devices.scrap", "maintenance.scrap");
    private static final List<String> PHASES = Arrays.asList("UNASSIGNED", "WAITING", "PROCESSING", "CLOSED");
    private static final List<String> RECORD_ACTIONS = Arrays.asList("CREATED", "RETURN_REPAIR", "ASSIGNED", "STARTED", "FAILED", "PASSED", "UNREPAIRABLE", "SEND_REPAIR", "REPAIRED", "DISABLED", "RESTORED", "SCRAPPED");
    private static final List<String> INPUT_KEYS = Arrays.asList("siteId", "operationId", "deviceId", "deviceVersion", "id", "orderVersion", "reason", "handlerId", "handlerVersion", "repairContent", "inspection", "result", "acknowledged", "codeConfirmation", "secondConfirmed");

    private final AdminLedgerStore ledger;
    private final AdminQueryService queries;
    private final AdminAssignmentService assignments;

    public AdminMaintenanceService(AdminLedgerStore ledger, AdminQueryService queries, AdminAssignmentService assignments) {
        this.ledger = ledger;
        this.queries = queries;
        this.assignments = assignments;
    }

    public boolean handlesQuery(String kind) { return QUERIES.contains(kind); }

    public boolean handles(String type) { return COMMANDS.contains(type); }

    public Map<String, String> deviceButtons(JSONObject state, JSONObject actor, JSONObject device, String relation) {
        Map<String, String> actions = new LinkedHashMap<String, String>();
        for (String type : Arrays.asList("maintenance.create", "devices.disable", "devices.restore", "devices.scrap")) {
            actions.put(type, reason(state, actor, device, relation, type, null));
        }
        return actions;
    }

    public Map<String, Object> query(String accountId, String kind, JSONObject input) {
        JSONObject state = readState();
        JSONObject actor = actor(state, accountId);
        if (input == null) input = new JSONObject();
        queries.requireRead(state, actor, input);
        if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty()) loadDevice(state, actor, input);
        if ("maintenanceOrder".equals(kind)) return project(state, actor, loadOrder(state, actor, input));
        if ("maintenanceOrders".equals(kind)) return orders(state, actor, input);
        if ("maintenanceRecords".equals(kind)) loadOrder(state, actor, input);
        String action = input.getString("action");
        if (action != null && !action.isEmpty() && !RECORD_ACTIONS.contains(action)) throw AdminQueryService.fail(400, "INVALID_FILTER", "记录动作无效");
        String key = "maintenanceRecords".equals(kind) ? "maintenanceRecords" : "lifecycleHistory";
        List<JSONObject> rows = new ArrayList<JSONObject>();
        List<JSONObject> records = rows(state, key);
        for (int i = records.size() - 1; i >= 0; i--) {
            JSONObject record = records.get(i);
            if (!input.getString("siteId").equals(record.getString("siteId"))) continue;
            if ("maintenanceRecords".equals(kind) && !input.getString("id").equals(record.getString("orderId"))) continue;
            if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty() && !input.getString("deviceId").equals(record.getString("deviceId"))) continue;
            if (action != null && !action.isEmpty() && !action.equals(record.getString("action"))) continue;
            JSONObject owned = find(state, "devices", record.getString("deviceId"));
            if (owned == null || !queries.allows(state, actor, "assets:read", owned.getString("siteId"), owned.getString("areaId"))) continue;
            if (!queries.allows(state, actor, "assets:read", record.getString("siteId"), record.getString("areaId"))) continue;
            JSONObject view = JSONObject.parseObject(record.toJSONString());
            view.put("code", record.getString("deviceCode"));
            view.put("name", record.getString("deviceName"));
            rows.add(view);
        }
        return page(rows, input, true);
    }

    public JSONObject execute(String accountId, String type, JSONObject input) {
        if (!handles(type)) throw AdminQueryService.fail(400, "COMMAND_NOT_AVAILABLE", "不支持此运维操作");
        JSONObject state = readState();
        JSONObject actor = actor(state, accountId);
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
        try {
            assignments.publish(state);
        } catch (AdminQueryService.QueryFailed error) {
            throw error;
        } catch (RuntimeException error) {
            throw AdminQueryService.fail(400, "PORTAL_REJECTED", error.getMessage() == null ? "监护数据保存失败" : error.getMessage());
        }
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
        boolean existingOrder = type.startsWith("maintenance.") && !"maintenance.create".equals(type);
        JSONObject order = null;
        JSONObject device;
        if (existingOrder) {
            JSONObject loaded = loadOrder(state, actor, input);
            order = loaded.getJSONObject("order");
            device = loaded.getJSONObject("device");
        } else {
            device = loadDevice(state, actor, input);
        }
        if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty() && !input.getString("deviceId").equals(device.getString("id"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "设备与工单不匹配");
        if (!queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "没有本设备资产办理权限");
        if (Arrays.asList("maintenance.assign", "devices.scrap", "maintenance.scrap").contains(type) && !manager(state, actor, device)) throw AdminQueryService.fail(403, "ADMIN_REQUIRED", "仅授权范围内系统／厂站管理员可办理");
        if (Arrays.asList("maintenance.start", "maintenance.inspect").contains(type) && (order == null || !actor.getString("id").equals(order.getString("handlerId")))) throw AdminQueryService.fail(403, "HANDLER_REQUIRED", "仅当前指定处理人可办理");
        rejectExtra(input);
        if (device.getIntValue("version") != input.getIntValue("deviceVersion") || (order != null && order.getIntValue("version") != input.getIntValue("orderVersion"))) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "设备或工单已变化，请重新读取");
        String blocked = reason(state, actor, device, queries.relationshipOf(state, device).getString("state"), type, order);
        if (!blocked.isEmpty()) throw AdminQueryService.fail(409, "MAINTENANCE_CONFLICT", blocked);
        String previous = device.getString("lifecycle");
        String lifeAction = null;
        String description = "";
        String inspection = null;
        if ("devices.scrap".equals(type) || "maintenance.scrap".equals(type)) {
            description = text(input, "reason");
            if (input.getString("codeConfirmation") == null || !input.getString("codeConfirmation").trim().equals(device.getString("code"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请完整复输当前设备编号，大小写必须一致");
            if (!Boolean.TRUE.equals(input.getBoolean("secondConfirmed"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请完成报废二次确认");
            if ("maintenance.scrap".equals(type)) inspection = text(input, "inspection");
            device.put("lifecycle", "SCRAPPED");
            lifeAction = "SCRAPPED";
            if (order != null) {
                order.put("status", "CLOSED");
                order.put("phase", "CLOSED");
                order.put("outcome", "UNREPAIRABLE_SCRAPPED");
                order.put("closedAt", now());
                add(state, "maintenanceRecords", record(state, "maintenanceRecords", device, actor, fields(order.getString("id"), "UNREPAIRABLE", description, inspection, order.getString("handlerName"), null, null, null)));
            }
        } else if ("maintenance.create".equals(type)) {
            description = text(input, "reason");
            JSONObject handler = handler(state, device, input);
            order = new JSONObject();
            order.put("id", "repair-" + nextId(state));
            order.put("siteId", device.getString("siteId"));
            order.put("areaId", device.getString("areaId"));
            order.put("deviceId", device.getString("id"));
            order.put("status", "OPEN");
            order.put("phase", "WAITING");
            order.put("reason", description);
            order.put("handlerId", handler.getString("id"));
            order.put("handlerName", handler.getString("name"));
            order.put("version", 1);
            order.put("createdAt", now());
            order.put("source", "MOCK_STOCK");
            order.put("batchId", null);
            add(state, "maintenanceOrders", order);
            device.put("lifecycle", "MAINTENANCE");
            add(state, "maintenanceRecords", record(state, "maintenanceRecords", device, actor, fields(order.getString("id"), "CREATED", description, null, handler.getString("name"), null, null, null)));
            lifeAction = "SEND_REPAIR";
        } else if ("maintenance.assign".equals(type)) {
            description = text(input, "reason");
            JSONObject handler = handler(state, device, input);
            String oldName = order.getString("handlerName");
            order.put("handlerId", handler.getString("id"));
            order.put("handlerName", handler.getString("name"));
            order.put("phase", "WAITING");
            JSONObject extra = fields(order.getString("id"), "ASSIGNED", description, null, handler.getString("name"), null, null, null);
            extra.put("oldHandlerName", oldName);
            add(state, "maintenanceRecords", record(state, "maintenanceRecords", device, actor, extra));
        } else if ("maintenance.start".equals(type)) {
            order.put("phase", "PROCESSING");
            add(state, "maintenanceRecords", record(state, "maintenanceRecords", device, actor, fields(order.getString("id"), "STARTED", null, null, actor.getString("name"), null, null, null)));
        } else if ("maintenance.inspect".equals(type)) {
            String repairContent = text(input, "repairContent");
            inspection = text(input, "inspection");
            if (!"PASS".equals(input.getString("result")) && !"FAIL".equals(input.getString("result"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择检测通过或未通过");
            if ("PASS".equals(input.getString("result"))) {
                confirm(input);
                order.put("status", "CLOSED");
                order.put("phase", "CLOSED");
                order.put("outcome", "REPAIRED");
                order.put("closedAt", now());
                device.put("lifecycle", "STOCK");
                lifeAction = "REPAIRED";
            }
            add(state, "maintenanceRecords", record(state, "maintenanceRecords", device, actor, fields(order.getString("id"), "PASS".equals(input.getString("result")) ? "PASSED" : "FAILED", null, inspection, actor.getString("name"), repairContent, null, null)));
        } else if ("devices.disable".equals(type)) {
            description = text(input, "reason");
            device.put("lifecycle", "DISABLED");
            lifeAction = "DISABLED";
        } else if ("devices.restore".equals(type)) {
            description = text(input, "reason");
            inspection = text(input, "inspection");
            confirm(input);
            device.put("lifecycle", "STOCK");
            lifeAction = "RESTORED";
        }
        if (lifeAction != null) {
            JSONObject extra = fields(order == null ? null : order.getString("id"), lifeAction, description, inspection, order == null ? null : order.getString("handlerName"), null, previous, device.getString("lifecycle"));
            add(state, "lifecycleHistory", record(state, "lifecycleHistory", device, actor, extra));
        }
        if (existingOrder && order != null) order.put("version", order.getIntValue("version") + 1);
        device.put("version", device.getIntValue("version") + 1);
        JSONObject output = new JSONObject();
        output.put("deviceId", device.getString("id"));
        output.put("orderId", order == null ? null : order.getString("id"));
        output.put("lifecycle", device.getString("lifecycle"));
        output.put("phase", order == null ? null : phase(order));
        output.put("deviceVersion", device.getIntValue("version"));
        output.put("orderVersion", order == null ? null : order.getIntValue("version"));
        return output;
    }

    private Map<String, Object> orders(JSONObject state, JSONObject actor, JSONObject input) {
        String status = input.getString("status");
        String phase = input.getString("phase");
        if ((status != null && !status.isEmpty() && !Arrays.asList("OPEN", "CLOSED").contains(status)) || (phase != null && !phase.isEmpty() && !PHASES.contains(phase)) || (input.containsKey("mine") && !(input.get("mine") instanceof Boolean))) throw AdminQueryService.fail(400, "INVALID_FILTER", "工单筛选无效");
        List<JSONObject> rows = new ArrayList<JSONObject>();
        List<JSONObject> orders = rows(state, "maintenanceOrders");
        for (int i = orders.size() - 1; i >= 0; i--) {
            JSONObject order = orders.get(i);
            if (!input.getString("siteId").equals(order.getString("siteId"))) continue;
            if (input.getString("deviceId") != null && !input.getString("deviceId").isEmpty() && !input.getString("deviceId").equals(order.getString("deviceId"))) continue;
            JSONObject device = find(state, "devices", order.getString("deviceId"));
            if (device == null || !input.getString("siteId").equals(device.getString("siteId")) || !queries.allows(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) continue;
            JSONObject view = project(state, actor, pair(order, device));
            if (status != null && !status.isEmpty() && !status.equals(view.get("status"))) continue;
            if (phase != null && !phase.isEmpty() && !phase.equals(view.get("phase"))) continue;
            if (Boolean.TRUE.equals(input.getBoolean("mine")) && !actor.getString("id").equals(order.getString("handlerId"))) continue;
            view.put("code", view.getString("id") + " " + view.getString("deviceCode"));
            view.put("name", view.getString("deviceName"));
            rows.add(view);
        }
        return page(rows, input, true);
    }

    private JSONObject project(JSONObject state, JSONObject actor, JSONObject pair) {
        JSONObject order = pair.getJSONObject("order");
        JSONObject device = pair.getJSONObject("device");
        JSONObject view = JSONObject.parseObject(order.toJSONString());
        JSONObject handler = find(state, "accounts", order.getString("handlerId"));
        view.put("phase", phase(order));
        view.put("deviceCode", device.getString("code"));
        view.put("deviceName", device.getString("name"));
        view.put("deviceType", device.getString("type"));
        view.put("deviceVersion", device.getIntValue("version"));
        view.put("deviceLifecycle", device.getString("lifecycle"));
        view.put("handlerName", order.getString("handlerName"));
        view.put("currentHandlerName", handler == null ? null : handler.getString("name"));
        view.put("handlerValid", handler != null && handler.getBooleanValue("enabled") && queries.allows(state, handler, "assets:write", device.getString("siteId"), device.getString("areaId")));
        view.put("manager", manager(state, actor, device));
        JSONObject actions = new JSONObject();
        String relation = queries.relationshipOf(state, device).getString("state");
        for (String type : Arrays.asList("maintenance.assign", "maintenance.start", "maintenance.inspect", "maintenance.scrap")) actions.put(type, reason(state, actor, device, relation, type, order));
        view.put("actions", actions);
        return view;
    }

    private String reason(JSONObject state, JSONObject actor, JSONObject device, String relation, String type, JSONObject order) {
        if (!queries.allows(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId")) || !queries.allows(state, actor, "assets:write", device.getString("siteId"), device.getString("areaId"))) return "需要本设备范围内资产办理权限";
        if (Arrays.asList("maintenance.assign", "devices.scrap", "maintenance.scrap").contains(type) && !manager(state, actor, device)) return "仅授权范围内的系统／厂站管理员可办理";
        if (Arrays.asList("maintenance.start", "maintenance.inspect").contains(type) && (order == null || !actor.getString("id").equals(order.getString("handlerId")))) return "仅指定处理人可办理；管理员需先重新指派给自己";
        if ("SCRAPPED".equals(device.getString("lifecycle"))) return "报废档案只读，不支持恢复或再次办理";
        if (!"UNASSIGNED".equals(relation) || activeAssignment(state, device.getString("id"))) return "必须明确未领用且无有效关系；使用中先归还，未知或冲突需核实";
        List<JSONObject> active = openOrders(state, device.getString("id"));
        if (type.startsWith("maintenance.") && !"maintenance.create".equals(type)) {
            if (order == null || !"OPEN".equals(order.getString("status"))) return "工单不存在或已关闭";
            if (!"MAINTENANCE".equals(device.getString("lifecycle")) || active.size() != 1 || !order.getString("id").equals(active.get(0).getString("id")) || !device.getString("siteId").equals(order.getString("siteId"))) return "设备与活动工单状态不一致，需核实";
            if ("maintenance.start".equals(type) && !"WAITING".equals(phase(order))) return "仅待处理工单可接单";
            if ("maintenance.inspect".equals(type) && !"PROCESSING".equals(phase(order))) return "请先接单开始维修，再记录检测结果";
        } else if (!active.isEmpty()) {
            return "存在未完成维修单，不能直接办理此操作";
        } else {
            List<String> allowed = "devices.restore".equals(type) ? Arrays.asList("DISABLED") : "devices.scrap".equals(type) ? Arrays.asList("STOCK", "DISABLED") : Arrays.asList("STOCK");
            if (!allowed.contains(device.getString("lifecycle"))) return "当前生命周期不允许此操作";
        }
        return "";
    }

    private boolean manager(JSONObject state, JSONObject actor, JSONObject device) {
        String siteId = device.getString("siteId");
        String areaId = device.getString("areaId");
        if (!queries.allows(state, actor, "assets:read", siteId, areaId)) return false;
        if ("demo-system".equals(actor.getString("id")) && actor.getBooleanValue("enabled")) return queries.allows(state, actor, "assets:write", siteId, areaId);
        JSONArray roleIds = actor.getJSONArray("roleIds");
        if (roleIds == null || !roleIds.contains("site")) return false;
        JSONObject role = find(state, "roles", "site");
        if (role == null || !role.getBooleanValue("builtin") || !role.getBooleanValue("enabled")) return false;
        boolean enabledSite = false;
        for (JSONObject site : rows(state, "sites")) if (siteId.equals(site.getString("id")) && site.getBooleanValue("enabled")) enabledSite = true;
        if (!enabledSite) return false;
        JSONArray grants = role.getJSONArray("grants");
        if (grants == null) return false;
        for (int i = 0; i < grants.size(); i++) {
            JSONObject grant = grants.getJSONObject(i);
            JSONArray operations = grant.getJSONArray("operations");
            JSONArray sites = grant.getJSONArray("siteIds");
            if (operations == null || sites == null || !sites.contains(siteId)) continue;
            if (!(operations.contains("*") || operations.contains("assets:write"))) continue;
            Object areas = grant.get("areaIds");
            if ("*".equals(areas) || (areas instanceof JSONArray && ((JSONArray) areas).contains(areaId))) return true;
        }
        return false;
    }

    private JSONObject handler(JSONObject state, JSONObject device, JSONObject input) {
        JSONObject handler = find(state, "accounts", input.getString("handlerId"));
        if (handler == null || !handler.getBooleanValue("enabled") || !queries.allows(state, handler, "assets:write", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(409, "MAINTENANCE_CONFLICT", "请选择仍有本设备资产办理权限的启用账号");
        if (handler.getIntValue("version") != input.getIntValue("handlerVersion")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "处理人账号已变化，请重新读取");
        return handler;
    }

    private static void confirm(JSONObject input) {
        if (!Boolean.TRUE.equals(input.getBoolean("acknowledged"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请确认仅为本地验收，不代表真实设备安全认证");
    }

    private static String text(JSONObject input, String key) {
        String value = input.getString(key);
        String label = "reason".equals(key) ? "原因" : "repairContent".equals(key) ? "维修内容" : "inspection".equals(key) ? "检查／检测说明" : key;
        if (value == null || value.trim().isEmpty() || value.trim().length() > 1000) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写" + label + "（最多1000字）");
        return value.trim();
    }

    private JSONObject readState() {
        JSONObject state = ledger.read();
        if (state == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        return state;
    }

    private JSONObject actor(JSONObject state, String accountId) {
        JSONObject actor = find(state, "accounts", accountId);
        if (actor == null || !actor.getBooleanValue("enabled")) throw AdminQueryService.fail(401, "IDENTITY_INVALID", "请先登录");
        return actor;
    }

    private JSONObject loadDevice(JSONObject state, JSONObject actor, JSONObject input) {
        JSONObject device = find(state, "devices", input.getString("deviceId"));
        if (device == null || !input.getString("siteId").equals(device.getString("siteId")) || !queries.allows(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "设备不存在或不可见");
        return device;
    }

    private JSONObject loadOrder(JSONObject state, JSONObject actor, JSONObject input) {
        JSONObject order = find(state, "maintenanceOrders", input.getString("id"));
        if (order == null || !input.getString("siteId").equals(order.getString("siteId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "维修单不存在或不可见");
        JSONObject lookup = new JSONObject();
        lookup.put("siteId", input.getString("siteId"));
        lookup.put("deviceId", order.getString("deviceId"));
        return pair(order, loadDevice(state, actor, lookup));
    }

    private static JSONObject pair(JSONObject order, JSONObject device) {
        JSONObject pair = new JSONObject();
        pair.put("order", order);
        pair.put("device", device);
        return pair;
    }

    private int nextId(JSONObject state) {
        int next = state.getIntValue("nextId") + 1;
        state.put("nextId", next);
        return next;
    }

    private JSONObject record(JSONObject state, String key, JSONObject device, JSONObject actor, JSONObject extra) {
        JSONObject record = new JSONObject();
        record.put("id", key + "-" + nextId(state));
        record.put("siteId", device.getString("siteId"));
        record.put("areaId", device.getString("areaId"));
        record.put("deviceId", device.getString("id"));
        record.put("deviceCode", device.getString("code"));
        record.put("deviceName", device.getString("name"));
        record.put("type", device.getString("type"));
        record.put("actorId", actor.getString("id"));
        record.put("actorName", actor.getString("name"));
        record.put("occurredAt", now());
        record.put("source", "前端内存本地");
        if (extra != null) record.putAll(extra);
        return record;
    }

    private static JSONObject fields(String orderId, String action, String description, String inspection, String handlerName, String repairContent, String from, String to) {
        JSONObject fields = new JSONObject();
        fields.put("orderId", orderId);
        fields.put("action", action);
        if (description != null) fields.put("description", description);
        if (inspection != null) fields.put("inspection", inspection);
        fields.put("handlerName", handlerName);
        if (repairContent != null) fields.put("repairContent", repairContent);
        if (from != null) fields.put("from", from);
        if (to != null) fields.put("to", to);
        return fields;
    }

    private static String phase(JSONObject order) {
        if ("CLOSED".equals(order.getString("status"))) return "CLOSED";
        if (order.getString("phase") != null && !order.getString("phase").isEmpty()) return order.getString("phase");
        return order.getString("handlerId") != null && !order.getString("handlerId").isEmpty() ? "WAITING" : "UNASSIGNED";
    }

    private static boolean activeAssignment(JSONObject state, String deviceId) {
        for (JSONObject assignment : rows(state, "assignments")) if (assignment.getBooleanValue("active") && deviceId.equals(assignment.getString("deviceId"))) return true;
        return false;
    }

    private static List<JSONObject> openOrders(JSONObject state, String deviceId) {
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject order : rows(state, "maintenanceOrders")) if (deviceId.equals(order.getString("deviceId")) && "OPEN".equals(order.getString("status"))) rows.add(order);
        return rows;
    }

    private Map<String, Object> page(List<JSONObject> rows, JSONObject input, boolean useKeyword) {
        int pageNum = input.getIntValue("pageNum");
        int pageSize = input.getIntValue("pageSize");
        if (pageNum == 0) pageNum = 1;
        if (pageSize == 0) pageSize = 20;
        if (pageNum < 1 || pageSize < 1 || pageSize > 100) throw AdminQueryService.fail(400, "INVALID_PAGE", "分页参数无效");
        String keyword = useKeyword ? input.getString("keyword") : "";
        if (keyword == null) keyword = "";
        if (keyword.length() > 100) throw AdminQueryService.fail(400, "INVALID_KEYWORD", "关键词最多100字");
        List<JSONObject> filtered = rows;
        if (!keyword.trim().isEmpty()) {
            String needle = keyword.trim().toLowerCase();
            filtered = new ArrayList<JSONObject>();
            for (JSONObject row : rows) {
                String hay = textOf(row, "code") + " " + textOf(row, "loginName") + " " + textOf(row, "personName") + " " + textOf(row, "name");
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

    private static String now() { return new Date().toInstant().toString(); }

    private static String textOf(JSONObject row, String key) {
        String value = row.getString(key);
        return value == null ? "" : value;
    }

    private static void rejectExtra(JSONObject input) {
        for (String key : input.keySet()) if (!INPUT_KEYS.contains(key)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "不允许指定状态、时间或经办人");
    }

    private static void add(JSONObject state, String key, JSONObject row) {
        JSONArray list = state.getJSONArray(key);
        if (list == null) { list = new JSONArray(); state.put(key, list); }
        list.add(row);
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
}
