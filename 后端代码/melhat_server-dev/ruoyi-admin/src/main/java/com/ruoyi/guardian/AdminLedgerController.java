package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/admin/v1")
public class AdminLedgerController {
    private final AdminLedgerStore store;
    private final AdminQueryService queries;
    private final AdminDeviceService devices;
    private final AdminAssignmentService assignments;
    private final AdminMaintenanceService maintenance;
    private final AdminMasterService master;
    private final AdminAccessService access;

    public AdminLedgerController(AdminLedgerStore store, AdminQueryService queries, AdminDeviceService devices, AdminAssignmentService assignments, AdminMaintenanceService maintenance, AdminMasterService master, AdminAccessService access) {
        this.store = store;
        this.queries = queries;
        this.devices = devices;
        this.assignments = assignments;
        this.maintenance = maintenance;
        this.master = master;
        this.access = access;
    }

    @GetMapping("/state")
    public Map<String, Object> read() {
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("state", store.read());
        return body;
    }

    @PutMapping("/state")
    public Map<String, Object> write(@RequestBody JSONObject state) {
        store.write(state);
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("ok", true);
        return body;
    }

    @PostMapping("/execute")
    public JSONObject execute(@RequestBody JSONObject body) {
        String accountId = body == null ? "" : body.getString("accountId");
        String type = body == null ? "" : body.getString("type");
        JSONObject input = body == null ? new JSONObject() : body.getJSONObject("input");
        if (type != null && access.handles(type)) return access.execute(accountId, type, input);
        if (type != null && master.handles(type)) return master.execute(accountId, type, input);
        if (type != null && maintenance.handles(type)) return maintenance.execute(accountId, type, input);
        if (type != null && type.startsWith("assignments.")) return assignments.execute(accountId, type, input);
        return devices.execute(accountId, type, input);
    }

    @PostMapping("/query")
    public Map<String, Object> query(@RequestBody JSONObject body) {
        String accountId = body == null ? "" : body.getString("accountId");
        String kind = body == null ? "" : body.getString("kind");
        JSONObject input = body == null ? new JSONObject() : body.getJSONObject("input");
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("code", 200);
        result.put("data", access.handlesQuery(kind) ? access.query(accountId, kind, input) : maintenance.handlesQuery(kind) ? maintenance.query(accountId, kind, input) : assignments.handlesQuery(kind) ? assignments.query(accountId, kind, input) : queries.query(accountId, kind, input));
        return result;
    }

    @org.springframework.web.bind.annotation.ExceptionHandler(AdminQueryService.QueryFailed.class)
    public org.springframework.http.ResponseEntity<Map<String, Object>> queryFailed(AdminQueryService.QueryFailed error) {
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("code", error.code);
        body.put("errorCode", error.errorCode);
        body.put("message", error.getMessage());
        return org.springframework.http.ResponseEntity.status(error.code).body(body);
    }

    @PostMapping("/login")
    public Map<String, Object> login(@RequestBody JSONObject body) {
        String username = body == null ? "" : String.valueOf(body.getString("username"));
        String password = body == null ? "" : String.valueOf(body.getString("password"));
        JSONObject account = findAccount(store.read(), username);
        if (account == null || !"Admin@2026".equals(password)) throw new AdminUnauthorized("账号或密码错误，或账号已停用");
        Map<String, Object> identity = new LinkedHashMap<String, Object>();
        identity.put("id", account.getString("id"));
        identity.put("name", account.getString("name"));
        identity.put("loginName", account.getString("loginName"));
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("identity", identity);
        return result;
    }

    private static JSONObject findAccount(JSONObject state, String username) {
        if (state == null || username == null || username.trim().isEmpty()) return null;
        JSONArray accounts = state.getJSONArray("accounts");
        if (accounts == null) return null;
        for (int i = 0; i < accounts.size(); i++) {
            JSONObject account = accounts.getJSONObject(i);
            if (account == null || !account.getBooleanValue("enabled")) continue;
            if (username.equals(account.getString("loginName")) || username.equals(account.getString("id"))) return account;
        }
        return null;
    }

    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public static class AdminUnauthorized extends RuntimeException {
        public AdminUnauthorized(String message) {
            super(message);
        }
    }
}
