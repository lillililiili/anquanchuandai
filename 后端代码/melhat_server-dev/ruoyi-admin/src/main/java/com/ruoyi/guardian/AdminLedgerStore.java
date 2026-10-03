package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.util.StreamUtils;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

@Service
public class AdminLedgerStore {
    private static final Pattern CJK = Pattern.compile("[\\u4e00-\\u9fff]");
    private static final List<String> ARRAY_KEYS = Arrays.asList(
            "sites", "organizations", "areas", "people", "dutyShifts",
            "accounts", "roles", "devices", "assignments", "history", "audit");
    private static final Map<String, String> TABLES = arrayTables();

    private final JdbcTemplate jdbc;
    private final Object lock = new Object();
    private TransactionTemplate transactions;

    public AdminLedgerStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        ensureSchema();
    }

    public JSONObject read() {
        synchronized (lock) {
            ensureSchema();
            if (!imported()) importInitial();
            JSONObject state = assemble();
            return readable(state) ? state : null;
        }
    }

    public void write(JSONObject state) {
        if (!readable(state)) throw new GuardianRejected("后台台账无法保存");
        synchronized (lock) {
            ensureSchema();
            transactions().execute(status -> {
                replace(state);
                return null;
            });
        }
    }

    private void importInitial() {
        JSONObject initial = legacy();
        if (!readable(initial)) initial = seed();
        write(initial);
    }

    private JSONObject legacy() {
        List<String> rows = jdbc.query("SELECT body FROM admin_ledger WHERE id = 1", (rs, row) -> rs.getString("body"));
        if (rows.isEmpty() || rows.get(0) == null) return null;
        return JSON.parseObject(rows.get(0));
    }

    private JSONObject seed() {
        try {
            ClassPathResource resource = new ClassPathResource("admin-seed.json");
            return JSON.parseObject(StreamUtils.copyToString(resource.getInputStream(), StandardCharsets.UTF_8));
        } catch (java.io.IOException error) {
            throw new IllegalStateException("后台初始台账不可用", error);
        }
    }

    private boolean imported() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM wearable_meta", Integer.class);
        return count != null && count > 0;
    }

    private JSONObject assemble() {
        JSONObject state = new JSONObject();
        jdbc.query("SELECT revision, next_id FROM wearable_meta WHERE id = 1", rs -> {
            if (rs.next()) {
                state.put("revision", rs.getLong(1));
                state.put("nextId", rs.getLong(2));
            }
            return null;
        });
        for (String key : ARRAY_KEYS) state.put(key, loadRows(TABLES.get(key)));
        state.put("idempotency", loadIdempotency());
        List<Map<String, String>> docs = jdbc.query("SELECT doc_key, body FROM wearable_document ORDER BY doc_key", (rs, row) -> {
            Map<String, String> item = new LinkedHashMap<String, String>();
            item.put("key", rs.getString(1));
            item.put("body", rs.getString(2));
            return item;
        });
        for (Map<String, String> doc : docs) {
            if (ARRAY_KEYS.contains(doc.get("key")) || "idempotency".equals(doc.get("key"))) continue;
            state.put(doc.get("key"), parseValue(doc.get("body")));
        }
        return state;
    }

    private JSONArray loadRows(String table) {
        List<String> bodies = jdbc.query("SELECT body FROM " + table + " ORDER BY sort_order, id", (rs, row) -> rs.getString("body"));
        JSONArray rows = new JSONArray();
        for (String body : bodies) rows.add(JSON.parseObject(body));
        return rows;
    }

    private JSONObject loadIdempotency() {
        JSONObject memory = new JSONObject();
        List<Map<String, String>> rows = jdbc.query("SELECT idem_key, body FROM wearable_idempotency ORDER BY idem_key", (rs, row) -> {
            Map<String, String> item = new LinkedHashMap<String, String>();
            item.put("key", rs.getString(1));
            item.put("body", rs.getString(2));
            return item;
        });
        for (Map<String, String> row : rows) memory.put(row.get("key"), parseValue(row.get("body")));
        return memory;
    }

    private void replace(JSONObject state) {
        jdbc.update("DELETE FROM wearable_meta");
        jdbc.update("INSERT INTO wearable_meta (id, revision, next_id) VALUES (1, ?, ?)", number(state, "revision"), number(state, "nextId"));
        replaceRows("wearable_site", "INSERT INTO wearable_site (id, code, name, time_zone, enabled, version, sort_order, body) VALUES (?,?,?,?,?,?,?,?)", state.getJSONArray("sites"), new SiteBinder());
        replaceRows("wearable_organization", "INSERT INTO wearable_organization (id, site_id, code, name, area_id, parent_id, enabled, version, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?,?)", state.getJSONArray("organizations"), new OrganizationBinder());
        replaceRows("wearable_area", "INSERT INTO wearable_area (id, site_id, code, name, parent_id, enabled, version, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?)", state.getJSONArray("areas"), new AreaBinder());
        replaceRows("wearable_person", "INSERT INTO wearable_person (id, site_id, code, name, organization_id, area_id, account_id, enabled, version, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?,?,?)", state.getJSONArray("people"), new PersonBinder());
        replaceRows("wearable_duty_shift", "INSERT INTO wearable_duty_shift (id, site_id, name, enabled, version, starts_at, ends_at, shift_source, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?,?)", state.getJSONArray("dutyShifts"), new ShiftBinder());
        replaceRows("wearable_account", "INSERT INTO wearable_account (id, login_name, name, site_id, person_id, enabled, builtin, version, credential_version, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?,?,?)", state.getJSONArray("accounts"), new AccountBinder());
        replaceRows("wearable_role", "INSERT INTO wearable_role (id, name, builtin, enabled, version, sort_order, body) VALUES (?,?,?,?,?,?,?)", state.getJSONArray("roles"), new RoleBinder());
        replaceRows("wearable_device", "INSERT INTO wearable_device (id, site_id, area_id, code, name, device_type, lifecycle, relation_state, communication, version, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", state.getJSONArray("devices"), new DeviceBinder());
        replaceRows("wearable_assignment", "INSERT INTO wearable_assignment (id, site_id, device_id, person_id, active, started_at, version, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?)", state.getJSONArray("assignments"), new AssignmentBinder());
        replaceRows("wearable_assignment_history", "INSERT INTO wearable_assignment_history (id, site_id, person_id, device_id, action, occurred_at, sort_order, body) VALUES (?,?,?,?,?,?,?,?)", state.getJSONArray("history"), new HistoryBinder());
        replaceRows("wearable_audit", "INSERT INTO wearable_audit (id, site_id, area_id, actor_id, object_id, action, result, occurred_at, sort_order, body) VALUES (?,?,?,?,?,?,?,?,?,?)", state.getJSONArray("audit"), new AuditBinder());
        jdbc.update("DELETE FROM wearable_idempotency");
        JSONObject memory = state.getJSONObject("idempotency");
        if (memory != null) {
            for (String key : memory.keySet()) {
                jdbc.update("INSERT INTO wearable_idempotency (idem_key, body) VALUES (?, ?)", key, JSON.toJSONString(memory.get(key)));
            }
        }
        jdbc.update("DELETE FROM wearable_document");
        for (String key : state.keySet()) {
            if (ARRAY_KEYS.contains(key) || "revision".equals(key) || "nextId".equals(key) || "idempotency".equals(key)) continue;
            jdbc.update("INSERT INTO wearable_document (doc_key, body) VALUES (?, ?)", key, JSON.toJSONString(state.get(key)));
        }
    }

    private void replaceRows(String table, String sql, JSONArray rows, RowBinder binder) {
        jdbc.update("DELETE FROM " + table);
        if (rows == null) return;
        for (int i = 0; i < rows.size(); i++) {
            JSONObject row = rows.getJSONObject(i);
            if (row == null || text(row, "id") == null) throw new GuardianRejected("后台台账无法保存");
            List<Object> args = new ArrayList<Object>();
            binder.bind(args, row);
            args.add(i);
            args.add(row.toJSONString());
            jdbc.update(sql, args.toArray());
        }
    }

    private void ensureSchema() {
        jdbc.execute("CREATE TABLE IF NOT EXISTS admin_ledger (id TINYINT NOT NULL PRIMARY KEY, body LONGTEXT NOT NULL, updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP)");
        if (transactions != null) return;
        try {
            String sql = StreamUtils.copyToString(new ClassPathResource("db/20261003_wearable_master.sql").getInputStream(), StandardCharsets.UTF_8);
            for (String part : sql.split(";")) {
                String statement = stripComments(part);
                if (!statement.isEmpty()) jdbc.execute(statement);
            }
        } catch (java.io.IOException error) {
            throw new IllegalStateException("主数据表结构不可用", error);
        }
        transactions = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
    }

    private TransactionTemplate transactions() {
        if (transactions == null) ensureSchema();
        return transactions;
    }

    private static Map<String, String> arrayTables() {
        Map<String, String> tables = new LinkedHashMap<String, String>();
        tables.put("sites", "wearable_site");
        tables.put("organizations", "wearable_organization");
        tables.put("areas", "wearable_area");
        tables.put("people", "wearable_person");
        tables.put("dutyShifts", "wearable_duty_shift");
        tables.put("accounts", "wearable_account");
        tables.put("roles", "wearable_role");
        tables.put("devices", "wearable_device");
        tables.put("assignments", "wearable_assignment");
        tables.put("history", "wearable_assignment_history");
        tables.put("audit", "wearable_audit");
        return tables;
    }

    private static String stripComments(String statement) {
        StringBuilder kept = new StringBuilder();
        for (String line : statement.split("\n")) {
            if (line.trim().startsWith("--")) continue;
            kept.append(line).append('\n');
        }
        return kept.toString().trim();
    }

    private static Object parseValue(String body) {
        if (body == null) return null;
        String trimmed = body.trim();
        if (trimmed.startsWith("[")) return JSON.parseArray(trimmed);
        if (trimmed.startsWith("{")) return JSON.parseObject(trimmed);
        return JSON.parse(trimmed);
    }

    private static boolean readable(JSONObject state) {
        if (state == null) return false;
        JSONArray sites = state.getJSONArray("sites");
        if (sites == null || sites.isEmpty()) return false;
        JSONObject site = sites.getJSONObject(0);
        return site != null && site.getString("name") != null && CJK.matcher(site.getString("name")).find();
    }

    private static String text(JSONObject row, String key) {
        if (row == null || !row.containsKey(key) || row.get(key) == null) return null;
        String value = row.getString(key);
        return value == null || value.isEmpty() ? null : value;
    }

    private static Long number(JSONObject row, String key) {
        if (row == null || !row.containsKey(key) || row.get(key) == null) return 0L;
        return row.getLong(key);
    }

    private static Boolean flag(JSONObject row, String key) {
        if (row == null || !row.containsKey(key) || row.get(key) == null) return null;
        return row.getBoolean(key);
    }

    private interface RowBinder {
        void bind(List<Object> args, JSONObject row);
    }

    private static final class SiteBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "code"));
            args.add(text(row, "name"));
            args.add(text(row, "timezone"));
            args.add(flag(row, "enabled"));
            args.add(number(row, "version"));
        }
    }

    private static final class OrganizationBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "code"));
            args.add(text(row, "name"));
            args.add(text(row, "areaId"));
            args.add(text(row, "parentId"));
            args.add(flag(row, "enabled"));
            args.add(number(row, "version"));
        }
    }

    private static final class AreaBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "code"));
            args.add(text(row, "name"));
            args.add(text(row, "parentId"));
            args.add(flag(row, "enabled"));
            args.add(number(row, "version"));
        }
    }

    private static final class PersonBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "code"));
            args.add(text(row, "name"));
            args.add(text(row, "organizationId"));
            args.add(text(row, "areaId"));
            args.add(text(row, "accountId"));
            args.add(flag(row, "enabled"));
            args.add(number(row, "version"));
        }
    }

    private static final class ShiftBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "name"));
            args.add(flag(row, "enabled"));
            args.add(number(row, "version"));
            args.add(text(row, "startsAt"));
            args.add(text(row, "endsAt"));
            args.add(text(row, "source"));
        }
    }

    private static final class AccountBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "loginName"));
            args.add(text(row, "name"));
            args.add(text(row, "siteId"));
            args.add(text(row, "personId"));
            args.add(flag(row, "enabled"));
            args.add(flag(row, "builtin"));
            args.add(number(row, "version"));
            args.add(number(row, "credentialVersion"));
        }
    }

    private static final class RoleBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "name"));
            args.add(flag(row, "builtin"));
            args.add(flag(row, "enabled"));
            args.add(number(row, "version"));
        }
    }

    private static final class DeviceBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "areaId"));
            args.add(text(row, "code"));
            args.add(text(row, "name"));
            args.add(text(row, "type"));
            args.add(text(row, "lifecycle"));
            args.add(text(row, "relation"));
            args.add(text(row, "communication"));
            args.add(number(row, "version"));
        }
    }

    private static final class AssignmentBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "deviceId"));
            args.add(text(row, "personId"));
            args.add(flag(row, "active"));
            args.add(text(row, "startedAt"));
            args.add(number(row, "version"));
        }
    }

    private static final class HistoryBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "personId"));
            args.add(text(row, "deviceId"));
            args.add(text(row, "action"));
            args.add(text(row, "occurredAt"));
        }
    }

    private static final class AuditBinder implements RowBinder {
        public void bind(List<Object> args, JSONObject row) {
            args.add(text(row, "id"));
            args.add(text(row, "siteId"));
            args.add(text(row, "areaId"));
            args.add(text(row, "actorId"));
            args.add(text(row, "objectId"));
            args.add(text(row, "action"));
            args.add(text(row, "result"));
            args.add(text(row, "occurredAt"));
        }
    }
}
