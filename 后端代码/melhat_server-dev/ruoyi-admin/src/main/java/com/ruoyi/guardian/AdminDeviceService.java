package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

@Service
public class AdminDeviceService {
    private static final Pattern DATE = Pattern.compile("\\d{4}-\\d{2}-\\d{2}");
    private static final List<String> TYPES = Arrays.asList("HELMET", "BELT", "WATCH");
    private final AdminLedgerStore ledger;
    private final GuardianHatArchive hats;
    @org.springframework.beans.factory.annotation.Autowired private AdminQueryService queries;

    public AdminDeviceService(AdminLedgerStore ledger, GuardianHatArchive hats) {
        this.ledger = ledger;
        this.hats = hats;
    }

    public JSONObject execute(String accountId, String type, JSONObject input) {
        if (!Arrays.asList("devices.create", "devices.update", "devices.configure").contains(type)) {
            throw AdminQueryService.fail(400, "COMMAND_NOT_AVAILABLE", "本阶段仅开放设备建档、资料编辑和型号配置");
        }
        JSONObject state = ledger.read();
        if (state == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        JSONObject actor = account(state, accountId);
        if (actor == null) throw AdminQueryService.fail(401, "IDENTITY_INVALID", "请先登录");
        if (input == null) input = new JSONObject();
        JSONObject existing = "devices.create".equals(type) ? null : findDevice(state, input.getString("id"), input.getString("siteId"));
        String areaId = existing == null ? null : existing.getString("areaId");
        JSONObject fields = input.getJSONObject("data");
        if(existing!=null && "PLATFORM".equals(existing.getString("source")) && fields!=null) {
            for(String key:new String[]{"code","sn"}) if(fields.containsKey(key) && !java.util.Objects.equals(fields.getString(key),existing.getString(key)))
                throw AdminQueryService.fail(400,"PLATFORM_ID_READ_ONLY","厂家设备编号和SN不能修改");
        }
        String nextArea = fields != null && fields.containsKey("areaId") ? fields.getString("areaId") : areaId;
        if ((existing != null && !queries.allows(state, actor, "assets:write", input.getString("siteId"), areaId))
                || !queries.allows(state, actor, "assets:write", input.getString("siteId"), nextArea))
            throw AdminQueryService.fail(403, "PERMISSION_DENIED", "当前身份无此操作或数据范围权限");
        String operationId = input.getString("operationId");
        if (operationId == null || operationId.trim().isEmpty() || operationId.length() > 100) {
            throw AdminQueryService.fail(400, "OPERATION_REQUIRED", "操作标识无效");
        }
        String key = accountId + "\n" + type + "\n" + operationId;
        String fingerprint = input.toJSONString();
        JSONObject memory = state.getJSONObject("idempotency");
        if (memory == null) {
            memory = new JSONObject();
            state.put("idempotency", memory);
        }
        JSONObject previous = memory.getJSONObject(key);
        if (previous != null) {
            if (!fingerprint.equals(previous.getString("fingerprint"))) {
                throw AdminQueryService.fail(409, "IDEMPOTENCY_CONFLICT", "相同操作标识不能用于不同内容");
            }
            return previous.getJSONObject("result");
        }
        String action = type.substring("devices.".length());
        JSONObject row = null;
        if (!"create".equals(action)) {
            row = findDevice(state, input.getString("id"), input.getString("siteId"));
            if (row == null) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "设备不存在或不可见");
            if (!input.containsKey("expectedVersion") || input.getIntValue("expectedVersion") != row.getIntValue("version")) {
                throw AdminQueryService.fail(409, "VERSION_CONFLICT", "对象已变化，请重新读取");
            }
        }
        JSONObject output = apply(state, action, row, input);
        if ("HELMET".equals(output.getString("type"))) hats.ensureUnassigned(output.getString("code"));
        state.put("revision", state.getIntValue("revision") + 1);
        JSONArray audit = state.getJSONArray("audit");
        if (audit == null) {
            audit = new JSONArray();
            state.put("audit", audit);
        }
        JSONObject line = new JSONObject();
        line.put("id", "audit-device-" + state.getIntValue("revision"));
        line.put("siteId", input.getString("siteId"));
        line.put("areaId", output.getString("areaId"));
        line.put("actorName", actor.getString("name"));
        line.put("actorId", actor.getString("id"));
        line.put("occurredAt", java.time.Instant.now().toString());
        line.put("action", type);
        line.put("objectId", output.getString("id"));
        line.put("operationId", operationId);
        line.put("result", "SUCCESS");
        audit.add(line);
        JSONObject stored = new JSONObject();
        stored.put("fingerprint", fingerprint);
        JSONObject envelope = new JSONObject();
        envelope.put("code", 200);
        envelope.put("data", output);
        stored.put("result", envelope);
        memory.put(key, stored);
        ledger.write(state);
        return envelope;
    }

    private JSONObject apply(JSONObject state, String action, JSONObject row, JSONObject input) {
        JSONObject data = input.getJSONObject("data");
        if (data == null || data.isEmpty() && !"configure".equals(action)) throw AdminQueryService.fail(400, "INVALID_DATA", "请提交设备资料");
        if (data == null) data = new JSONObject();
        Set<String> allowed = new HashSet<String>(Arrays.asList("code", "name", "manufacturer", "sn", "areaId", "modelId", "assetCode", "purchasedOn", "remark", "assemblies", "confirmModelChange"));
        if ("create".equals(action)) allowed.add("type");
        if ("configure".equals(action)) allowed = new HashSet<String>(Arrays.asList("modelId", "assemblies", "confirmModelChange"));
        for (String key : data.keySet()) {
            if (!allowed.contains(key)) throw AdminQueryService.fail(400, "FIELD_NOT_ALLOWED", "不能通过基础资料修改厂站、类型、生命周期、通信、领用或验证结果");
        }
        if (row != null && "SCRAPPED".equals(row.getString("lifecycle"))) throw AdminQueryService.fail(409, "DEVICE_READ_ONLY", "报废设备全档案只读");
        JSONObject result = row == null ? new JSONObject() : JSONObject.parseObject(row.toJSONString());
        if (row == null) {
            int next = state.getIntValue("nextId") + 1;
            state.put("nextId", next);
            result.put("id", "device-" + next);
            result.put("siteId", input.getString("siteId"));
            result.put("type", data.getString("type"));
            result.put("version", 0);
            result.put("lifecycle", "STOCK");
            result.put("relation", "UNASSIGNED");
            result.put("communication", "NOT_CONNECTED");
            result.put("freshness", "UNKNOWN");
            result.put("connection", "NOT_CONNECTED");
            result.put("verification", "UNCONFIRMED");
            result.put("capability", "UNCONFIRMED");
            result.put("capabilitySource", "后台建档，未验证真实设备");
            result.put("assemblies", new JSONObject());
        }
        if (!TYPES.contains(result.getString("type"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择设备类型");
        if (!"configure".equals(action)) {
            for (String key : Arrays.asList("code", "name", "manufacturer", "sn", "assetCode", "purchasedOn", "remark")) {
                String value = data.containsKey(key) ? data.getString(key) : result.getString(key);
                if (value == null) value = "";
                int max = "remark".equals(key) ? 500 : 100;
                if (value.trim().length() > max) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "字段格式或长度无效");
                result.put(key, value.trim());
            }
            if (result.getString("code") == null || result.getString("code").isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写平台编号");
            if (result.getString("name") == null || result.getString("name").isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写设备名称");
            String purchased = result.getString("purchasedOn");
            if (purchased != null && !purchased.isEmpty() && !DATE.matcher(purchased).matches()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写有效购置日期");
        }
        if (data.containsKey("areaId") || row == null) {
            String areaId = data.getString("areaId");
            result.put("areaId", areaId == null || areaId.isEmpty() ? null : areaId);
        }
        if (result.getString("areaId") != null) {
            JSONObject area = find(state, "areas", result.getString("areaId"));
            if (area == null || !input.getString("siteId").equals(area.getString("siteId")) || !area.getBooleanValue("enabled")) {
                throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择本厂站启用区域");
            }
            JSONObject versions = input.getJSONObject("relatedVersions");
            if (versions != null && versions.getIntValue(area.getString("id")) != area.getIntValue("version")) {
                throw AdminQueryService.fail(409, "VERSION_CONFLICT", "区域已变化，请重新读取");
            }
        }
        String modelId = data.getString("modelId");
        if (modelId == null || modelId.isEmpty()) modelId = result.getString("modelId");
        if (modelId == null || modelId.isEmpty()) modelId = "unknown-" + result.getString("type");
        if (!modelMatches(modelId, result.getString("type"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "型号与设备类型不匹配");
        boolean changedModel = row != null && !modelId.equals(row.getString("modelId"));
        if (changedModel && !data.getBooleanValue("confirmModelChange")) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请确认型号变更及选配清理影响");
        result.put("modelId", modelId);
        result.put("assemblies", new JSONObject());
        if (row != null && locked(row, result)) {
            String reason = keyReason(state, row);
            if (reason != null) throw AdminQueryService.fail(409, "KEY_FIELDS_LOCKED", reason);
        }
        String code = result.getString("code") == null ? "" : result.getString("code").toLowerCase();
        for (JSONObject device : devices(state)) {
            if (result.getString("id").equals(device.getString("id"))) continue;
            if (device.getString("code") != null && device.getString("code").toLowerCase().equals(code)) {
                throw AdminQueryService.fail(409, "DEVICE_CONFLICT", "平台编号已存在，请核对后修改");
            }
            if (sameSn(result, device)) throw AdminQueryService.fail(409, "DEVICE_CONFLICT", "厂商与SN组合已存在，请核对后修改");
        }
        result.put("version", result.getIntValue("version") + 1);
        JSONArray devices = state.getJSONArray("devices");
        if (row == null) devices.add(result);
        else {
            for (int i = 0; i < devices.size(); i++) {
                if (result.getString("id").equals(devices.getJSONObject(i).getString("id"))) devices.set(i, result);
            }
        }
        return result;
    }

    private static boolean locked(JSONObject before, JSONObject after) {
        for (String key : Arrays.asList("code", "manufacturer", "sn", "areaId", "modelId")) {
            String left = before.getString(key) == null ? "" : before.getString(key);
            String right = after.getString(key) == null ? "" : after.getString(key);
            if (!left.equals(right)) return true;
        }
        return false;
    }

    private static String keyReason(JSONObject state, JSONObject device) {
        if (!"STOCK".equals(device.getString("lifecycle"))) return "仅库存设备可修改关键身份和选配";
        for (JSONObject assignment : assignments(state)) {
            if (assignment.getBooleanValue("active") && device.getString("id").equals(assignment.getString("deviceId"))) return "领用领用情况不明、冲突或存在有效关系，请先核实";
        }
        if (!"UNASSIGNED".equals(device.getString("relation"))) return "领用领用情况不明、冲突或存在有效关系，请先核实";
        for (JSONObject order : orders(state)) {
            if (device.getString("id").equals(order.getString("deviceId")) && "OPEN".equals(order.getString("status"))) return "存在未完成维修单，请先处理";
        }
        return null;
    }

    private static boolean modelMatches(String modelId, String type) {
        if ("demo-helmet-basic".equals(modelId) || "unknown-HELMET".equals(modelId)) return "HELMET".equals(type);
        if ("demo-belt".equals(modelId) || "unknown-BELT".equals(modelId)) return "BELT".equals(type);
        if ("demo-watch".equals(modelId) || "unknown-WATCH".equals(modelId)) return "WATCH".equals(type);
        return false;
    }

    private static boolean sameSn(JSONObject left, JSONObject right) {
        String maker = left.getString("manufacturer");
        String sn = left.getString("sn");
        if (maker == null || maker.isEmpty() || sn == null || sn.isEmpty()) return false;
        return maker.equalsIgnoreCase(right.getString("manufacturer")) && sn.equalsIgnoreCase(right.getString("sn"));
    }

    private static JSONObject account(JSONObject state, String accountId) {
        if (accountId == null || accountId.trim().isEmpty()) return null;
        for (JSONObject account : list(state, "accounts")) {
            if (accountId.equals(account.getString("id")) && account.getBooleanValue("enabled")) return account;
        }
        return null;
    }

    private static JSONObject findDevice(JSONObject state, String id, String siteId) {
        for (JSONObject device : devices(state)) if (id != null && id.equals(device.getString("id")) && siteId.equals(device.getString("siteId"))) return device;
        return null;
    }

    private static List<JSONObject> devices(JSONObject state) { return list(state, "devices"); }
    private static List<JSONObject> assignments(JSONObject state) { return list(state, "assignments"); }
    private static List<JSONObject> orders(JSONObject state) { return list(state, "orders"); }

    private static List<JSONObject> list(JSONObject state, String key) {
        if ("orders".equals(key)) key = "maintenanceOrders";
        List<JSONObject> rows = new java.util.ArrayList<JSONObject>();
        JSONArray raw = state.getJSONArray(key);
        if (raw == null) return rows;
        for (int i = 0; i < raw.size(); i++) {
            JSONObject row = raw.getJSONObject(i);
            if (row != null) rows.add(row);
        }
        return rows;
    }

    private static JSONObject find(JSONObject state, String key, String id) {
        for (JSONObject row : list(state, key)) if (id.equals(row.getString("id"))) return row;
        return null;
    }
}
