package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PeopleOrganizationQueryTest {
    JSONObject state, actor, grant;
    AdminQueryService queries;

    @BeforeEach void setup() {
        actor = object("id", "people-reader", "enabled", true, "roleIds", JSONArray.of("people-role"));
        grant = object("operations", JSONArray.of("people:read", "organization:read"), "siteIds", JSONArray.of("site-1"));
        state = object("accounts", JSONArray.of(actor),
                "roles", JSONArray.of(object("id", "people-role", "enabled", true, "grants", JSONArray.of(grant))),
                "sites", JSONArray.of(object("id", "site-1", "enabled", true), object("id", "site-2", "enabled", true)),
                "organizations", JSONArray.of(organization("root", "site-1", null, true), organization("child", "site-1", "root", true),
                        organization("grandchild", "site-1", "child", false), organization("sibling", "site-1", null, true),
                        organization("foreign", "site-2", "root", true), organization("bridged", "site-1", "foreign", true)),
                "people", JSONArray.of(person("root-person", "site-1", "root", true), person("child-person", "site-1", "child", true),
                        person("grandchild-person", "site-1", "grandchild", false), person("sibling-person", "site-1", "sibling", true),
                        person("unassigned-person", "site-1", null, true), person("foreign-person", "site-2", "foreign", true),
                        person("corrupt-foreign-person", "site-1", "foreign", true), person("bridged-person", "site-1", "bridged", true)));
        AdminLedgerStore ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call -> copy(state));
        queries = new AdminQueryService(ledger, mock(GuardianStore.class), mock(ObjectProvider.class));
    }

    JSONObject organization(String id, String site, String parent, boolean enabled) {
        return object("id", id, "siteId", site, "parentId", parent, "name", id, "enabled", enabled);
    }

    JSONObject person(String id, String site, String organization, boolean enabled) {
        return object("id", id, "siteId", site, "organizationId", organization, "code", id, "name", id, "enabled", enabled, "version", 1);
    }

    Map<String, Object> query(JSONObject input) {
        JSONObject params = object("siteId", "site-1", "entity", "people", "pageNum", 1, "pageSize", 100);
        params.putAll(input);
        return queries.query(actor.getString("id"), "master", params);
    }

    List<String> ids(Map<String, Object> result) {
        return ((List<JSONObject>) result.get("rows")).stream().map(row -> row.getString("id")).collect(Collectors.toList());
    }

    @Test void optionalDescendantsIncludeMultipleLevelsAndRetainDefaultExactMatching() {
        assertEquals(Arrays.asList("root-person"), ids(query(object("organizationId", "root"))));
        assertEquals(Arrays.asList("root-person"), ids(query(object("organizationId", "root", "includeDescendants", false))));
        assertEquals(Arrays.asList("root-person", "child-person", "grandchild-person"), ids(query(object("organizationId", "root", "includeDescendants", true))));
        assertEquals(Arrays.asList("child-person", "grandchild-person"), ids(query(object("organizationId", "child", "includeDescendants", true))));
        assertEquals(Arrays.asList("grandchild-person"), ids(query(object("organizationId", "grandchild", "includeDescendants", true))));
        assertEquals(7, query(object("includeDescendants", true)).get("total"));
    }

    @Test void descendantFilteringCombinesWithPersonStatusKeywordAndPagination() {
        JSONObject input = object("organizationId", "root", "includeDescendants", true, "status", "enabled", "pageSize", 1, "pageNum", 2);
        Map<String, Object> secondPage = query(input);
        assertEquals(2, secondPage.get("total"));assertEquals(Arrays.asList("child-person"), ids(secondPage));
        input.put("status", "disabled");input.put("pageNum", 1);input.put("keyword", "grandchild");
        assertEquals(Arrays.asList("grandchild-person"), ids(query(input)));
    }

    @Test void foreignInvalidOrInvisibleOrganizationsCannotBroadenTheAuthorizedPersonnelSet() {
        assertTrue(ids(query(object("organizationId", "foreign", "includeDescendants", true))).isEmpty());
        assertTrue(ids(query(object("organizationId", "missing", "includeDescendants", true))).isEmpty());
        assertFalse(ids(query(object("organizationId", "root", "includeDescendants", true))).contains("bridged-person"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> query(object("siteId", "site-2", "organizationId", "foreign", "includeDescendants", true))).code);
        grant.put("operations", JSONArray.of("people:read"));
        assertTrue(ids(query(object("organizationId", "root", "includeDescendants", true))).isEmpty());
        assertEquals(Arrays.asList("root-person"), ids(query(object("organizationId", "root"))), "legacy exact filtering retains its existing permission behavior");
        grant.put("operations", JSONArray.of("organization:read"));
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class, () -> query(object("organizationId", "root", "includeDescendants", true))).code);
    }

    @Test void cyclesTerminateWithoutDuplicatesAndQueriesDoNotMutateTheLedger() {
        find(state, "organizations", "root").put("parentId", "grandchild");
        String baseline = state.toJSONString();
        assertTimeoutPreemptively(Duration.ofSeconds(2), () -> assertEquals(Arrays.asList("root-person", "child-person", "grandchild-person"),
                ids(query(object("organizationId", "root", "includeDescendants", true)))));
        assertEquals(baseline, state.toJSONString());
    }

    @Test void descendantFlagRequiresABoolean() {
        for (Object value : Arrays.asList("true", 1, new JSONObject())) {
            assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class, () -> query(object("organizationId", "root", "includeDescendants", value))).code);
        }
    }
}
