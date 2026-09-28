package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.regex.Pattern;

@Service
public class AdminLedgerStore {
    private static final Pattern CJK = Pattern.compile("[\\u4e00-\\u9fff]");
    private final JdbcTemplate jdbc;
    private final Object lock = new Object();

    public AdminLedgerStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        jdbc.execute("CREATE TABLE IF NOT EXISTS admin_ledger (id TINYINT NOT NULL PRIMARY KEY, body LONGTEXT NOT NULL, updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP) DEFAULT CHARSET=utf8mb4");
    }

    public JSONObject read() {
        synchronized (lock) {
            List<String> rows = jdbc.query("SELECT body FROM admin_ledger WHERE id = 1", (rs, row) -> rs.getString("body"));
            if (rows.isEmpty()) return null;
            JSONObject state = JSON.parseObject(rows.get(0));
            if (!readable(state)) return null;
            return state;
        }
    }

    public void write(JSONObject state) {
        if (!readable(state)) throw new GuardianRejected("后台台账无法保存");
        String body = new String(JSON.toJSONBytes(state), StandardCharsets.UTF_8);
        synchronized (lock) {
            int updated = jdbc.update("UPDATE admin_ledger SET body = ?, updated_at = CURRENT_TIMESTAMP WHERE id = 1", body);
            if (updated == 0) jdbc.update("INSERT INTO admin_ledger (id, body) VALUES (1, ?)", body);
        }
    }

    private static boolean readable(JSONObject state) {
        if (state == null) return false;
        JSONArray sites = state.getJSONArray("sites");
        if (sites == null || sites.isEmpty()) return false;
        JSONObject site = sites.getJSONObject(0);
        return site != null && site.getString("name") != null && CJK.matcher(site.getString("name")).find();
    }
}
