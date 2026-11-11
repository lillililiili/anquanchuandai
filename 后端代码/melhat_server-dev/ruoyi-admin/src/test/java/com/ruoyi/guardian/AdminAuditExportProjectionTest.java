package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.util.StreamUtils;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Collectors;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Public audit projection and text-export behavior through the real query controller. */
class AdminAuditExportProjectionTest {
    private static final List<String> COLUMNS = Arrays.asList("id", "siteId", "actorName", "action", "objectId", "occurredAt", "result", "requestId", "operationId", "before", "after", "source");
    private final ObjectMapper json = new ObjectMapper();
    private AtomicReference<JSONObject> saved;
    private AdminLedgerStore ledger;
    private AdminAccessService access;
    private JSONObject actor;
    private MockMvc http;

    @BeforeEach void setup() throws Exception {
        JSONObject seed = JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(), StandardCharsets.UTF_8));
        migrate(seed);
        rows(seed, "audit").clear();
        saved = new AtomicReference<>(seed);
        actor = find(seed, "accounts", "demo-system");
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        access = new AdminAccessService(ledger);
        AdminQueryService queries = new AdminQueryService(ledger, mock(GuardianStore.class), mock(ObjectProvider.class));
        AdminLedgerController controller = new AdminLedgerController(ledger, queries, mock(AdminDeviceService.class),
                mock(AdminAssignmentService.class), mock(AdminMaintenanceService.class), mock(AdminMasterService.class), access);
        http = MockMvcBuilders.standaloneSetup(controller).build();
    }

    private JSONObject query(String kind, JSONObject input) throws Exception {
        String body = http.perform(post("/api/admin/v1/query").requestAttr("wearable.actor", actor)
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsBytes(object("kind", kind, "input", input))))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return JSONObject.parseObject(body).getJSONObject("data");
    }

    private JSONObject row(String id, String site, String timestamp) {
        return object("id", id, "siteId", site, "actorName", "核验人员", "action", "people.update",
                "objectId", "synthetic-person", "occurredAt", timestamp, "result", "SUCCESS", "source", "local",
                "requestId", "request-" + id, "operationId", "operation-" + id,
                "before", object("name", "原姓名"), "after", object("name", "新姓名"));
    }

    private JSONObject nestedSnapshot(String name) {
        return object("name", name, "version", 7, "enabled", false, "zero", 0,
                "note", "普通文本 areaId=keep，areaIds 不应按字符串删改", "token", "synthetic-test-secret",
                "passwordHash", "synthetic-test-hash", "areaId", "retired-area", "areaName", "退役区域",
                "personAreaId", "retired-person-area", "areas", JSONArray.of("retired-area"),
                "scopeAreas", JSONArray.of("retired-area"), "writableAreas", JSONArray.of("retired-area"), "mapAreas", JSONArray.of("retired-area"),
                "grants", JSONArray.of(object("siteIds", JSONArray.of("site-1"), "operations", JSONArray.of("people:read"), "areaIds", JSONArray.of("retired-area"))),
                "roleScopes", object("duty", object("siteIds", JSONArray.of("site-1"), "areaIds", "*")));
    }

    @Test void nestedLedgerSnapshotsMatchControllerListAndDetailWithoutMutatingStoredAudit() throws Exception {
        JSONObject record = row("projection-audit", "site-1", "2026-11-05T01:02:03Z");
        record.put("before", nestedSnapshot("原始,姓名\n下一行"));
        record.put("after", nestedSnapshot("更新\"姓名\""));
        rows(saved.get(), "audit").add(record);
        String original = saved.get().toJSONString();
        JSONObject expected = query("audit", object("siteId", "site-1", "pageNum", 1, "pageSize", 10)).getJSONArray("rows").getJSONObject(0);
        JSONObject detail = query("auditDetail", object("siteId", "site-1", "id", record.getString("id")));
        Map<String, String> exported = csvRows(query("auditExport", object("siteId", "site-1")).getString("csv")).get(0);
        for (String column : Arrays.asList("before", "after")) {
            JSONObject actual = JSONObject.parseObject(exported.get(column));
            assertEquals(expected.getJSONObject(column), actual);
            assertEquals(detail.getJSONObject(column), actual);
            assertFalse(actual.containsKey("areaId"));
            assertFalse(actual.getJSONArray("grants").getJSONObject(0).containsKey("areaIds"));
            assertFalse(actual.getJSONObject("roleScopes").getJSONObject("duty").containsKey("areaIds"));
            assertFalse(actual.containsKey("passwordHash"));
            assertEquals("[已脱敏]", actual.getString("token"));
            assertEquals("普通文本 areaId=keep，areaIds 不应按字符串删改", actual.getString("note"));
            assertFalse(actual.getBooleanValue("enabled"));
            assertEquals(0, actual.getIntValue("zero"));
        }
        assertEquals(original, saved.get().toJSONString());
        verify(ledger, never()).write(any());
    }

    @Test void guardianWorkAuditUsesTheSamePublicProjectionAndPreservesItsSource() throws Exception {
        JSONObject record = row("guardian-work-audit", "site-1", "2026-11-05T02:03:04Z");
        record.put("action", "works.update");
        record.put("before", nestedSnapshot("作业前"));
        record.put("after", nestedSnapshot("作业后"));
        JSONObject portal = object("audit", JSONArray.of(record));
        String original = portal.toJSONString();
        GuardianStore guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(call -> copy(portal));
        ReflectionTestUtils.setField(access, "guardian", guardian);
        JSONObject listed = query("audit", object("siteId", "site-1", "pageNum", 1, "pageSize", 10)).getJSONArray("rows").getJSONObject(0);
        Map<String, String> exported = csvRows(query("auditExport", object("siteId", "site-1")).getString("csv")).get(0);
        assertEquals(listed.getJSONObject("before"), JSONObject.parseObject(exported.get("before")));
        assertEquals(listed.getJSONObject("after"), JSONObject.parseObject(exported.get("after")));
        assertEquals(original, portal.toJSONString());
        verify(ledger, never()).write(any());
    }

    @Test void exportKeepsFiltersOrderingScopeAndAllRowsBeyondTheCurrentPage() throws Exception {
        for (String id : Arrays.asList("qa-a", "qa-c", "qa-b")) rows(saved.get(), "audit").add(row(id, "site-1", "2026-11-05T03:00:00Z"));
        rows(saved.get(), "audit").add(row("qa-other-site", "site-2", "2026-11-05T03:00:00Z"));
        rows(saved.get(), "audit").add(row("qa-other-day", "site-1", "2026-11-04T03:00:00Z"));
        JSONObject failed = row("qa-failed", "site-1", "2026-11-05T03:00:00Z"); failed.put("result", "FAILED"); rows(saved.get(), "audit").add(failed);
        String original = saved.get().toJSONString();
        JSONObject filter = object("siteId", "site-1", "pageNum", 2, "pageSize", 1, "dateFrom", "2026-11-05", "dateTo", "2026-11-05",
                "actorName", "核验人员", "action", "people.update", "objectId", "synthetic-person", "result", "SUCCESS", "keyword", "qa-");
        JSONObject page = query("audit", filter);
        assertEquals(3, page.getIntValue("total"));
        assertEquals("qa-b", page.getJSONArray("rows").getJSONObject(0).getString("id"));
        JSONObject exported = query("auditExport", filter);
        assertEquals(3, exported.getIntValue("total"));
        assertEquals(Arrays.asList("qa-c", "qa-b", "qa-a"), csvRows(exported.getString("csv")).stream().map(r -> r.get("id")).collect(Collectors.toList()));
        assertEquals(original, saved.get().toJSONString());
        verify(ledger, never()).write(any());
    }

    @Test void exportStillRejectsActorWithoutAuditReadAndLeavesLedgerUntouched() throws Exception {
        rows(saved.get(), "roles").add(object("id", "audit-test-no-audit", "enabled", true,
                "grants", JSONArray.of(object("siteIds", JSONArray.of("site-1"), "operations", JSONArray.of("people:read")))));
        actor = object("id", "audit-test-actor", "enabled", true, "siteId", "site-1", "roleIds", JSONArray.of("audit-test-no-audit"));
        rows(saved.get(), "accounts").add(actor);
        String original = saved.get().toJSONString();
        http.perform(post("/api/admin/v1/query").requestAttr("wearable.actor", actor).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsBytes(object("kind", "auditExport", "input", object("siteId", "site-1")))))
                .andExpect(status().isForbidden());
        assertEquals(original, saved.get().toJSONString());
        verify(ledger, never()).write(any());
    }

    @Test void reportMetadataUsesReportLabelAndKeepsTheActualRowSourceAndColumns() throws Exception {
        JSONObject record = row("report-label", "site-1", "2026-11-05T03:00:00Z");
        record.put("source", "现场维护");
        rows(saved.get(), "audit").add(record);
        String original = saved.get().toJSONString();
        String csv = query("auditExport", object("siteId", "site-1")).getString("csv");
        assertTrue(csv.startsWith("\ufeff\"报表\",\"后台操作日志\"\r\n"));
        assertTrue(csv.contains("\"记录数\",\"1\"\r\n"));
        List<Map<String, String>> exported = csvRows(csv);
        assertEquals(1, exported.size());
        assertEquals("现场维护", exported.get(0).get("source"));
        assertEquals("report-label", exported.get(0).get("id"));
        assertEquals(original, saved.get().toJSONString());
        verify(ledger, never()).write(any());
    }

    private String exportActorName(String name) throws Exception {
        rows(saved.get(), "audit").clear();
        JSONObject record = row("formula-text", "site-1", "2026-11-05T03:00:00Z");
        record.put("actorName", name);
        rows(saved.get(), "audit").add(record);
        String original = saved.get().toJSONString();
        String exported = csvRows(query("auditExport", object("siteId", "site-1")).getString("csv")).get(0).get("actorName");
        assertEquals(original, saved.get().toJSONString());
        verify(ledger, never()).write(any());
        return exported;
    }

    @Test void existingDirectAndControlFormulaPrefixesRemainPlainExportedText() throws Exception {
        for (String text : Arrays.asList("=1+1", "+1", "-1", "@SUM(A1)", " \t\r=1+1", "\u0000\u007f+1")) {
            assertEquals("'" + text, exportActorName(text));
        }
    }

    @Test void bomAndUnicodeSpaceFormulaPrefixesAreProtectedBeforeAnySpreadsheetImport() throws Exception {
        for (String text : Arrays.asList("\ufeff=1+1", "\u00a0@SUM(A1)", "\u3000-1")) {
            assertEquals("'" + text, exportActorName(text));
        }
    }

    @Test void formulaTextContainingNewlinesIsStillProtectedWithoutExecutingIt() throws Exception {
        for (String text : Arrays.asList("=1+\n1", "+1\r\n+1", "\t@SUM(\nA1)")) {
            assertEquals("'" + text, exportActorName(text));
        }
    }

    @Test void ordinaryChineseQuotesCommasAndLineBreaksRemainUnchanged() throws Exception {
        for (String text : Arrays.asList("普通,姓名\"引号\"\r\n第二行", "\t普通文字", "人员 =1+1", "areaId=literal", "")) {
            assertEquals(text, exportActorName(text));
        }
    }

    /** Independent CSV decoding: preserves escaped quotes and embedded CR/LF. */
    private List<Map<String, String>> csvRows(String text) {
        assertTrue(text.startsWith("\ufeff"));
        List<List<String>> records = new ArrayList<>();
        List<String> row = new ArrayList<>();
        StringBuilder field = new StringBuilder();
        boolean quoted = false;
        for (int i = 1; i < text.length(); i++) {
            char c = text.charAt(i);
            if (quoted) {
                if (c == '"' && i + 1 < text.length() && text.charAt(i + 1) == '"') { field.append('"'); i++; }
                else if (c == '"') quoted = false;
                else field.append(c);
            } else if (c == '"') quoted = true;
            else if (c == ',') { row.add(field.toString()); field.setLength(0); }
            else if (c == '\r' || c == '\n') {
                row.add(field.toString()); field.setLength(0); records.add(row); row = new ArrayList<>();
                if (c == '\r' && i + 1 < text.length() && text.charAt(i + 1) == '\n') i++;
            } else field.append(c);
        }
        assertFalse(quoted);
        if (field.length() > 0 || !row.isEmpty()) { row.add(field.toString()); records.add(row); }
        int header = records.indexOf(COLUMNS);
        assertTrue(header >= 0, "CSV must retain its expected public columns");
        List<Map<String, String>> result = new ArrayList<>();
        for (List<String> record : records.subList(header + 1, records.size())) {
            assertEquals(COLUMNS.size(), record.size());
            Map<String, String> values = new LinkedHashMap<>();
            for (int i = 0; i < COLUMNS.size(); i++) values.put(COLUMNS.get(i), record.get(i));
            result.add(values);
        }
        return result;
    }
}
