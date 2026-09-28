package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

@Service
public class AdminAccessService {
    private static final List<String> AUDIT_QUERIES = Arrays.asList("audit", "auditDetail", "auditExport");
    private static final List<String> DELEGATE = Arrays.asList("viewer", "people-editor", "asset-operator");
    private static final List<String> OPERATIONS = Arrays.asList("overview:read", "assets:read", "people:read", "people:write", "organization:read", "organization:write", "sites:read", "sites:write", "duty:read", "duty:write", "access:read", "accounts:write", "roles:write", "audit:read", "integrations:read", "integrations:write", "assets:write", "groups:write");
    private static final Pattern SECRET = Pattern.compile("password|passwd|token|secret|credential|authorization|cookie", Pattern.CASE_INSENSITIVE);
    private static final Map<String, Preview> PREVIEWS = Collections.synchronizedMap(new LinkedHashMap<String, Preview>());

    private final AdminLedgerStore ledger;

    public AdminAccessService(AdminLedgerStore ledger) { this.ledger = ledger; }

    public boolean handlesQuery(String kind) { return AUDIT_QUERIES.contains(kind) || "authorizationPreview".equals(kind); }

    public boolean handles(String type) {
        return "accounts.resetCredential".equals(type) || (type != null && (type.startsWith("accounts.") || type.startsWith("roles.")));
    }

    public Map<String, Object> query(String accountId, String kind, JSONObject input) {
        JSONObject state = read();
        JSONObject actor = account(state, accountId);
        if (input == null) input = new JSONObject();
        if ("authorizationPreview".equals(kind)) return preview(state, actor, input);
        return audit(state, actor, kind, input);
    }

    public JSONObject execute(String accountId, String type, JSONObject input) {
        if (!handles(type)) throw AdminQueryService.fail(400, "UNKNOWN_COMMAND", "未开放此操作");
        JSONObject state = read();
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
        if (needsPreview(state, actor, type, input)) checkPreview(state, actor, type, input);
        JSONObject before = copy(find(state, type.startsWith("roles.") ? "roles" : "accounts", input.getString("id")));
        JSONObject output = "accounts.resetCredential".equals(type) ? reset(state, actor, input) : change(state, actor, type, input);
        output.remove("_before");
        state.put("revision", state.getIntValue("revision") + 1);
        auditRow(state, actor, type, input, before, output);
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

    private Map<String, Object> preview(JSONObject state, JSONObject actor, JSONObject input) {
        String type = input.getString("type");
        JSONObject command = input.getJSONObject("command");
        if (command == null || !Arrays.asList("accounts.update", "roles.update", "roles.status").contains(type) || !input.getString("siteId").equals(command.getString("siteId"))) throw AdminQueryService.fail(400, "INVALID_PREVIEW", "不支持此授权预览");
        String entity = type.startsWith("roles.") ? "roles" : "accounts";
        JSONObject row = find(state, entity, command.getString("id"));
        authorize(state, actor, entity, "update".equals(type.substring(type.indexOf('.') + 1)) ? "update" : "status", row, command);
        if (row.getIntValue("version") != command.getIntValue("expectedVersion")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "对象已变化，请重新读取");
        JSONObject draft = copy(state);
        change(draft, actor, type, command);
        boolean required = "roles.status".equals(type) || changedAccess(state, draft, type, command);
        String previewId = "preview-" + System.nanoTime();
        synchronized (PREVIEWS) {
            while (PREVIEWS.size() >= 50) PREVIEWS.remove(PREVIEWS.keySet().iterator().next());
            PREVIEWS.put(previewId, new Preview(actor.getString("id"), state.getIntValue("revision"), type, command.toJSONString()));
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.put("previewId", previewId);
        body.put("required", required);
        body.put("revision", state.getIntValue("revision"));
        body.put("accounts", diff(state, draft, type, command));
        return body;
    }

    private void checkPreview(JSONObject state, JSONObject actor, String type, JSONObject input) {
        Preview preview = PREVIEWS.get(input.getString("previewId"));
        JSONObject command = copy(input);
        command.remove("previewId");
        if (preview == null || !actor.getString("id").equals(preview.actorId) || preview.revision != state.getIntValue("revision") || !type.equals(preview.type) || !preview.fingerprint.equals(command.toJSONString())) {
            throw AdminQueryService.fail(409, "PREVIEW_EXPIRED", "授权预览缺失或已失效，请重新预览后确认");
        }
    }

    private boolean needsPreview(JSONObject state, JSONObject actor, String type, JSONObject input) {
        if (!Arrays.asList("accounts.update", "roles.update", "roles.status").contains(type)) return false;
        JSONObject draft = copy(state);
        change(draft, actor, type, input);
        return "roles.status".equals(type) || changedAccess(state, draft, type, input);
    }

    private JSONObject change(JSONObject state, JSONObject actor, String type, JSONObject input) {
        if ("accounts.resetCredential".equals(type)) return reset(state, actor, input);
        String entity = type.startsWith("roles.") ? "roles" : "accounts";
        String action = type.substring(type.indexOf('.') + 1);
        JSONObject row = "create".equals(action) ? null : find(state, entity, input.getString("id"));
        authorize(state, actor, entity, action, row, input);
        if (!"create".equals(action) && input.getIntValue("expectedVersion") != row.getIntValue("version")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "对象已变化，请重新读取");
        if ("delete".equals(action)) throw AdminQueryService.fail(400, "DELETE_DISABLED", "该资料仅支持启停，不允许删除");
        if ("status".equals(action)) return status(row, input);
        return "accounts".equals(entity) ? saveAccount(state, actor, action, row, input) : saveRole(state, action, row, input);
    }

    private void authorize(JSONObject state, JSONObject actor, String entity, String action, JSONObject row, JSONObject input) {
        if (!Arrays.asList("create", "update", "status", "delete").contains(action)) throw AdminQueryService.fail(400, "UNKNOWN_COMMAND", "未开放此操作");
        if (!"create".equals(action) && (row == null || !input.getString("siteId").equals(row.getString("siteId")) && !"roles".equals(entity))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "对象不存在或不可见");
        if ("roles".equals(entity) && !"demo-system".equals(actor.getString("id"))) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "仅系统管理员可维护厂站或角色");
        if (row != null && (("roles".equals(entity) && row.getBooleanValue("builtin")) || ("accounts".equals(entity) && "demo-system".equals(row.getString("id"))))) throw AdminQueryService.fail(403, "BUILTIN_PROTECTED", "内置系统管理员或角色受保护");
        String operation = "roles".equals(entity) ? "roles:write" : "accounts:write";
        if (!can(state, actor, operation, input.getString("siteId"), null)) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "当前身份无此操作或数据范围权限");
        if ("accounts".equals(entity) && row != null && !manageable(state, actor, row)) throw AdminQueryService.fail(403, "DELEGATION_DENIED", "不能管理自身、上级权限或超出自身范围的账号");
    }

    private JSONObject status(JSONObject row, JSONObject input) {
        if (!(input.get("enabled") instanceof Boolean)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "启停状态无效");
        row.put("enabled", input.getBooleanValue("enabled"));
        row.put("version", row.getIntValue("version") + 1);
        return row;
    }

    private JSONObject saveAccount(JSONObject state, JSONObject actor, String action, JSONObject row, JSONObject input) {
        JSONObject data = input.getJSONObject("data");
        if (data == null) data = new JSONObject();
        boolean creating = "create".equals(action);
        JSONObject record = creating ? new JSONObject() : copy(row);
        if (creating) {
            record.put("id", "accounts-19007199254740993-" + nextId(state));
            record.put("siteId", input.getString("siteId"));
            record.put("enabled", true);
            record.put("builtin", false);
            record.put("credentialVersion", 1);
            record.put("personId", null);
        }
        record.put("name", required(data, "name", 100, "名称"));
        record.put("version", (row == null ? 0 : row.getIntValue("version")) + 1);
        String login = required(data, "loginName", 50, "登录名");
        if (row != null && !login.equals(row.getString("loginName"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "登录名创建后不可修改");
        for (JSONObject other : rows(state, "accounts")) if (!record.getString("id").equals(other.getString("id")) && login.equalsIgnoreCase(other.getString("loginName"))) throw AdminQueryService.fail(409, "RELATION_CONFLICT", "登录名已存在");
        record.put("loginName", login);
        String personId = blank(data.getString("personId"));
        if (personId != null) {
            JSONObject person = find(state, "people", personId);
            if (person == null || !person.getBooleanValue("enabled") || !input.getString("siteId").equals(person.getString("siteId"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "关联对象未启用、不同厂站或不在授权范围");
            for (JSONObject other : rows(state, "accounts")) if (!record.getString("id").equals(other.getString("id")) && personId.equals(other.getString("personId"))) throw AdminQueryService.fail(409, "RELATION_CONFLICT", "该人员已关联另一个账号");
            JSONObject versions = input.getJSONObject("relatedVersions");
            if (versions != null && versions.getIntValue(personId) != person.getIntValue("version")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "关联人员已变化，请重新读取");
            if (row != null && row.getString("personId") != null && !row.getString("personId").equals(personId)) clearPerson(state, row.getString("personId"));
            person.put("accountId", record.getString("id"));
            person.put("version", person.getIntValue("version") + 1);
        } else if (row != null && row.getString("personId") != null) clearPerson(state, row.getString("personId"));
        record.put("personId", personId);
        JSONArray bindings = data.getJSONArray("bindings");
        if (bindings == null) bindings = new JSONArray();
        if (creating && !bindings.isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "新账号先以无授权状态创建，再编辑分配角色");
        record.put("roleIds", new JSONArray());
        record.put("roleScopes", new JSONObject());
        List<String> seen = new ArrayList<String>();
        for (int i = 0; i < bindings.size(); i++) {
            JSONObject binding = bindings.getJSONObject(i);
            String roleId = binding.getString("roleId");
            if (roleId == null || seen.contains(roleId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "角色不能重复");
            seen.add(roleId);
            JSONObject role = find(state, "roles", roleId);
            if (role == null || !role.getBooleanValue("enabled") || "system".equals(roleId) || (!"demo-system".equals(actor.getString("id")) && !DELEGATE.contains(roleId))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "此角色不可委派");
            JSONObject versions = input.getJSONObject("relatedVersions");
            if (versions != null && versions.containsKey(roleId) && versions.getIntValue(roleId) != role.getIntValue("version")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "角色已变化，请重新读取");
            JSONArray siteIds = binding.getJSONArray("siteIds");
            Object areas = binding.get("areaIds");
            if (siteIds == null || siteIds.isEmpty() || (!"*".equals(areas) && !(areas instanceof JSONArray && !((JSONArray) areas).isEmpty()))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择角色的厂站和区域范围");
            for (int s = 0; s < siteIds.size(); s++) {
                String siteId = siteIds.getString(s);
                if (find(state, "sites", siteId) == null || !find(state, "sites", siteId).getBooleanValue("enabled")) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "授权厂站未启用");
                if (!covers(role, siteId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "账号范围不能超过角色模板");
                if ("*".equals(areas) && !grantAllowsAllAreas(role, siteId)) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "区域角色不能扩大为全厂");
                if (areas instanceof JSONArray) {
                    JSONArray areaIds = (JSONArray) areas;
                    boolean any = false;
                    for (int a = 0; a < areaIds.size(); a++) {
                        JSONObject area = find(state, "areas", areaIds.getString(a));
                        if (area == null || !area.getBooleanValue("enabled") || !siteId.equals(area.getString("siteId"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "区域不属于选定厂站");
                        if (!grantAllowsArea(role, siteId, area.getString("id"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "区域超出角色模板");
                        if (!"demo-system".equals(actor.getString("id")) && !operationsCovered(state, actor, role, siteId, area.getString("id"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "不得委派超出自身的操作或范围");
                        any = true;
                    }
                    if (!any) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "每个选定厂站至少需要一个授权区域");
                }
            }
            record.getJSONArray("roleIds").add(roleId);
            JSONObject scope = new JSONObject();
            scope.put("siteIds", siteIds);
            scope.put("areaIds", "*".equals(areas) ? "*" : areas);
            record.getJSONObject("roleScopes").put(roleId, scope);
        }
        record.put("description", record.getJSONArray("roleIds").isEmpty() ? "自定义本地账号 · 尚未分配授权" : "自定义本地账号 · 按角色范围访问");
        put(state, "accounts", record, creating);
        return record;
    }

    private JSONObject saveRole(JSONObject state, String action, JSONObject row, JSONObject input) {
        JSONObject data = input.getJSONObject("data");
        if (data == null) data = new JSONObject();
        boolean creating = "create".equals(action);
        JSONObject record = creating ? new JSONObject() : copy(row);
        if (creating) {
            record.put("id", "roles-19007199254740993-" + nextId(state));
            record.put("enabled", true);
            record.put("builtin", false);
        }
        record.put("name", required(data, "name", 100, "名称"));
        record.put("version", (row == null ? 0 : row.getIntValue("version")) + 1);
        JSONArray operations = data.getJSONArray("operations");
        JSONArray siteIds = data.getJSONArray("siteIds");
        Object areas = data.get("areaIds");
        if (operations == null || operations.isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择已开放的操作，不允许通配权限");
        for (int i = 0; i < operations.size(); i++) if (!OPERATIONS.contains(operations.getString(i)) || "*".equals(operations.getString(i))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择已开放的操作，不允许通配权限");
        if (siteIds == null || siteIds.isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择启用的厂站");
        for (int i = 0; i < siteIds.size(); i++) if (find(state, "sites", siteIds.getString(i)) == null || !find(state, "sites", siteIds.getString(i)).getBooleanValue("enabled")) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择启用的厂站");
        if (!"*".equals(areas)) {
            if (!(areas instanceof JSONArray) || ((JSONArray) areas).isEmpty()) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择这些厂站内的区域");
            for (int i = 0; i < ((JSONArray) areas).size(); i++) {
                JSONObject area = find(state, "areas", ((JSONArray) areas).getString(i));
                if (area == null || !area.getBooleanValue("enabled") || !siteIds.contains(area.getString("siteId"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请选择这些厂站内的区域");
            }
        }
        JSONArray ops = new JSONArray();
        ops.add("overview:read");
        for (int i = 0; i < operations.size(); i++) if (!ops.contains(operations.getString(i))) ops.add(operations.getString(i));
        JSONObject grant = new JSONObject();
        grant.put("operations", ops);
        grant.put("siteIds", siteIds);
        grant.put("areaIds", "*".equals(areas) ? "*" : areas);
        JSONArray grants = new JSONArray();
        grants.add(grant);
        record.put("grants", grants);
        record.remove("siteId");
        put(state, "roles", record, creating);
        return record;
    }

    private JSONObject reset(JSONObject state, JSONObject actor, JSONObject input) {
        JSONObject row = find(state, "accounts", input.getString("id"));
        if (row == null || !input.getString("siteId").equals(row.getString("siteId"))) throw AdminQueryService.fail(404, "OBJECT_NOT_FOUND", "账号不存在或不可见");
        if (!manageable(state, actor, row)) throw AdminQueryService.fail(403, "ACCOUNT_PROTECTED", "不能重置自身、系统身份或超范围账号");
        if (input.getIntValue("expectedVersion") != row.getIntValue("version")) throw AdminQueryService.fail(409, "VERSION_CONFLICT", "对象已变化，请重新读取");
        String reason = input.getString("reason");
        if (reason == null || reason.trim().isEmpty() || reason.trim().length() > 500) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写重置原因（1–500字）");
        if (!Boolean.TRUE.equals(input.getBoolean("confirm"))) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请确认仅重置本地凭据");
        row.put("credentialVersion", row.getIntValue("credentialVersion") + 1);
        row.put("version", row.getIntValue("version") + 1);
        JSONObject output = new JSONObject();
        output.put("id", row.getString("id"));
        output.put("siteId", row.getString("siteId"));
        output.put("areaId", row.getString("areaId"));
        output.put("name", row.getString("name"));
        output.put("version", row.getIntValue("version"));
        output.put("credentialVersion", row.getIntValue("credentialVersion"));
        output.put("reason", reason.trim());
        return output;
    }

    private boolean changedAccess(JSONObject before, JSONObject after, String type, JSONObject input) {
        if ("roles.status".equals(type)) return true;
        String entity = type.startsWith("roles.") ? "roles" : "accounts";
        JSONObject left = find(before, entity, input.getString("id"));
        JSONObject right = find(after, entity, input.getString("id"));
        if (left == null || right == null) return true;
        if ("roles".equals(entity)) return !String.valueOf(left.get("grants")).equals(String.valueOf(right.get("grants")));
        return !String.valueOf(left.get("roleIds")).equals(String.valueOf(right.get("roleIds"))) || !String.valueOf(left.get("roleScopes")).equals(String.valueOf(right.get("roleScopes")));
    }

    private List<Map<String, Object>> diff(JSONObject before, JSONObject after, String type, JSONObject input) {
        List<String> ids = new ArrayList<String>();
        if (type.startsWith("accounts.")) ids.add(input.getString("id"));
        else for (JSONObject account : rows(before, "accounts")) if (account.getJSONArray("roleIds") != null && account.getJSONArray("roleIds").contains(input.getString("id"))) ids.add(account.getString("id"));
        List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
        for (String id : ids) {
            JSONObject oldAccount = find(before, "accounts", id);
            JSONObject nextAccount = find(after, "accounts", id);
            if (oldAccount == null || nextAccount == null) continue;
            List<JSONObject> oldEffects = effects(before, oldAccount);
            List<JSONObject> nextEffects = effects(after, nextAccount);
            Map<String, Object> row = new LinkedHashMap<String, Object>();
            row.put("id", id);
            row.put("name", oldAccount.getString("name"));
            row.put("added", missing(nextEffects, oldEffects));
            row.put("removed", missing(oldEffects, nextEffects));
            row.put("retained", missing(nextEffects, missing(nextEffects, oldEffects)));
            List<Map<String, String>> lost = new ArrayList<Map<String, String>>();
            for (JSONObject site : rows(before, "sites")) if (hasSite(before, oldAccount, site.getString("id")) && !hasSite(after, nextAccount, site.getString("id"))) {
                Map<String, String> item = new LinkedHashMap<String, String>();
                item.put("id", site.getString("id"));
                item.put("name", site.getString("name"));
                lost.add(item);
            }
            row.put("lostSites", lost);
            row.put("noScope", !anySite(after, nextAccount));
            rows.add(row);
        }
        return rows;
    }

    private List<JSONObject> effects(JSONObject state, JSONObject account) {
        List<JSONObject> effects = new ArrayList<JSONObject>();
        for (JSONObject site : rows(state, "sites")) {
            List<JSONObject> areas = new ArrayList<JSONObject>();
            JSONObject whole = new JSONObject();
            whole.put("id", null);
            whole.put("name", "全厂及未指定区域");
            areas.add(whole);
            for (JSONObject area : rows(state, "areas")) if (site.getString("id").equals(area.getString("siteId"))) areas.add(area);
            for (JSONObject area : areas) for (String operation : OPERATIONS) if (can(state, account, operation, site.getString("id"), area.getString("id"))) {
                JSONObject effect = new JSONObject();
                effect.put("key", operation + "|" + site.getString("id") + "|" + area.getString("id"));
                effect.put("operation", operation);
                effect.put("siteId", site.getString("id"));
                effect.put("siteName", site.getString("name"));
                effect.put("areaId", area.getString("id"));
                effect.put("areaName", area.getString("name"));
                effects.add(effect);
            }
        }
        return effects;
    }

    private List<JSONObject> missing(List<JSONObject> source, List<JSONObject> other) {
        List<String> keys = new ArrayList<String>();
        for (JSONObject row : other) keys.add(row.getString("key"));
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject row : source) if (!keys.contains(row.getString("key"))) rows.add(row);
        return rows;
    }

    private Map<String, Object> audit(JSONObject state, JSONObject actor, String kind, JSONObject input) {
        if (!can(state, actor, "audit:read", input.getString("siteId"), null)) throw AdminQueryService.fail(403, "PERMISSION_DENIED", "无权查看此厂站操作日志");
        List<JSONObject> visible = new ArrayList<JSONObject>();
        for (JSONObject row : rows(state, "audit")) if (input.getString("siteId").equals(row.getString("siteId")) && can(state, actor, "audit:read", row.getString("siteId"), row.getString("areaId"))) visible.add(redact(row));
        if ("auditDetail".equals(kind)) {
            for (JSONObject row : visible) if (input.getString("id").equals(row.getString("id"))) {
                Map<String, Object> body = new LinkedHashMap<String, Object>();
                body.put("availability", "AVAILABLE");
                body.putAll(row);
                return body;
            }
            throw AdminQueryService.fail(404, "AUDIT_NOT_FOUND", "操作日志不存在或不可见");
        }
        String keyword = text(input, "keyword");
        String actorName = text(input, "actorName");
        String objectId = text(input, "objectId");
        String action = text(input, "action");
        String result = text(input, "result");
        long from = date(input, "dateFrom", false);
        long to = date(input, "dateTo", true);
        if (from > 0 && to > 0 && from > to) throw AdminQueryService.fail(400, "INVALID_DATE_RANGE", "开始日期不得晚于结束日期");
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject row : visible) {
            long time = parse(row.getString("occurredAt"));
            if ((from > 0 || to > 0) && time == 0) continue;
            if (from > 0 && time < from || to > 0 && time > to) continue;
            if (!actorName.isEmpty() && !actorName.equals(row.getString("actorName"))) continue;
            if (!objectId.isEmpty() && !objectId.equals(row.getString("objectId"))) continue;
            if (!action.isEmpty() && !action.equals(row.getString("action"))) continue;
            if (!result.isEmpty() && !result.equals(row.getString("result"))) continue;
            String hay = String.valueOf(row.getString("id")) + " " + row.getString("actorName") + " " + row.getString("objectId") + " " + row.getString("action") + " " + row.getString("result") + " " + row.getString("requestId") + " " + row.getString("operationId");
            if (!keyword.isEmpty() && !hay.toLowerCase().contains(keyword.toLowerCase())) continue;
            rows.add(row);
        }
        rows.sort((a, b) -> {
            int time = String.valueOf(b.getString("occurredAt")).compareTo(String.valueOf(a.getString("occurredAt")));
            return time != 0 ? time : String.valueOf(b.getString("id")).compareTo(String.valueOf(a.getString("id")));
        });
        if ("audit".equals(kind)) return page(rows, input);
        String exportedAt = Instant.now().toString();
        List<String> columns = Arrays.asList("id", "siteId", "areaId", "actorName", "action", "objectId", "occurredAt", "result", "requestId", "operationId", "before", "after", "source");
        StringBuilder csv = new StringBuilder().append('\uFEFF');
        csv.append(cell("模拟数据")).append(',').append(cell("后台操作日志")).append("\r\n");
        csv.append(cell("厂站")).append(',').append(cell(input.getString("siteId"))).append("\r\n");
        csv.append(cell("导出时间（UTC）")).append(',').append(cell(exportedAt)).append("\r\n");
        csv.append(cell("记录数")).append(',').append(cell(String.valueOf(rows.size()))).append("\r\n");
        for (int i = 0; i < columns.size(); i++) csv.append(i == 0 ? "" : ",").append(cell(columns.get(i)));
        csv.append("\r\n");
        for (JSONObject row : rows) {
            for (int i = 0; i < columns.size(); i++) csv.append(i == 0 ? "" : ",").append(cell(row.get(columns.get(i))));
            csv.append("\r\n");
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("filename", "audit-" + DateTimeFormatter.ofPattern("yyyyMMddHHmmss").withZone(ZoneOffset.UTC).format(Instant.now()) + ".csv");
        body.put("csv", csv.toString());
        body.put("total", rows.size());
        body.put("exportedAt", exportedAt);
        return body;
    }

    private void auditRow(JSONObject state, JSONObject actor, String type, JSONObject input, JSONObject before, JSONObject after) {
        JSONObject row = new JSONObject();
        row.put("id", "audit-" + nextId(state));
        row.put("siteId", input.getString("siteId"));
        row.put("areaId", after.getString("areaId"));
        row.put("actorId", actor.getString("id"));
        row.put("actorName", actor.getString("name"));
        row.put("action", type);
        row.put("objectId", after.getString("id"));
        row.put("objectName", after.getString("name"));
        row.put("occurredAt", Instant.now().toString());
        row.put("result", "SUCCESS");
        row.put("operationId", input.getString("operationId"));
        row.put("before", before);
        row.put("after", copy(after));
        row.put("source", "后台台账");
        JSONArray audit = state.getJSONArray("audit");
        if (audit == null) { audit = new JSONArray(); state.put("audit", audit); }
        audit.add(row);
    }

    private boolean manageable(JSONObject state, JSONObject actor, JSONObject account) {
        if ("demo-system".equals(actor.getString("id")) && actor.getBooleanValue("enabled")) return !"demo-system".equals(account.getString("id"));
        if (account.getBooleanValue("builtin") || actor.getString("id").equals(account.getString("id")) || !can(state, actor, "accounts:write", account.getString("siteId"), account.getString("areaId"))) return false;
        JSONArray roles = account.getJSONArray("roleIds");
        if (roles == null) return true;
        for (int i = 0; i < roles.size(); i++) if (!DELEGATE.contains(roles.getString(i))) return false;
        return true;
    }

    private boolean can(JSONObject state, JSONObject actor, String operation, String siteId, String areaId) {
        if (actor == null || !actor.getBooleanValue("enabled")) return false;
        JSONObject site = find(state, "sites", siteId);
        if (site != null && !site.getBooleanValue("enabled") && !"sites:write".equals(operation)) return false;
        if ("demo-system".equals(actor.getString("id"))) return true;
        JSONArray roleIds = actor.getJSONArray("roleIds");
        if (roleIds == null) return false;
        for (int i = 0; i < roleIds.size(); i++) {
            JSONObject role = find(state, "roles", roleIds.getString(i));
            if (role == null || !role.getBooleanValue("enabled")) continue;
            JSONObject scope = scopes(actor).getJSONObject(role.getString("id"));
            JSONArray grants = role.getJSONArray("grants");
            if (grants == null) continue;
            for (int g = 0; g < grants.size(); g++) {
                JSONObject grant = grants.getJSONObject(g);
                JSONArray operations = grant.getJSONArray("operations");
                JSONArray sites = grant.getJSONArray("siteIds");
                if (operations == null || sites == null || !(operations.contains("*") || operations.contains(operation)) || !sites.contains(siteId)) continue;
                if (scope != null && scope.getJSONArray("siteIds") != null && !scope.getJSONArray("siteIds").contains(siteId)) continue;
                Object areas = limitedAreas(grant, scope);
                if ("*".equals(areas) || (areaId != null && areas instanceof JSONArray && ((JSONArray) areas).contains(areaId))) return true;
            }
        }
        return false;
    }

    private boolean hasSite(JSONObject state, JSONObject actor, String siteId) {
        if (find(state, "sites", siteId) == null || !find(state, "sites", siteId).getBooleanValue("enabled")) return false;
        if ("demo-system".equals(actor.getString("id")) && actor.getBooleanValue("enabled")) return true;
        JSONArray roleIds = actor.getJSONArray("roleIds");
        if (roleIds == null) return false;
        for (int i = 0; i < roleIds.size(); i++) {
            JSONObject role = find(state, "roles", roleIds.getString(i));
            if (role == null || !role.getBooleanValue("enabled")) continue;
            JSONArray grants = role.getJSONArray("grants");
            if (grants == null) continue;
            for (int g = 0; g < grants.size(); g++) {
                JSONObject grant = grants.getJSONObject(g);
                if (grant.getJSONArray("siteIds") != null && grant.getJSONArray("siteIds").contains(siteId)) return true;
            }
        }
        return false;
    }

    private boolean anySite(JSONObject state, JSONObject actor) {
        for (JSONObject site : rows(state, "sites")) if (hasSite(state, actor, site.getString("id"))) return true;
        return false;
    }

    private static Object limitedAreas(JSONObject grant, JSONObject scope) {
        Object areas = grant.get("areaIds");
        if (scope == null || scope.get("areaIds") == null || "*".equals(scope.get("areaIds"))) return areas;
        if ("*".equals(areas)) return scope.get("areaIds");
        if (areas instanceof JSONArray && scope.get("areaIds") instanceof JSONArray) {
            JSONArray limited = new JSONArray();
            JSONArray wanted = (JSONArray) areas;
            JSONArray allowed = scope.getJSONArray("areaIds");
            for (int i = 0; i < wanted.size(); i++) if (allowed.contains(wanted.getString(i))) limited.add(wanted.getString(i));
            return limited;
        }
        return areas;
    }

    private static boolean covers(JSONObject role, String siteId) {
        JSONArray grants = role.getJSONArray("grants");
        if (grants == null) return false;
        for (int i = 0; i < grants.size(); i++) if (grants.getJSONObject(i).getJSONArray("siteIds") != null && grants.getJSONObject(i).getJSONArray("siteIds").contains(siteId)) return true;
        return false;
    }

    private static boolean grantAllowsAllAreas(JSONObject role, String siteId) {
        JSONArray grants = role.getJSONArray("grants");
        if (grants == null) return false;
        for (int i = 0; i < grants.size(); i++) {
            JSONObject grant = grants.getJSONObject(i);
            if (grant.getJSONArray("siteIds") != null && grant.getJSONArray("siteIds").contains(siteId) && "*".equals(grant.get("areaIds"))) return true;
        }
        return false;
    }

    private static boolean grantAllowsArea(JSONObject role, String siteId, String areaId) {
        JSONArray grants = role.getJSONArray("grants");
        if (grants == null) return false;
        for (int i = 0; i < grants.size(); i++) {
            JSONObject grant = grants.getJSONObject(i);
            if (grant.getJSONArray("siteIds") == null || !grant.getJSONArray("siteIds").contains(siteId)) continue;
            Object areas = grant.get("areaIds");
            if ("*".equals(areas) || (areas instanceof JSONArray && ((JSONArray) areas).contains(areaId))) return true;
        }
        return false;
    }

    private boolean operationsCovered(JSONObject state, JSONObject actor, JSONObject role, String siteId, String areaId) {
        JSONArray grants = role.getJSONArray("grants");
        if (grants == null) return false;
        for (int i = 0; i < grants.size(); i++) {
            JSONObject grant = grants.getJSONObject(i);
            JSONArray operations = grant.getJSONArray("operations");
            if (operations == null) continue;
            for (int o = 0; o < operations.size(); o++) if (!can(state, actor, operations.getString(o), siteId, areaId)) return false;
        }
        return true;
    }

    private static void clearPerson(JSONObject state, String personId) {
        JSONObject person = find(state, "people", personId);
        if (person == null) return;
        person.put("accountId", null);
        person.put("version", person.getIntValue("version") + 1);
    }

    private static JSONObject scopes(JSONObject actor) {
        JSONObject scopes = actor.getJSONObject("roleScopes");
        return scopes == null ? new JSONObject() : scopes;
    }

    private JSONObject read() {
        JSONObject state = ledger.read();
        if (state == null) throw AdminQueryService.fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        return state;
    }

    private JSONObject account(JSONObject state, String id) {
        JSONObject account = find(state, "accounts", id);
        if (account == null || !account.getBooleanValue("enabled")) throw AdminQueryService.fail(401, "IDENTITY_INVALID", "请先登录");
        return account;
    }

    private void put(JSONObject state, String key, JSONObject record, boolean creating) {
        JSONArray list = state.getJSONArray(key);
        if (list == null) { list = new JSONArray(); state.put(key, list); }
        if (creating) list.add(record);
        else for (int i = 0; i < list.size(); i++) if (record.getString("id").equals(list.getJSONObject(i).getString("id"))) list.set(i, record);
    }

    private int nextId(JSONObject state) {
        int next = state.getIntValue("nextId") + 1;
        state.put("nextId", next);
        return next;
    }

    private Map<String, Object> page(List<JSONObject> rows, JSONObject input) {
        int pageNum = input.getIntValue("pageNum");
        int pageSize = input.getIntValue("pageSize");
        if (pageNum <= 0) pageNum = 1;
        if (pageSize <= 0) pageSize = 20;
        if (pageNum < 1 || pageSize > 100) throw AdminQueryService.fail(400, "INVALID_PAGE", "分页参数无效");
        int from = (pageNum - 1) * pageSize;
        List<JSONObject> slice = from >= rows.size() ? new ArrayList<JSONObject>() : new ArrayList<JSONObject>(rows.subList(from, Math.min(from + pageSize, rows.size())));
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.put("rows", slice);
        body.put("total", rows.size());
        body.put("pageNum", pageNum);
        body.put("pageSize", pageSize);
        return body;
    }

    private static JSONObject redact(JSONObject row) {
        return (JSONObject) clean(copy(row));
    }

    private static Object clean(Object value) {
        if (value instanceof JSONArray) {
            JSONArray clean = new JSONArray();
            JSONArray list = (JSONArray) value;
            for (int i = 0; i < list.size(); i++) clean.add(clean(list.get(i)));
            return clean;
        }
        if (value instanceof JSONObject) {
            JSONObject clean = new JSONObject();
            JSONObject object = (JSONObject) value;
            for (String key : object.keySet()) clean.put(key, SECRET.matcher(key).find() ? "[已脱敏]" : clean(object.get(key)));
            return clean;
        }
        return value;
    }

    private static String text(JSONObject input, String key) {
        String value = input.getString(key);
        if (value == null) return "";
        if (value.length() > 100) throw AdminQueryService.fail(400, "INVALID_FILTER", "筛选条件最多100字");
        return value.trim();
    }

    private static long date(JSONObject input, String key, boolean end) {
        String value = text(input, key);
        if (value.isEmpty()) return 0;
        if (!value.matches("\\d{4}-\\d{2}-\\d{2}")) throw AdminQueryService.fail(400, "INVALID_DATE", "日期须为UTC日期或带Z的UTC时间");
        return parse(value + (end ? "T23:59:59.999Z" : "T00:00:00.000Z"));
    }

    private static long parse(String value) {
        try { return value == null ? 0 : Instant.parse(value).toEpochMilli(); }
        catch (RuntimeException error) { return 0; }
    }

    private static String cell(Object value) {
        String text = value == null ? "" : value instanceof String ? (String) value : String.valueOf(value);
        if (text.matches("^[\\s\\u0000-\\u001f\\u007f-\\u009f]*[=+\\-@].*")) text = "'" + text;
        return "\"" + text.replace("\"", "\"\"") + "\"";
    }

    private static String required(JSONObject data, String key, int max, String label) {
        String value = data.getString(key);
        if (value == null || value.trim().isEmpty() || value.trim().length() > max) throw AdminQueryService.fail(400, "VALIDATION_ERROR", "请填写" + label + "（1–" + max + "字）");
        return value.trim();
    }

    private static String blank(String value) { return value == null || value.trim().isEmpty() ? null : value; }

    private static JSONObject copy(JSONObject value) { return value == null ? null : JSONObject.parseObject(value.toJSONString()); }

    private static JSONObject find(JSONObject state, String key, String id) {
        if (id == null) return null;
        for (JSONObject row : rows(state, key)) if (id.equals(row.getString("id"))) return row;
        return null;
    }

    private static List<JSONObject> rows(JSONObject state, String key) {
        List<JSONObject> list = new ArrayList<JSONObject>();
        JSONArray raw = state == null ? null : state.getJSONArray(key);
        if (raw == null) return list;
        for (int i = 0; i < raw.size(); i++) if (raw.getJSONObject(i) != null) list.add(raw.getJSONObject(i));
        return list;
    }

    private static final class Preview {
        private final String actorId;
        private final int revision;
        private final String type;
        private final String fingerprint;
        private Preview(String actorId, int revision, String type, String fingerprint) {
            this.actorId = actorId;
            this.revision = revision;
            this.type = type;
            this.fingerprint = fingerprint;
        }
    }
}
