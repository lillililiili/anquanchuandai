package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminPersonHistoryTest {
    JdbcTemplate jdbc;
    AdminLedgerStore ledger;
    GuardianStore guardian;

    @BeforeEach void setup() {
        jdbc = new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID()
                + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE", "sa", ""));
        ledger = new AdminLedgerStore(jdbc);
        JSONObject state = ledger.read();
        state.put("sites", JSONArray.of(site("site-1"), site("site-2")));
        state.put("accounts", JSONArray.of(account("demo-system", "经办员", "system"),
                account("reader", "只读人员", "reader-role"), account("people-reader", "人员查看员", "people-role")));
        state.put("roles", JSONArray.of(role("reader-role", "assets:read", "people:read"), role("people-role", "people:read")));
        state.put("people", JSONArray.of(person("person-A", "site-1"), person("person-B", "site-1"), person("person-C", "site-2")));
        state.put("devices", JSONArray.of(device("helmet-A", "site-1", "HELMET"), device("belt-A", "site-1", "BELT"),
                device("helmet-B", "site-1", "HELMET"), device("helmet-C", "site-2", "HELMET")));
        ledger.write(state);
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenReturn(object("devices", new JSONArray()));
    }

    JSONObject site(String id) { return object("id", id, "name", id, "enabled", true, "version", 1); }
    JSONObject account(String id, String name, String role) {
        return object("id", id, "name", name, "loginName", id, "siteId", "site-1", "enabled", true,
                "version", 1, "roleIds", JSONArray.of(role));
    }
    JSONObject role(String id, String... operations) {
        JSONArray ops = new JSONArray();
        for (String operation : operations) ops.add(operation);
        return object("id", id, "enabled", true, "grants", JSONArray.of(object("operations", ops, "siteIds", JSONArray.of("site-1"))));
    }
    JSONObject person(String id, String site) {
        return object("id", id, "siteId", site, "name", "人员-" + id, "code", "CODE-" + id, "enabled", true, "version", 1,
                "equipmentEvidence", object("HELMET", "COMPLETE", "BELT", "COMPLETE", "WATCH", "COMPLETE"));
    }
    JSONObject device(String id, String site, String type) {
        return object("id", id, "siteId", site, "name", "设备-" + id, "code", "CODE-" + id, "type", type,
                "source", "HELMET".equals(type) ? "DIRECT_HELMET" : "DIRECT_BELT", "deviceNumber", "LOGIN-" + id,
                "lifecycle", "STOCK", "relation", "UNASSIGNED", "version", 1);
    }
    AdminQueryService queries(AdminLedgerStore store) {
        return new AdminQueryService(store, guardian, mock(ObjectProvider.class));
    }
    AdminAssignmentService assignments(AdminLedgerStore store) { return new AdminAssignmentService(store, guardian, queries(store)); }
    JSONObject request(String personId, String operation, boolean returning, String... deviceIds) {
        JSONObject state = ledger.read();
        JSONObject person = find(state, "people", personId);
        JSONArray items = new JSONArray();
        for (String id : deviceIds) {
            JSONObject device = find(state, "devices", id);
            JSONObject item = object("deviceId", id, "deviceVersion", device.getIntValue("version"));
            if (returning) for (Object raw : rows(state, "assignments")) {
                JSONObject link = (JSONObject) raw;
                if (id.equals(link.getString("deviceId")) && link.getBooleanValue("active")) {
                    item.put("assignmentId", link.getString("id")); item.put("assignmentVersion", link.getIntValue("version"));
                    item.put("condition", "GOOD");
                }
            }
            items.add(item);
        }
        return object("siteId", person.getString("siteId"), "personId", personId, "personVersion", person.getIntValue("version"),
                "operationId", operation, "acknowledged", true, "items", items);
    }
    JSONObject operate(boolean returning, String personId, String operation, String... ids) {
        return assignments(ledger).execute("demo-system", returning ? "assignments.return" : "assignments.issue",
                request(personId, operation, returning, ids));
    }
    Map<String, Object> history(String actor, JSONObject options) {
        JSONObject input = object("siteId", "site-1", "pageNum", 1, "pageSize", 100);
        input.putAll(options);
        AdminLedgerStore restarted = new AdminLedgerStore(jdbc);
        return assignments(restarted).query(actor, "assignmentHistory", input);
    }
    List<JSONObject> historyRows(Map<String, Object> result) { return (List<JSONObject>) result.get("rows"); }
    Map<String, Object> detail(String actor) {
        return queries(new AdminLedgerStore(jdbc)).query(actor, "person", object("siteId", "site-1", "id", "person-A"));
    }

    @Test void issueAndReturnPersistOneSnapshotPerItemAcrossStoreAndServiceRestart() {
        JSONObject issued = operate(false, "person-A", "issue-batch", "helmet-A", "belt-A").getJSONObject("data");
        JSONObject giveBack = request("person-A", "return-batch", true, "helmet-A", "belt-A");
        JSONObject returned = assignments(ledger).execute("demo-system", "assignments.return", giveBack);
        assertEquals(returned.toJSONString(), assignments(new AdminLedgerStore(jdbc)).execute("demo-system", "assignments.return", giveBack).toJSONString());
        assertEquals(4, jdbc.queryForObject("SELECT COUNT(*) FROM wearable_assignment_history", Integer.class));
        List<JSONObject> history = historyRows(history("demo-system", object("personId", "person-A")));
        assertEquals(4, history.size());
        assertEquals("RETURN", history.get(0).getString("action"));
        assertEquals("ISSUE", history.get(3).getString("action"));
        for (JSONObject row : history) {
            assertEquals("person-A", row.getString("personId"));
            assertEquals("人员-person-A", row.getString("personName"));
            assertEquals("CODE-person-A", row.getString("personCode"));
            assertEquals("demo-system", row.getString("actorId"));
            assertEquals("经办员", row.getString("actorName"));
            assertEquals("设备-" + row.getString("deviceId"), row.getString("deviceName"));
            assertEquals("CODE-" + row.getString("deviceId"), row.getString("deviceCode"));
            assertNotNull(Instant.parse(row.getString("occurredAt")));
            assertNotNull(Instant.parse(row.getString("startedAt")));
            assertNotNull(row.getString("assignmentId"));
        }
        assertEquals(2, history("demo-system", object("batchId", issued.getString("batchId"))).get("total"));
        assertTrue(((List<?>) detail("demo-system").get("equipment")).isEmpty());
        JSONObject state = ledger.read();
        find(state, "people", "person-A").put("name", "改名人员");
        find(state, "devices", "helmet-A").put("code", "改号设备");
        find(state, "accounts", "demo-system").put("name", "改名经办员");
        ledger.write(state);
        assertEquals(history, historyRows(history("demo-system", object("personId", "person-A"))), "history retains the recorded identities");
    }

    @Test void existingAssignmentSnapshotDoesNotFabricateHistory() {
        JSONObject state = ledger.read();
        state.getJSONArray("assignments").add(object("id", "legacy-link", "siteId", "site-1", "personId", "person-A", "deviceId", "helmet-A",
                "active", true, "startedAt", "2026-01-01T00:00:00Z", "version", 1));
        find(state, "devices", "helmet-A").put("lifecycle", "IN_USE");
        find(state, "devices", "helmet-A").put("relation", "ASSIGNED");
        ledger.write(state);
        assertEquals(0, history("demo-system", object("personId", "person-A")).get("total"));
        assertEquals(1, ((List<?>) detail("demo-system").get("equipment")).size());
    }

    @Test void historyFiltersRespectPersonSitePermissionActionAndPageBoundaries() {
        operate(false, "person-A", "issue-A", "helmet-A", "belt-A");
        operate(true, "person-A", "return-A", "helmet-A", "belt-A");
        operate(false, "person-B", "issue-B", "helmet-B");
        operate(false, "person-C", "issue-C", "helmet-C");
        assertEquals(5, history("reader", new JSONObject()).get("total"));
        assertEquals(4, history("reader", object("personId", "person-A")).get("total"));
        assertEquals(1, history("reader", object("personId", "person-A", "type", "HELMET", "action", "RETURN", "keyword", "CODE-helmet-A")).get("total"));
        Map<String, Object> second = history("reader", object("personId", "person-A", "pageNum", 2, "pageSize", 2));
        assertEquals(4, second.get("total"));
        assertEquals(2, historyRows(second).size());
        assertEquals("ISSUE", historyRows(second).get(0).getString("action"));
        assertTrue(historyRows(history("reader", object("pageNum", Integer.MAX_VALUE))).isEmpty());
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> history("reader", object("siteId", "site-2"))).code);
        assertEquals(404, assertThrows(AdminQueryService.QueryFailed.class, () -> history("reader", object("personId", "person-C"))).code);
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> history("people-reader", object("personId", "person-A"))).code);
    }

    @Test void failedHistoryWriteRollsBackReturnAndVersionsTogether() {
        operate(false, "person-A", "issue-rollback", "helmet-A", "belt-A");
        JSONObject before = ledger.read();
        jdbc.execute("ALTER TABLE wearable_assignment_history ADD CONSTRAINT history_return_failure CHECK (action <> 'RETURN')");
        assertThrows(RuntimeException.class, () -> operate(true, "person-A", "return-rollback", "helmet-A", "belt-A"));
        assertEquals(before, new AdminLedgerStore(jdbc).read());
        assertEquals(2, history("demo-system", object("personId", "person-A")).get("total"));
    }

    @Test void personDetailResolvesBothAccountLinkDirectionsWithoutExposingHiddenAccounts() {
        JSONObject state = ledger.read();
        JSONObject linked = account("linked-account", "关联账号", "reader-role");
        linked.put("personId", "person-A"); state.getJSONArray("accounts").add(linked); ledger.write(state);
        assertEquals("关联账号", detail("demo-system").get("accountName"));
        assertNull(detail("people-reader").get("accountName"));
        state = ledger.read();
        find(state, "accounts", "linked-account").remove("personId");
        find(state, "people", "person-A").put("accountId", "linked-account"); ledger.write(state);
        assertEquals("关联账号", detail("demo-system").get("accountName"));
        assertNull(detail("people-reader").get("accountName"));
        state = ledger.read();
        find(state, "people", "person-A").put("accountId", "people-reader"); ledger.write(state);
        assertEquals("人员查看员", detail("people-reader").get("accountName"), "the actor may see their own linked account");
        state = ledger.read();
        find(state, "people", "person-A").put("accountId", "missing-account"); ledger.write(state);
        assertNull(detail("demo-system").get("accountName"));
    }
}
