package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

@Service
public class AdminMasterService {
    private static final List<String> ENTITIES = Arrays.asList("people", "organizations", "areas", "sites", "dutyShifts");
    private static final List<String> ACTIONS = Arrays.asList("create", "update", "status", "delete");
    private static final Pattern CJK = Pattern.compile("[\\u4e00-\\u9fff]");
    private final AdminLedgerStore ledger;
    private final GuardianStore guardian;
    private final AdminQueryService queries;

    public AdminMasterService(AdminLedgerStore ledger, GuardianStore guardian, AdminQueryService queries) {
        this.ledger = ledger;
        this.guardian = guardian;
        this.queries = queries;
    }


    public boolean handles(String type) {
        if (type == null || !type.contains(".")) return false;
        String entity = type.substring(0, type.indexOf('.'));
        String action = type.substring(type.indexOf('.') + 1);
        return ENTITIES.contains(entity) && ACTIONS.contains(action);
    }

    public JSONObject execute(String accountId, String type, JSONObject input) {
        if (!handles(type)) throw AdminQueryService.fail(400, "UNKNOWN_COMMAND", "未开放此操作");
        JSONObject state = ledger.read();
        if (state == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        JSONObject actor = account(state, accountId);
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
        String entity = type.substring(0, type.indexOf('.'));
        String action = type.substring(type.indexOf('.') + 1);
        JSONObject before = null;
        JSONObject output = apply(state, actor, entity, action, input);
        if (!"create".equals(action)) before = output.getJSONObject("_before");
        output.remove("_before");
        try {
            publish(state);
        } catch (AdminQueryService.QueryFailed error) {
            throw error;
        } catch (RuntimeException error) {
            throw AdminQueryService.fail(400, "PORTAL_REJECTED", error.getMessage() == null ? "监护数据保存失败" : error.getMessage());
        }
        state.put("revision", state.getIntValue("revision") + 1);
        audit(state, actor, type, input, before, output);
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

    private JSONObject apply(JSONObject state, JSONObject actor, String entity, String action, JSONObject input) {
        JSONObject row = "create".equals(action) ? null : find(state, entity, input.getString("id"));
        if (!"create".equals(action) && (row == null || (!"sites".equals(entity) && !input.getString("siteId").equals(row.getString("siteId"))))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "对象不存在或不可见");
        if ("sites".equals(entity) && !"demo-system".equals(actor.getString("id"))) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "仅系统管理员可维护厂站或角色");
        String siteId = row == null ? input.getString("siteId") : row.getString("siteId");
        String areaId = row == null ? null : ("areas".equals(entity) ? row.getString("id") : row.getString("areaId"));
        if (!queries.allows(state, actor, writeOperation(entity), "sites".equals(entity) ? input.getString("id") : siteId, areaId)) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "当前身份无此操作或数据范围权限");
        if (!"sites".equals(entity) && !siteEnabled(state, siteId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择启用的厂站");
        if (!"create".equals(action) && input.getIntValue("expectedVersion") != row.getIntValue("version")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "对象已变化，请重新读取");
        if ("delete".equals(action)) return remove(state, entity, row);
        if ("status".equals(action)) return status(state, actor, entity, row, input);
        return save(state, actor, entity, action, row, input, siteId);
    }

    private JSONObject remove(JSONObject state, String entity, JSONObject row) {
        if (!"organizations".equals(entity) && !"areas".equals(entity)) throw AdminQueryService.fail(400, "DELETE_DISABLED", "该资料仅支持启停，不允许删除");
        if (referenced(state, entity, row, true)) throw AdminQueryService.fail(409, "REFERENCED", "仍有引用，不能删除");
        JSONArray list = state.getJSONArray(entity);
        for (int i = 0; i < list.size(); i++) if (row.getString("id").equals(list.getJSONObject(i).getString("id"))) list.remove(i);
        JSONObject output = JSONObject.parseObject(row.toJSONString());
        output.put("deleted", true);
        output.put("_before", row);
        return output;
    }

    private JSONObject status(JSONObject state, JSONObject actor, String entity, JSONObject row, JSONObject input) {
        if (!input.containsKey("enabled") || !(input.get("enabled") instanceof Boolean)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "启停状态无效");
        boolean enabled = input.getBooleanValue("enabled");
        if ("dutyShifts".equals(entity)) {
            Instant start = parseInstant(row.getString("startsAt"));
            if (enabled || start == null || !start.isAfter(Instant.now())) throw AdminQueryService.fail(409, "SHIFT_STARTED", "仅未来班次允许取消，不能恢复已取消班次");
        }
        if (!enabled && referenced(state, entity, row, false)) throw AdminQueryService.fail(409, "REFERENCED", "存在活动引用，请先处理影响清单");
        if (enabled && row.getString("parentId") != null) requireEnabled(state, actor, entity, row.getString("parentId"), row.getString("siteId"), input);
        if (enabled && "people".equals(entity)) {
            requireEnabled(state, actor, "areas", row.getString("areaId"), row.getString("siteId"), input);
            requireEnabled(state, actor, "organizations", row.getString("organizationId"), row.getString("siteId"), input);
        }
        JSONObject before = JSONObject.parseObject(row.toJSONString());
        row.put("enabled", enabled);
        row.put("version", row.getIntValue("version") + 1);
        row.put("_before", before);
        return row;
    }

    private JSONObject save(JSONObject state, JSONObject actor, String entity, String action, JSONObject row, JSONObject input, String siteId) {
        JSONObject data = input.getJSONObject("data");
        if (data == null) data = new JSONObject();
        boolean creating = "create".equals(action);
        if (!creating && data.getString("siteId") != null && !data.getString("siteId").isEmpty() && !"sites".equals(entity) && !data.getString("siteId").equals(siteId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "不支持跨厂站调动");
        JSONObject record = creating ? new JSONObject() : JSONObject.parseObject(row.toJSONString());
        if (creating) {
            record.put("id", entity + "-19007199254740993-" + nextId(state));
            record.put("siteId", siteId);
            record.put("enabled", true);
        }
        record.put("name", required(data, "name", 100, "名称"));
        record.put("version", (row == null ? 0 : row.getIntValue("version")) + 1);
        if (!"dutyShifts".equals(entity)) {
            record.put("code", required(data, "code", 50, "编号"));
            for (JSONObject other : rows(state, entity)) {
                if (record.getString("id").equals(other.getString("id"))) continue;
                if (other.getString("code") != null && other.getString("code").equalsIgnoreCase(record.getString("code"))) throw AdminQueryService.fail(409, "RELATION_CONFLICT", "编号已存在，请使用其他编号");
            }
        }
        if ("organizations".equals(entity) || "areas".equals(entity)) {
            String parentId = blank(data.getString("parentId"));
            record.put("parentId", parentId);
            if (parentId != null) requireEnabled(state, actor, entity, parentId, siteId, input);
            if (cycle(state, entity, record.getString("id"), parentId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "上级不能是自身或后代");
            if ("organizations".equals(entity)) {
                String area = blank(data.getString("areaId"));
                record.put("areaId", area);
                if (area != null) requireEnabled(state, actor, "areas", area, siteId, input);
                if (!queries.allows(state, actor, "organization:write", siteId, area)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "目标区域不在可维护范围");
            }
            if ("areas".equals(entity)) record.put("points", areaPoints(data));
        }
        if ("sites".equals(entity)) {
            record.remove("siteId");
            String timezone = required(data, "timezone", 100, "时区");
            try { ZoneId.of(timezone); } catch (DateTimeException error) { throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请输入有效的IANA时区，例如Asia/Shanghai"); }
            record.put("timezone", timezone);
            if ("site-1".equals(record.getString("id")) && !CJK.matcher(record.getString("name")).find()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "临江厂站名称需要保留中文，否则监护数据无法保存");
            if (creating) {
                JSONObject system = find(state, "roles", "system");
                if (system != null && system.getJSONArray("grants") != null && !system.getJSONArray("grants").isEmpty()) system.getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds").add(record.getString("id"));
            }
        }
        if ("people".equals(entity)) {
            String organizationId = blank(data.getString("organizationId"));
            String area = blank(data.getString("areaId"));
            record.put("organizationId", organizationId);
            record.put("areaId", area);
            if (organizationId != null) requireEnabled(state, actor, "organizations", organizationId, siteId, input);
            if (area != null) requireEnabled(state, actor, "areas", area, siteId, input);
            if (!queries.allows(state, actor, "people:write", siteId, area)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "目标区域不在可维护范围");
            String remark = data.getString("remark");
            remark = remark == null ? "" : remark.trim();
            if (remark.length() > 500) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "备注最多500字");
            record.put("remark", remark);
            if (row != null) record.put("accountId", row.get("accountId"));
            if (row != null && row.getJSONObject("equipmentEvidence") != null) record.put("equipmentEvidence", row.getJSONObject("equipmentEvidence"));
            else if (creating) {
                JSONObject evidence = new JSONObject();
                evidence.put("HELMET", "COMPLETE");
                evidence.put("BELT", "COMPLETE");
                evidence.put("WATCH", "COMPLETE");
                record.put("equipmentEvidence", evidence);
            }
        }
        if ("dutyShifts".equals(entity)) {
            Instant existingStart = row == null ? null : parseInstant(row.getString("startsAt"));
        if (row != null && (!row.getBooleanValue("enabled") || existingStart == null || !existingStart.isAfter(Instant.now()))) throw AdminQueryService.fail(409, "SHIFT_STARTED", "已开始或已取消班次不能普通编辑");
            Instant start = requireInstant(data, "startsAt");
            Instant end = requireInstant(data, "endsAt");
            if (!start.isAfter(Instant.now()) || !end.isAfter(start)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "班次必须在未来开始，结束晚于开始");
            JSONArray people = data.getJSONArray("personIds");
            if (people == null || people.isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择至少一名成员，且不能重复");
            List<String> seen = new ArrayList<String>();
            JSONArray snapshots = new JSONArray();
            for (int i = 0; i < people.size(); i++) {
                String id = people.getString(i);
                if (id == null || seen.contains(id)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择至少一名成员，且不能重复");
                seen.add(id);
                JSONObject person = requireEnabled(state, actor, "people", id, siteId, input);
                if (!queries.allows(state, actor, "duty:write", siteId, person.getString("areaId"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "成员不在可维护范围");
                JSONObject snap = new JSONObject();
                snap.put("id", id);
                snap.put("name", person.getString("name"));
                snapshots.add(snap);
            }
            record.put("startsAt", start.toString());
            record.put("endsAt", end.toString());
            record.put("personIds", people);
            record.put("source", "MOCK");
            record.put("memberSnapshots", snapshots);
        }
        JSONArray list = state.getJSONArray(entity);
        if (list == null) { list = new JSONArray(); state.put(entity, list); }
        if (creating) list.add(record);
        else for (int i = 0; i < list.size(); i++) if (record.getString("id").equals(list.getJSONObject(i).getString("id"))) list.set(i, record);
        if (row != null) record.put("_before", JSONObject.parseObject(row.toJSONString()));
        return record;
    }

    private boolean referenced(JSONObject state, String entity, JSONObject row, boolean all) {
        if ("people".equals(entity)) {
            for (JSONObject assignment : rows(state, "assignments")) if (assignment.getBooleanValue("active") && row.getString("id").equals(assignment.getString("personId"))) return true;
            for (JSONObject shift : rows(state, "dutyShifts")) {
                JSONArray members = shift.getJSONArray("personIds");
                if (members == null || !members.contains(row.getString("id"))) continue;
                if (!all && !shift.getBooleanValue("enabled")) continue;
                Instant end = parseInstant(shift.getString("endsAt"));
                if (all || (end != null && end.isAfter(Instant.now()))) return true;
            }
            return openWork(row);
        }
        if ("organizations".equals(entity) || "areas".equals(entity)) {
            for (JSONObject child : rows(state, entity)) if (row.getString("id").equals(child.getString("parentId")) && (all || child.getBooleanValue("enabled"))) return true;
            String key = "areas".equals(entity) ? "areaId" : "organizationId";
            for (JSONObject person : rows(state, "people")) if (row.getString("id").equals(person.getString(key)) && (all || person.getBooleanValue("enabled"))) return true;
            if ("areas".equals(entity)) {
                for (JSONObject device : rows(state, "devices")) if (row.getString("id").equals(device.getString("areaId"))) return true;
                for (JSONObject org : rows(state, "organizations")) if (row.getString("id").equals(org.getString("areaId")) && (all || org.getBooleanValue("enabled"))) return true;
            }
        }
        if ("sites".equals(entity)) {
            for (String key : Arrays.asList("organizations", "areas", "people", "devices", "accounts")) {
                for (JSONObject item : rows(state, key)) if (row.getString("id").equals(item.getString("siteId")) && (all || item.getBooleanValue("enabled"))) return true;
            }
        }
        return false;
    }

    private boolean openWork(JSONObject person) {
        JSONObject snapshot = guardian.snapshot();
        if (snapshot == null) return false;
        String portalId = person.getString("portalId");
        if (portalId == null || portalId.isEmpty()) portalId = person.getString("id");
        if (portalId == null) return false;
        for (JSONObject work : rows(snapshot, "works")) {
            if ("已结束".equals(work.getString("status"))) continue;
            JSONArray members = work.getJSONArray("members");
            if (members != null && members.contains(portalId)) return true;
        }
        return false;
    }

    private JSONArray areaPoints(JSONObject data) {
        if (data.get("points") == null) return new JSONArray();
        JSONArray raw = data.getJSONArray("points");
        if (raw == null || raw.isEmpty()) return new JSONArray();
        if (raw.size() < 3) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "地图范围至少需要 3 个点，或清空后只保存名称");
        JSONArray clean = new JSONArray();
        for (int i = 0; i < raw.size(); i++) {
            JSONArray pair = raw.getJSONArray(i);
            if (pair == null || pair.size() < 2) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "地图范围的节点无效");
            double x = pair.getDoubleValue(0);
            double y = pair.getDoubleValue(1);
            if (x < 0 || x > 100 || y < 0 || y > 100) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "地图范围需要落在厂区地图内");
            JSONArray point = new JSONArray();
            point.add(x);
            point.add(y);
            clean.add(point);
        }
        return clean;
    }

    private void publish(JSONObject admin) {
        WearableModel.migrate(admin);
        guardian.update(snapshot -> {
            GuardianMasterProjection.apply(snapshot, admin);
            JSONArray mapAreas = new JSONArray();
            for (JSONObject area : rows(admin, "areas")) {
                if (!area.getBooleanValue("enabled") || area.getJSONArray("points") == null || area.getJSONArray("points").size() < 3) continue;
                JSONObject site = find(admin, "sites", area.getString("siteId"));
                if (site != null) mapAreas.add(WearableModel.object("id",area.getString("id"),"name",area.getString("name"),"station",site.getString("portalStation"),"points",area.get("points")));
            }
            snapshot.put("mapAreas",mapAreas);
            snapshot.put("seq", snapshot.getIntValue("seq") + 1);
            return true;
        });
    }

    private JSONObject requireEnabled(JSONObject state, JSONObject actor, String key, String id, String siteId, JSONObject input) {
        if (id == null || id.isEmpty()) return null;
        JSONObject ref = find(state, key, id);
        if (ref == null || !ref.getBooleanValue("enabled") || ("sites".equals(key) ? false : !siteId.equals(ref.getString("siteId")))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "关联对象未启用、不同厂站或不在授权范围");
        String operation = "people".equals(key) ? "people:read" : "areas".equals(key) ? "organization:read" : "organizations".equals(key) ? "organization:read" : "sites:read";
        String areaId = "areas".equals(key) ? ref.getString("id") : ref.getString("areaId");
        if (!queries.allows(state, actor, operation, "sites".equals(key) ? ref.getString("id") : ref.getString("siteId"), areaId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "关联对象未启用、不同厂站或不在授权范围");
        JSONObject versions = input.getJSONObject("relatedVersions");
        if (versions != null && (!versions.containsKey(id) || versions.getIntValue(id) != ref.getIntValue("version"))) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "关联对象已变化，请重新读取");
        return ref;
    }

    private void audit(JSONObject state, JSONObject actor, String type, JSONObject input, JSONObject before, JSONObject after) {
        JSONObject row = new JSONObject();
        row.put("id", "audit-" + nextId(state));
        row.put("siteId", "sites".equals(type.substring(0, type.indexOf('.'))) ? after.getString("id") : input.getString("siteId"));
        row.put("areaId", after.getString("areaId"));
        row.put("actorId", actor.getString("id"));
        row.put("actorName", actor.getString("name"));
        row.put("action", type);
        row.put("objectId", after.getString("id"));
        row.put("objectName", after.getString("name"));
        row.put("occurredAt", Instant.now().toString());
        row.put("result", "SUCCESS");
        row.put("operationId", input.getString("operationId"));
        row.put("before", brief(before));
        row.put("after", brief(after));
        row.put("source", "后台台账");
        JSONArray audit = state.getJSONArray("audit");
        if (audit == null) { audit = new JSONArray(); state.put("audit", audit); }
        audit.add(row);
    }

    private static JSONObject brief(JSONObject row) {
        if (row == null) return null;
        JSONObject brief = new JSONObject();
        for (String key : Arrays.asList("id", "name", "code", "enabled", "areaId", "organizationId", "remark")) if (row.containsKey(key)) brief.put(key, row.get(key));
        return brief;
    }

    private static String writeOperation(String entity) {
        if ("people".equals(entity)) return "people:write";
        if ("sites".equals(entity)) return "sites:write";
        if ("dutyShifts".equals(entity)) return "duty:write";
        return "organization:write";
    }

    private static boolean siteEnabled(JSONObject state, String siteId) {
        JSONObject site = find(state, "sites", siteId);
        return site != null && site.getBooleanValue("enabled");
    }

    private static boolean cycle(JSONObject state, String entity, String id, String parentId) {
        List<String> seen = new ArrayList<String>();
        seen.add(id);
        String parent = parentId;
        while (parent != null && !parent.isEmpty()) {
            if (seen.contains(parent)) return true;
            seen.add(parent);
            JSONObject node = find(state, entity, parent);
            parent = node == null ? null : node.getString("parentId");
        }
        return false;
    }

    private static String required(JSONObject data, String key, int max, String label) {
        String value = data.getString(key);
        if (value == null || value.trim().isEmpty() || value.trim().length() > max) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写" + label + "（1–" + max + "字）");
        return value.trim();
    }

    private static Instant requireInstant(JSONObject data, String key) {
        String value = data.getString(key);
        if (value == null || !value.endsWith("Z")) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请提供有效UTC时间");
        Instant instant = parseInstant(value);
        if (instant == null) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请提供有效UTC时间");
        return instant;
    }

    private static Instant parseInstant(String value) {
        try { return value == null ? null : Instant.parse(value); }
        catch (RuntimeException error) { return null; }
    }

    private static String blank(String value) { return value == null || value.trim().isEmpty() ? null : value; }

    private static String nameOf(JSONObject state, String key, String id) {
        JSONObject row = find(state, key, id);
        return row == null || row.getString("name") == null ? "" : row.getString("name");
    }

    private JSONObject account(JSONObject state, String id) {
        JSONObject account = find(state, "accounts", id);
        if (account == null || !account.getBooleanValue("enabled")) throw AdminQueryService.fail(401, "IDENTITY_INVALID", "请先登录");
        return account;
    }

    private int nextId(JSONObject state) {
        int next = state.getIntValue("nextId") + 1;
        state.put("nextId", next);
        return next;
    }

    private static JSONObject find(JSONObject state, String key, String id) {
        if (id == null) return null;
        for (JSONObject row : rows(state, key)) if (id.equals(row.getString("id"))) return row;
        return null;
    }

    private static List<JSONObject> rows(JSONObject state, String key) {
        List<JSONObject> list = new ArrayList<JSONObject>();
        JSONArray raw = state == null ? null : state.getJSONArray(key);
        if (raw == null) return list;
        for (int i = 0; i < raw.size(); i++) {
            JSONObject row = raw.getJSONObject(i);
            if (row != null) list.add(row);
        }
        return list;
    }
}
