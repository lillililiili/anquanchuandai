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
import java.util.HashSet;
import java.util.Set;

@Service
public class AdminLedgerStore {
    private static final List<String> ARRAY_KEYS = Arrays.asList(
            "sites", "organizations", "areas", "people", "dutyShifts",
            "accounts", "roles", "devices", "assignments", "history", "audit");
    private static final Map<String, String> TABLES = arrayTables();

    private final JdbcTemplate jdbc;
    private final com.ruoyi.common.database.DatabaseDialect dialect;
    private final Object lock = new Object();
    private TransactionTemplate transactions;
    private final boolean demoMode;

    public AdminLedgerStore(JdbcTemplate jdbc) {
        this(jdbc, false);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public AdminLedgerStore(JdbcTemplate jdbc,
            @org.springframework.beans.factory.annotation.Value("${melhat.demo-mode:false}") boolean demoMode) {
        this.jdbc = jdbc;
        this.dialect = com.ruoyi.common.database.DatabaseDialect.of(jdbc);
        this.demoMode = demoMode;
        ensureSchema();
    }

    @org.springframework.beans.factory.annotation.Value("${melhat.cluster.enabled:false}") private boolean clusterEnabled;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableMaintenance maintenance;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private com.ruoyi.cluster.ClusterWorkCoordinator coordinator;
    private final ThreadLocal<Mutation> current = new ThreadLocal<>();
    private static final class Mutation {
        final JSONObject state; final long revision; boolean changed;
        Mutation(JSONObject state) { this.state=state; this.revision=state.getLongValue("revision"); }
    }
    public static final class LedgerSnapshot {
        public final JSONObject state; public final long revision;
        LedgerSnapshot(JSONObject state) { this.state=state; this.revision=state.getLongValue("revision"); }
    }
    private <T>T fenced(java.util.function.Supplier<T> write){return coordinator==null?write.get():coordinator.fenced(write);}
    public LedgerSnapshot readSnapshot() { return new LedgerSnapshot(read()); }

    /** Lock order: maintenance/control fence -> ledger meta -> associated SQL. No network or Guardian callback. */
    public boolean inMutation(){return current.get()!=null;}
    public <T> T mutate(java.util.function.Supplier<T> edit) {
        if(coordinator!=null&&coordinator.enabled()&&current.get()==null)return coordinator.run("media",false,()->mutateProtected(edit));
        return mutateProtected(edit);
    }
    private <T>T mutateProtected(java.util.function.Supplier<T> edit) {
        if(current.get()!=null)return edit.get();
        if(maintenance!=null)maintenance.beginWrite();
        try {
            return fenced(() -> transactions().execute(status -> {
                initializeIfAllowed();
                lockMeta();
                Mutation mutation=new Mutation(assemble());current.set(mutation);
                try {
                    T result=edit.get();
                    if(mutation.changed) {
                        mutation.state.put("revision",mutation.revision+1);
                        replaceExpectedInTransaction(mutation.revision,mutation.state);
                    }
                    return result;
                } finally { current.remove(); }
            }));
        } finally { if(maintenance!=null)maintenance.endWrite(); }
    }
    public JSONObject read() {
        Mutation mutation=current.get();if(mutation!=null)return mutation.state;
        return transactions().execute(status -> {
            initializeIfAllowed();lockMeta();JSONObject state=assemble();
            JSONObject migrated=JSON.parseObject(state.toJSONString());
            boolean changed=WearableModel.migrate(migrated);changed=WearableCredentials.migrate(migrated)||changed;
            if(changed) {
                if(clusterEnabled)throw new IllegalStateException("台账需要显式升级；集群运行时禁止隐式迁移");
                if(maintenance!=null&&maintenance.paused())throw new IllegalStateException("维护期间禁止台账隐式迁移");
                migrated.put("revision",state.getLongValue("revision")+1);
                replaceExpectedInTransaction(state.getLongValue("revision"),migrated);state=migrated;
            }
            return readable(state)?state:null;
        });
    }
    private long lockMeta() {
        return jdbc.queryForObject("SELECT revision FROM wearable_meta WHERE id=1 FOR UPDATE",Long.class);
    }
    /** Compatibility only for local fixtures; production writers must call mutate. */
    public void write(JSONObject state) {
        if(!readable(state))throw new GuardianRejected("后台台账无法保存");
        Mutation mutation=current.get();
        if(mutation!=null) {
            if(state!=mutation.state)throw new IllegalArgumentException("台账写入必须使用当前事务状态");
            mutation.changed=true;return;
        }
        if(clusterEnabled)throw new IllegalStateException("集群禁止裸快照写入；必须使用 mutate 或 replaceExpected");
        transactions().execute(status->{ initializeIfAllowed();long revision=lockMeta();
            if(maintenance!=null&&maintenance.paused())throw new IllegalStateException("维护期间禁止台账写入");
            JSONObject copy=JSON.parseObject(state.toJSONString());copy.put("revision",revision+1);
            replaceExpectedInTransaction(revision,copy);return null; });
    }
    public void replaceExpected(long expectedRevision,JSONObject next) {
        if(!readable(next))throw new GuardianRejected("后台台账无法保存");
        if(maintenance!=null)maintenance.beginWrite();
        try { fenced(()->transactions().execute(status->{long actual=lockMeta();if(actual!=expectedRevision)throw conflict();
            JSONObject copy=JSON.parseObject(next.toJSONString());copy.put("revision",actual+1);
            replaceExpectedInTransaction(actual,copy);return null;}));
        } finally {if(maintenance!=null)maintenance.endWrite();}
    }
    private void replaceExpectedInTransaction(long revision,JSONObject state) {
        // New domain rows acquire canonical model fields inside their explicit mutation, never on a later GET.
        WearableModel.migrate(state);
        if(jdbc.update("UPDATE wearable_meta SET revision=?,next_id=? WHERE id=1 AND revision=?",revision+1,number(state,"nextId"),revision)!=1)throw conflict();
        replace(state);
    }
    private RuntimeException conflict(){return AdminQueryService.fail(409,"VERSION_CONFLICT","台账已变化，请刷新后重试");}
    private void initializeIfAllowed() {
        if(imported())return;
        if(clusterEnabled||com.ruoyi.database.SchemaLifecycle.validateOnly(jdbc))throw new IllegalStateException("集群台账未初始化；请先执行显式迁移");
        if(maintenance!=null&&maintenance.paused())throw new IllegalStateException("维护期间禁止隐式初始化");
        // Schema history is present before this store starts; serialize legacy imports on its stable row.
        jdbc.queryForObject("SELECT version_id FROM wearable_schema_history WHERE version_id='20261003_wearable_master' FOR UPDATE",String.class);
        if(imported())return;
        for(String table:TABLES.values())if(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)>0)
            throw new IllegalStateException("台账迁移标记缺失但业务表已有数据，请先核对；禁止回填或清空");
        for(String table:Arrays.asList("wearable_document","wearable_idempotency"))if(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)>0)
            throw new IllegalStateException("台账迁移标记缺失但业务表已有数据，禁止覆盖");
        JSONObject initial=legacy();if(!readable(initial))initial=demoMode?seed():empty();
        WearableModel.migrate(initial);WearableCredentials.migrate(initial);
        jdbc.update("INSERT INTO wearable_meta(id,revision,next_id) VALUES(1,?,?)",number(initial,"revision"),number(initial,"nextId"));
        replace(initial);
    }

    /** Offline bootstrap only; no endpoint calls this. Caller owns the schema startup gate. */
    void initializeEmpty(JSONObject supplied) {
        transactions().execute(status->{
            jdbc.queryForObject("SELECT version_id FROM wearable_schema_history WHERE version_id='20261003_wearable_master' FOR UPDATE",String.class);
            if(imported())throw new IllegalStateException("Ledger is already initialized");
            for(String table:TABLES.values())if(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)>0)throw new IllegalStateException("Unmarked ledger data; bootstrap refused");
            for(String table:Arrays.asList("wearable_document","wearable_idempotency","admin_ledger"))if(jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)>0)throw new IllegalStateException("Existing ledger data; bootstrap refused");
            JSONObject initial=JSON.parseObject(supplied.toJSONString());
            if(!readable(initial))throw new IllegalArgumentException("Invalid initial ledger");
            for(Object raw:WearableModel.rows(initial,"accounts")){JSONObject account=(JSONObject)raw;
                String hash=account.getString("passwordHash");if(hash==null||!hash.matches("\\$2[aby]\\$[0-9]{2}\\$[./A-Za-z0-9]{53}"))throw new IllegalArgumentException("Bootstrap requires an explicit BCrypt hash for every account; no default credentials");
            }
            WearableModel.migrate(initial);WearableCredentials.migrate(initial);initial.put("revision",1);
            jdbc.update("INSERT INTO wearable_meta(id,revision,next_id) VALUES(1,1,?)",number(initial,"nextId"));replace(initial);return null;
        });
    }

    private static JSONObject empty() {
        JSONObject state = new JSONObject();
        state.put("revision", 0); state.put("nextId", 1);
        for (String key : ARRAY_KEYS) state.put(key, new JSONArray());
        state.put("idempotency", new JSONObject());
        return state;
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
        JSONObject memory = state.getJSONObject("idempotency");
        replaceDocuments("wearable_idempotency", "idem_key", memory == null ? new JSONObject() : memory);
        JSONObject documents = new JSONObject();
        for (String key : state.keySet()) {
            if (ARRAY_KEYS.contains(key) || "revision".equals(key) || "nextId".equals(key) || "idempotency".equals(key)) continue;
            documents.put(key, state.get(key));
        }
        replaceDocuments("wearable_document", "doc_key", documents);
    }

    private void replaceRows(String table, String sql, JSONArray rows, RowBinder binder) {
        Map<String, String> old = new LinkedHashMap<String, String>();
        Map<String, Integer> order = new LinkedHashMap<String, Integer>();
        jdbc.query("SELECT id, body, sort_order FROM " + table, rs -> {
            old.put(rs.getString("id"), rs.getString("body"));
            order.put(rs.getString("id"), rs.getInt("sort_order"));
        });
        Set<String> kept = new HashSet<String>();
        String columns = sql.substring(sql.indexOf('(') + 1, sql.indexOf(')'));
        List<String> names=new ArrayList<String>();for(String column:columns.split(","))names.add(column.trim());
        List<String> updates=new ArrayList<String>(names);updates.remove("id");
        String update=dialect.upsertSql(table,names,Arrays.asList("id"),updates);
        for (int i = 0; rows != null && i < rows.size(); i++) {
            JSONObject row = rows.getJSONObject(i);
            if (row == null || text(row, "id") == null) throw new GuardianRejected("后台台账无法保存");
            String id = row.getString("id");
            if (!kept.add(id)) throw new GuardianRejected("后台台账存在重复编号");
            if (row.toJSONString().equals(old.get(id)) && Integer.valueOf(i).equals(order.get(id))) continue;
            List<Object> args = new ArrayList<Object>();
            binder.bind(args, row);
            args.add(i);
            args.add(row.toJSONString());
            jdbc.update(update.toString(), args.toArray());
        }
        for (String id : old.keySet()) if (!kept.contains(id)) jdbc.update("DELETE FROM " + table + " WHERE id=?", id);
    }

    private void replaceDocuments(String table, String column, JSONObject next) {
        Map<String, String> previous = new LinkedHashMap<String, String>();
        jdbc.query("SELECT " + column + ", body FROM " + table, rs -> { previous.put(rs.getString(1), rs.getString(2)); });
        for (String key : next.keySet()) {
            String body = JSON.toJSONString(next.get(key));
            if (!body.equals(previous.get(key))) dialect.upsert(jdbc,table,Arrays.asList(column,"body"),Arrays.asList(column),key,body);
        }
        for (String key : previous.keySet()) if (!next.containsKey(key)) jdbc.update("DELETE FROM " + table + " WHERE " + column + "=?", key);
    }

    private void ensureSchema() {
        if (transactions != null) return;
        com.ruoyi.database.SchemaLifecycle.ensure(jdbc,"20261003_wearable_master");
        transactions = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        transactions.setTimeout(10);
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
        return sites != null;
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
