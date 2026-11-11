package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.util.StreamUtils;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Collectors;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminAuditFilterTest {
    private AdminLedgerStore ledger;
    private AdminAccessService access;
    private AtomicReference<JSONObject> saved;

    @BeforeEach void setup() throws Exception {
        JSONObject state = JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(), StandardCharsets.UTF_8));
        migrate(state);
        rows(state, "audit").clear();
        saved = new AtomicReference<>(state);
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(saved.get()));
        access = new AdminAccessService(ledger);
    }

    private void add(String id, String objectId, String result, String site) {
        rows(saved.get(), "audit").add(object("id", id, "siteId", site, "objectId", objectId,
                "actorName", "核验人员", "action", "roles.update", "result", result,
                "occurredAt", "2026-11-09T01:00:00Z", "source", "测试"));
    }

    private JSONObject query(String kind, JSONObject filters) {
        JSONObject input = object("siteId", "site-1"); input.putAll(filters);
        return new JSONObject(access.query("demo-system", kind, input));
    }

    private java.util.List<String> ids(JSONObject page) {
        return page.getJSONArray("rows").stream().map(row -> ((JSONObject) row).getString("id")).collect(Collectors.toList());
    }

    @Test void recordIdMatchesTheLogIdRatherThanObjectOrKeywordFields() {
        add("audit-30", "role-1", "SUCCESS", "site-1");
        add("audit-31", "audit-30", "SUCCESS", "site-1");
        add("audit-300", "role-1", "SUCCESS", "site-1");
        add("hidden", "role-1", "SUCCESS", "site-2");
        String before = saved.get().toJSONString();
        JSONObject filter = object("recordId", " audit-30 ", "actorName", "核验人员", "action", "roles.update", "result", "SUCCESS");
        assertEquals(Arrays.asList("audit-30"), ids(query("audit", filter)));
        JSONObject export = query("auditExport", filter);
        assertEquals(1, export.getIntValue("total"));
        assertTrue(export.getString("csv").contains("\"audit-30\""));
        assertFalse(export.getString("csv").contains("\"audit-31\""));
        assertEquals(0, query("audit", object("recordId", "hidden")).getIntValue("total"));
        assertEquals(0, query("audit", object("recordId", "role-1")).getIntValue("total"));
        assertEquals(before, saved.get().toJSONString());
        verify(ledger, never()).write(any());
    }

    @Test void failureGroupIncludesEveryFailureCodeBeforePaginationAndExport() {
        add("a", "role-1", "FAILED", "site-1");
        add("b", "role-2", "FAILURE", "site-1");
        add("c", "role-3", "SOURCE_FAILURE", "site-1");
        add("d", "role-4", "SUCCESS", "site-1");
        add("hidden", "role-5", "FAILED", "site-2");
        JSONObject filter = object("result", "FAILED", "pageNum", 2, "pageSize", 1);
        JSONObject page = query("audit", filter);
        assertEquals(3, page.getIntValue("total"));
        assertEquals(Arrays.asList("b"), ids(page));
        JSONObject export = query("auditExport", filter);
        assertEquals(3, export.getIntValue("total"));
        for (String code : Arrays.asList("FAILED", "FAILURE", "SOURCE_FAILURE")) assertTrue(export.getString("csv").contains("\"" + code + "\""));
        assertFalse(export.getString("csv").contains("\"hidden\""));
        assertEquals(3, query("audit", object("result", "FAILURE")).getIntValue("total"));
        assertEquals(1, query("audit", object("result", "SOURCE_FAILURE")).getIntValue("total"));
    }

    @Test void rejectionGroupPreservesRawResultsAndCombinesWithRecordFilter() {
        add("a", "role-1", "DENIED", "site-1");
        add("b", "role-2", "BUSINESS_REJECTED", "site-1");
        add("c", "role-3", "FAILED", "site-1");
        String before = saved.get().toJSONString();
        JSONObject filter = object("result", "DENIED");
        assertEquals(2, query("audit", filter).getIntValue("total"));
        assertEquals(2, query("auditExport", filter).getIntValue("total"));
        filter.put("recordId", "b");
        JSONObject row = query("audit", filter).getJSONArray("rows").getJSONObject(0);
        assertEquals("b", row.getString("id"));
        assertEquals("BUSINESS_REJECTED", row.getString("result"));
        assertEquals(1, query("auditExport", filter).getIntValue("total"));
        assertEquals(before, saved.get().toJSONString());
        verify(ledger, never()).write(any());
    }

    @Test void retainsLegacyObjectFilteringAndAllResultCodesWithoutAResultFilter() {
        for (String code : Arrays.asList("SUCCESS", "FAILED", "FAILURE", "SOURCE_FAILURE", "DENIED", "BUSINESS_REJECTED", "UNKNOWN")) add(code, "role-1", code, "site-1");
        assertEquals(7, query("audit", object("objectId", "role-1")).getIntValue("total"));
        assertEquals(7, query("auditExport", object("objectId", "role-1")).getIntValue("total"));
        assertEquals(1, query("audit", object("result", "SUCCESS")).getIntValue("total"));
        assertEquals(1, query("audit", object("result", "BUSINESS_REJECTED")).getIntValue("total"));
    }

    @Test void invalidRecordFilterAndUnauthorizedReadersAreRejected() {
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class,
                () -> query("audit", object("recordId", new String(new char[101]).replace('\0', 'x')))).code);
        rows(saved.get(), "accounts").add(object("id", "no-audit", "enabled", true, "roleIds", new JSONArray()));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> access.query("no-audit", "audit", object("siteId", "site-1", "recordId", "a", "result", "FAILED"))).code);
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> access.query("no-audit", "auditExport", object("siteId", "site-1", "recordId", "a", "result", "FAILED"))).code);
    }
}
