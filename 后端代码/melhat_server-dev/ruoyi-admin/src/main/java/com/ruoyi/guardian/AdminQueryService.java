package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class AdminQueryService {
    private static final List<String> READ_ENTITIES = Arrays.asList("people", "organizations", "areas", "sites", "dutyShifts", "accounts", "roles");
    private static final List<String> DELEGATE_ROLES = Arrays.asList("viewer", "people-editor", "asset-operator", "mobile-user");
    private final AdminLedgerStore ledger;
    private final GuardianStore guardian;
    private final ObjectProvider<AdminMaintenanceService> maintenance;

    public AdminQueryService(AdminLedgerStore ledger, GuardianStore guardian, ObjectProvider<AdminMaintenanceService> maintenance) {
        this.ledger = ledger;
        this.guardian = guardian;
        this.maintenance = maintenance;
    }

    public Map<String, Object> query(String accountId, String kind, JSONObject input) {
        JSONObject state = ledger.read();
        if (state == null) throw fail(503, "SOURCE_FAILURE", "后台台账尚未保存");
        JSONObject actor = account(state, accountId);
        if (actor == null) throw fail(401, "IDENTITY_INVALID", "请先登录");
        if (input == null) input = new JSONObject();
        if ("context".equals(kind)) return context(state, actor);
        if ("overview".equals(kind)) return overview(state, actor, input);
        if ("details".equals(kind)) return details(state, actor, input);
        if ("devices".equals(kind) || "device".equals(kind) || "deviceOptions".equals(kind) || "deviceHistory".equals(kind) || "deviceChanges".equals(kind)) return devices(state, actor, kind, input);
        if ("master".equals(kind) || "person".equals(kind) || "record".equals(kind) || "options".equals(kind) || "impacts".equals(kind)) return master(state, actor, kind, input);
        throw fail(400, "UNKNOWN_QUERY", "未实现此查询");
    }

    private Map<String, Object> overview(JSONObject state, JSONObject actor, JSONObject input) {
        String siteId = requiredSite(state, actor, input, "assets:read");
        Map<String, Object> counts = new LinkedHashMap<String, Object>();
        for (String metric : Arrays.asList("assets", "available", "assigned", "unknown", "conflict")) counts.put(metric, rowsFor(state, actor, siteId, metric).size());
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.put("counts", counts);
        return body;
    }

    private Map<String, Object> details(JSONObject state, JSONObject actor, JSONObject input) {
        String siteId = requiredSite(state, actor, input, "assets:read");
        String metric = input.getString("metric");
        if (metric == null || metric.isEmpty()) metric = "assets";
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.putAll(page(rowsFor(state, actor, siteId, metric), input, true));
        return body;
    }

    private Map<String, Object> devices(JSONObject state, JSONObject actor, String kind, JSONObject input) {
        String siteId = requiredSite(state, actor, input, "assets:read");
        if ("deviceOptions".equals(kind)) {
            Map<String, Object> body = new LinkedHashMap<String, Object>();
            body.put("availability", "AVAILABLE");
            body.put("models", models());
            body.put("areas", areas(state, siteId, true));
            body.put("writableAreas", areas(state, siteId, can(state, actor, "assets:write", siteId, null) || system(actor)));
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
                JSONObject row = project(state, actor, device);
                if("PLATFORM".equals(input.getString("source")) && !"PLATFORM".equals(row.getString("source")))continue;
                if (!matches(input, row)) continue;
                String areaId = input.getString("areaId");
                if (areaId != null && !areaId.isEmpty() && !areaId.equals(row.getString("areaId"))) continue;
                String hay = (row.getString("code") + " " + row.getString("sn")).toLowerCase();
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
        if ("device".equals(kind)) return project(state, actor, device);
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

    private Map<String, Object> master(JSONObject state, JSONObject actor, String kind, JSONObject input) {
        if ("options".equals(kind)) return options(state, actor, input);
        String entity = input.getString("entity");
        if ("person".equals(kind)) entity = "people";
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
            if (canReadMaster(state, actor, entity, row)) rows.add(row);
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
                data.put("areaName", nameOf(state, "areas", row.getString("areaId"), "未关联"));
                data.put("equipment", equipment(state, actor, row));
                data.put("slots", personSlots(state, row));
                data.put("accountName", null);
            }
            return data;
        }
        String status = input.getString("status");
        if (status != null && !status.isEmpty() && !"enabled".equals(status) && !"disabled".equals(status)) throw fail(400, "INVALID_FILTER", "无效状态筛选");
        if (status != null && !status.isEmpty()) {
            boolean enabled = "enabled".equals(status);
            List<JSONObject> filtered = new ArrayList<JSONObject>();
            for (JSONObject row : rows) if (row.getBooleanValue("enabled") == enabled) filtered.add(row);
            rows = filtered;
        }
        String organizationId = input.getString("organizationId");
        if (organizationId != null && !organizationId.isEmpty()) rows = keep(rows, "organizationId", organizationId);
        String areaId = input.getString("areaId");
        if (areaId != null && !areaId.isEmpty()) rows = keep(rows, "areaId", areaId);
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("availability", "AVAILABLE");
        body.putAll(page(rows, input, true));
        return body;
    }

    private Map<String, Object> options(JSONObject state, JSONObject actor, JSONObject input) {
        Map<String, Object> data = new LinkedHashMap<String, Object>();
        for (String key : Arrays.asList("sites", "organizations", "areas", "people", "roles")) {
            List<JSONObject> rows = new ArrayList<JSONObject>();
            for (JSONObject row : array(state, key)) {
                if (row.getBooleanValue("enabled") == false && row.containsKey("enabled") && !row.getBooleanValue("enabled")) continue;
                if (!row.getBooleanValue("enabled") && row.containsKey("enabled")) continue;
                if (!"sites".equals(key) && !"roles".equals(key) && input.getString("siteId") != null && !input.getString("siteId").equals(row.getString("siteId"))) continue;
                rows.add(row);
            }
            data.put(key, rows);
        }
        data.put("scopeAreas", array(state, "areas"));
        return data;
    }

    private List<JSONObject> rowsFor(JSONObject state, JSONObject actor, String siteId, String metric) {
        if (!Arrays.asList("assets", "available", "assigned", "unknown", "conflict").contains(metric)) throw fail(400, "INVALID_METRIC", "不支持的明细类型");
        List<JSONObject> rows = new ArrayList<JSONObject>();
        for (JSONObject device : array(state, "devices")) {
            if (!siteId.equals(device.getString("siteId")) || !can(state, actor, "assets:read", device.getString("siteId"), device.getString("areaId"))) continue;
            JSONObject relation = relationship(state, device);
            JSONObject row = project(state, actor, device);
            if ("assets".equals(metric)) rows.add(row);
            else if ("maintenance".equals(metric)) {
                for (JSONObject order : array(state, "maintenanceOrders")) {
                    if (device.getString("id").equals(order.getString("deviceId")) && "OPEN".equals(order.getString("status"))) rows.add(row);
                }
            } else if ("available".equals(metric) && available(state, device)) rows.add(row);
            else if (metric.equalsIgnoreCase(relation.getString("state"))) rows.add(row);
        }
        return rows;
    }

    private JSONObject project(JSONObject state, JSONObject actor, JSONObject device) {
        JSONObject copy = JSONObject.parseObject(device.toJSONString());
        JSONObject relation = relationship(state, device);
        JSONObject person = relation.getJSONObject("person");
        copy.put("relation", relation.getString("state"));
        copy.put("person", person == null ? null : personView(person));
        copy.put("personName", person == null ? null : person.getString("name"));
        JSONObject assignment = relation.getJSONObject("assignment");
        copy.put("startedAt", assignment == null ? null : assignment.getString("startedAt"));
        copy.put("assignmentSource", assignment == null || assignment.getString("source") == null ? "INITIAL_SNAPSHOT" : assignment.getString("source"));
        copy.put("areaName", nameOf(state, "areas", device.getString("areaId"), "未分配区域"));
        copy.put("modelName", modelName(device.getString("type")));
        copy.put("declaration", declaration(device.getString("type")));


        copy.put("writable", !"SCRAPPED".equals(device.getString("lifecycle")));
        applyTelemetry(copy);
        return copy;
    }

    private void applyTelemetry(JSONObject device) {
        if ("PLATFORM".equals(device.getString("source"))) {
            try { if(java.time.Instant.parse(device.getString("sourceTime")).isBefore(java.time.Instant.now().minusSeconds(300))) {
                device.put("communication","UNKNOWN");device.put("freshness","STALE");
            }} catch(Exception error) { device.put("communication","UNKNOWN"); }
            return;
        }
        JSONObject remote = snapshotDevice(device.getString("portalDeviceId") != null ? device.getString("portalDeviceId") : device.getString("code"));
        if (remote == null) remote = snapshotDevice(device.getString("id"));
        if (remote == null || !remote.containsKey("online")) return;
        device.put("communication", remote.getBooleanValue("online") ? "ONLINE" : "OFFLINE");
        device.put("battery", remote.get("battery"));
        device.put("freshness", "CURRENT");
        if (remote.getString("updated") != null) device.put("sourceTime", remote.getString("updated"));
    }

    private JSONObject snapshotDevice(String id) {
        if (id == null) return null;
        JSONObject snapshot = guardian.snapshot();
        if (snapshot == null) return null;
        for (JSONObject device : array(snapshot, "devices")) if (id.equals(device.getString("id"))) return device;
        return null;
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
        for (JSONObject device : array(state, "devices")) {
            boolean open = false;
            for (JSONObject assignment : array(state, "assignments")) {
                if (assignment.getBooleanValue("active") && person.getString("id").equals(assignment.getString("personId")) && device.getString("id").equals(assignment.getString("deviceId"))) open = true;
            }
            if (open) rows.add(project(state, actor, device));
        }
        return rows;
    }

    private List<Map<String, Object>> impacts(JSONObject state, String entity, JSONObject row, boolean all) {
        List<Map<String, Object>> results = new ArrayList<Map<String, Object>>();
        if ("people".equals(entity)) {
            for (JSONObject assignment : array(state, "assignments")) if (assignment.getBooleanValue("active") && row.getString("id").equals(assignment.getString("personId"))) results.add(impact(assignment.getString("id"), assignment.getString("id"), "有效领用关系（请到发放回收页面归还或核实）"));
            for (JSONObject shift : array(state, "dutyShifts")) {
                JSONArray members = shift.getJSONArray("personIds");
                if (!shift.getBooleanValue("enabled") || members == null || !members.contains(row.getString("id"))) continue;
                String ends = shift.getString("endsAt");
                try {
                    if (ends != null && java.time.Instant.parse(ends).isAfter(java.time.Instant.now())) results.add(impact(shift.getString("id"), shift.getString("name"), "当前或未来名册"));
                } catch (RuntimeException ignored) { /* 无法解析的班次不当作活动引用 */ }
            }
            JSONObject snapshot = guardian.snapshot();
            String portalId = row.getString("portalId");
            if (portalId == null || portalId.isEmpty()) portalId = row.getString("id");
            if (snapshot != null && portalId != null) {
                for (JSONObject work : array(snapshot, "works")) {
                    if ("已结束".equals(work.getString("status"))) continue;
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
            for (JSONObject person : array(state, "people")) if (row.getString("id").equals(person.getString("organizationId")) && (all || person.getBooleanValue("enabled"))) results.add(impact(person.getString("id"), person.getString("name"), "人员引用"));
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
        int from = (pageNum - 1) * pageSize;
        List<JSONObject> slice = from >= filtered.size() ? new ArrayList<JSONObject>() : filtered.subList(from, Math.min(from + pageSize, filtered.size()));
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
        if (!enabled || !can(state, actor, operation, siteId, null)) throw fail(403, "PERMISSION_DENIED", "当前身份无此查询权限");
        return siteId;
    }

    private boolean can(JSONObject state, JSONObject actor, String operation, String siteId, String areaId) {
        if (system(actor)) return true;
        for (JSONObject role : array(state, "roles")) {
            if (!actor.getJSONArray("roleIds").contains(role.getString("id")) || role.getBooleanValue("enabled") == false) continue;
            JSONArray grants = role.getJSONArray("grants");
            if (grants == null) continue;
            for (int i = 0; i < grants.size(); i++) {
                JSONObject grant = grants.getJSONObject(i);
                JSONArray operations = grant.getJSONArray("operations");
                JSONArray sites = grant.getJSONArray("siteIds");
                if (operations == null || sites == null || !sites.contains(siteId)) continue;
                if (!(operations.contains("*") || operations.contains(operation))) continue;
                JSONObject scopes=actor.getJSONObject("roleScopes");
                JSONObject scope=scopes==null?null:scopes.getJSONObject(role.getString("id"));
                if(scope!=null && scope.getJSONArray("siteIds")!=null && !scope.getJSONArray("siteIds").contains(siteId)) continue;
                Object areas = grant.get("areaIds");
                if(scope!=null && scope.get("areaIds")!=null && !"*".equals(scope.get("areaIds"))) {
                    JSONArray limit=scope.getJSONArray("areaIds");
                    if("*".equals(areas)) areas=limit;
                    else { JSONArray intersection=new JSONArray();if(areas instanceof JSONArray)for(Object a:(JSONArray)areas)if(limit.contains(a))intersection.add(a);areas=intersection; }
                }
                if ("*".equals(areas) || areaId == null && areas instanceof JSONArray && !((JSONArray)areas).isEmpty()) return true;
                if (areas instanceof JSONArray && ((JSONArray) areas).contains(areaId)) return true;
            }
        }
        return false;
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
                    if ("*".equals(grant.areaIds)) {
                        if (!scopedCan(state, actor, operation, siteId, null)) return false;
                    } else if (grant.areaIds instanceof JSONArray) {
                        JSONArray areas = (JSONArray) grant.areaIds;
                        for (int a = 0; a < areas.size(); a++) if (!scopedCan(state, actor, operation, siteId, areas.getString(a))) return false;
                    } else return false;
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
            if ("*".equals(grant.areaIds)) return true;
            if (grant.areaIds instanceof JSONArray) {
                JSONArray areas = (JSONArray) grant.areaIds;
                for (int i = 0; i < areas.size(); i++) {
                    JSONObject area = find(state, "areas", areas.getString(i));
                    if (area != null && siteId.equals(area.getString("siteId")) && area.getBooleanValue("enabled")) return true;
                }
            }
        }
        return false;
    }

    private boolean scopedCan(JSONObject state, JSONObject actor, String operation, String siteId, String areaId) {
        JSONObject site = find(state, "sites", siteId);
        if (site != null && !site.getBooleanValue("enabled") && !"sites:write".equals(operation)) return false;
        for (ScopeGrant grant : grantsOf(state, actor)) {
            if (grant.operations == null || grant.siteIds == null || !grant.siteIds.contains(siteId)) continue;
            if (!(grant.operations.contains("*") || grant.operations.contains(operation))) continue;
            if ("*".equals(grant.areaIds)) return true;
            if (areaId != null && grant.areaIds instanceof JSONArray && ((JSONArray) grant.areaIds).contains(areaId)) return true;
        }
        return false;
    }

    private List<ScopeGrant> grantsOf(JSONObject state, JSONObject actor) {
        List<ScopeGrant> grants = new ArrayList<ScopeGrant>();
        if (actor == null || !actor.getBooleanValue("enabled")) return grants;
        JSONArray roleIds = actor.getJSONArray("roleIds");
        if (roleIds == null) return grants;
        JSONObject scopes = actor.getJSONObject("roleScopes");
        for (int i = 0; i < roleIds.size(); i++) {
            JSONObject role = find(state, "roles", roleIds.getString(i));
            if (role == null || !role.getBooleanValue("enabled")) continue;
            JSONObject limit = scopes == null ? null : scopes.getJSONObject(role.getString("id"));
            JSONArray roleGrants = role.getJSONArray("grants");
            if (roleGrants == null) continue;
            for (int g = 0; g < roleGrants.size(); g++) {
                JSONObject grant = roleGrants.getJSONObject(g);
                ScopeGrant item = new ScopeGrant();
                item.operations = grant.getJSONArray("operations");
                item.siteIds = limitSites(grant.getJSONArray("siteIds"), limit);
                item.areaIds = limitAreas(grant.get("areaIds"), limit);
                grants.add(item);
            }
        }
        return grants;
    }

    private static JSONArray limitSites(JSONArray sites, JSONObject limit) {
        if (limit == null || limit.getJSONArray("siteIds") == null) return sites;
        JSONArray allowed = limit.getJSONArray("siteIds");
        JSONArray limited = new JSONArray();
        if (sites == null) return limited;
        for (int i = 0; i < sites.size(); i++) if (allowed.contains(sites.getString(i))) limited.add(sites.getString(i));
        return limited;
    }

    private static Object limitAreas(Object areas, JSONObject limit) {
        if (limit == null || limit.get("areaIds") == null || "*".equals(limit.get("areaIds"))) return areas;
        if ("*".equals(areas)) return limit.get("areaIds");
        if (areas instanceof JSONArray && limit.get("areaIds") instanceof JSONArray) {
            JSONArray limited = new JSONArray();
            JSONArray allowed = limit.getJSONArray("areaIds");
            JSONArray wanted = (JSONArray) areas;
            for (int i = 0; i < wanted.size(); i++) if (allowed.contains(wanted.getString(i))) limited.add(wanted.getString(i));
            return limited;
        }
        return areas;
    }

    private static final class ScopeGrant {
        private JSONArray operations;
        private JSONArray siteIds;
        private Object areaIds;
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
