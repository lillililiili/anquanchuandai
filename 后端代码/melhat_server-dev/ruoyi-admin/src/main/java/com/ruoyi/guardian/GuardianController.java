package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/guardian/v1")
public class GuardianController {
    @org.springframework.beans.factory.annotation.Autowired private WearableSessions sessions;
    private final GuardianStore store;
    private final GuardianFiles files;
    private final AdminLedgerStore ledger;
    private final GuardianVoiceService voice;

    public GuardianController(GuardianStore store, GuardianFiles files, AdminLedgerStore ledger, GuardianVoiceService voice) {
        this.store = store;
        this.files = files;
        this.ledger = ledger;
        this.voice = voice;
    }

    @PostMapping("/login")
    public Map<String, Object> login(@RequestBody JSONObject body) {
        String account = body == null ? null : body.getString("account");
        String password = body == null ? null : body.getString("password");
        JSONObject duty = accountById("demo-duty");
        String loginName = duty == null || duty.getString("loginName") == null ? "duty" : duty.getString("loginName");
        if (duty == null || !duty.getBooleanValue("enabled") || !loginName.equals(account) || !"123456".equals(password)) {
            throw new GuardianUnauthorized("账号或密码错误。");
        }
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("ok", true);
        result.put("operator", operatorBody());
        result.put("token", sessions.issue(duty, "guardian"));
        return result;
    }

    @PostMapping("/logout")
    public Map<String, Object> logout(HttpServletRequest request) {
        sessions.revoke(request); return java.util.Collections.singletonMap("ok", true);
    }

    @PostMapping("/broadcast")
    public Map<String, Object> broadcast(@RequestBody JSONObject body) {
        voice.broadcast(body == null ? null : body.getJSONArray("hats"), body == null ? null : body.getString("content"));
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("ok", true);
        return result;
    }

    @PostMapping("/call")
    public Map<String, Object> call(@RequestBody JSONObject body) {
        Map<String, Object> result = voice.call(body == null ? null : body.getJSONArray("hats"));
        result.put("ok", true);
        return result;
    }

    @PostMapping("/call/end")
    public Map<String, Object> endCall(@RequestBody JSONObject body) {
        voice.end(body == null ? null : body.getString("channel"));
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("ok", true);
        return result;
    }

    @GetMapping("/operator")
    public Map<String, Object> operator() {
        return operatorBody();
    }

    private Map<String, Object> operatorBody() {
        JSONObject duty = accountById("demo-duty");
        JSONObject role = roleById(duty == null ? "duty" : firstRole(duty));
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("loginName", duty == null || duty.getString("loginName") == null ? "duty" : duty.getString("loginName"));
        body.put("name", duty == null || duty.getString("name") == null ? "值守员" : duty.getString("name"));
        body.put("roleName", role == null || role.getString("name") == null ? "平台值守员" : role.getString("name"));
        return body;
    }

    private JSONObject accountById(String id) {
        JSONObject state = ledger.read();
        if (state == null) return null;
        JSONArray accounts = state.getJSONArray("accounts");
        if (accounts == null) return null;
        for (int i = 0; i < accounts.size(); i++) {
            JSONObject account = accounts.getJSONObject(i);
            if (account != null && id.equals(account.getString("id"))) return account;
        }
        return null;
    }

    private JSONObject roleById(String id) {
        JSONObject state = ledger.read();
        if (state == null || id == null) return null;
        JSONArray roles = state.getJSONArray("roles");
        if (roles == null) return null;
        for (int i = 0; i < roles.size(); i++) {
            JSONObject role = roles.getJSONObject(i);
            if (role != null && id.equals(role.getString("id"))) return role;
        }
        return null;
    }

    private static String firstRole(JSONObject account) {
        JSONArray roleIds = account.getJSONArray("roleIds");
        if (roleIds == null || roleIds.isEmpty()) return "duty";
        return roleIds.getString(0);
    }

    @PutMapping("/files/{id}")
    public Map<String, Object> saveFile(@PathVariable("id") String id, HttpServletRequest request) {
        try {
            files.save(id, request.getContentType(), request.getInputStream());
        } catch (IOException error) {
            throw new GuardianRejected("照片保存失败，请检查磁盘空间");
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("ok", true);
        return body;
    }

    @GetMapping("/files/{id}")
    public ResponseEntity<byte[]> readFile(@PathVariable("id") String id) {
        GuardianFiles.Stored stored = files.read(id);
        if (stored == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(stored.type)).body(stored.bytes);
    }

    @GetMapping("/snapshot")
    public Map<String, Object> snapshot() {
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("state", store.snapshot());
        return body;
    }

    @PutMapping("/snapshot")
    public Map<String, Object> replace(@RequestBody JSONObject state, @org.springframework.web.bind.annotation.RequestHeader("X-Wearable-Revision") int expectedSeq) {
        try {
            store.replaceFromClient(state, expectedSeq);
        } catch (IllegalArgumentException error) {
            throw new GuardianRejected(error.getMessage());
        } catch (IllegalStateException error) {
            throw new GuardianRejected(error.getMessage() == null ? "监护数据保存失败" : error.getMessage());
        }
        Map<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("ok", true);
        return body;
    }
}
