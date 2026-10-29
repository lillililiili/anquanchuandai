package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.util.List;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectBeltRegistrationTest {
    JSONObject state, snapshot;
    AdminLedgerStore ledger;
    GuardianHatArchive hats;
    GuardianStore guardian;
    AdminQueryService queries;
    AdminDeviceService devices;

    @BeforeEach void setup() throws Exception {
        state = seed("admin-seed.json");
        snapshot = seed("guardian-seed.json");
        migrate(state);
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> copy(state));
        doAnswer(i -> { JSONObject next = i.getArgument(0); state.clear(); state.putAll(next); return null; })
                .when(ledger).write(any());
        hats = mock(GuardianHatArchive.class);
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(i -> copy(snapshot));
        queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
        devices = new AdminDeviceService(ledger, hats);
        ReflectionTestUtils.setField(devices, "queries", queries);
    }

    static JSONObject seed(String name) throws Exception {
        return JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource(name).getInputStream(), StandardCharsets.UTF_8));
    }

    JSONObject request() {
        return object("siteId", "site-1", "operationId", "register-belt", "data",
                object("type", "BELT", "source", "DIRECT_BELT", "deviceNumber", "BELT-LOGIN-100",
                        "code", "BELT-ASSET-100", "sn", "BELT-SERIAL-900", "manufacturer", "测试厂商", "name", "测试安全带"));
    }

    JSONObject create() { return devices.execute("demo-system", "devices.create", request()).getJSONObject("data"); }

    @Test void registrationSeparatesIdentityAndNeverCreatesHelmetArchive() {
        JSONObject created = create();
        assertEquals("BELT-LOGIN-100", created.getString("deviceNumber"));
        assertEquals("BELT-LOGIN-100", created.getString("portalDeviceId"));
        assertEquals("BELT-ASSET-100", created.getString("code"));
        assertEquals("BELT-SERIAL-900", created.getString("sn"));
        assertEquals("WEBSOCKET", created.getString("communicationProtocol"));
        assertNull(created.get("online"));
        assertTrue(created.getJSONArray("capabilities").isEmpty());
        assertEquals(created.toJSONString(), devices.execute("demo-system", "devices.create", request()).getJSONObject("data").toJSONString());
        verifyNoInteractions(hats);
        verify(ledger, times(1)).write(any());
    }

    @Test void wrongDeviceTypeUnregisteredSourceAndClientTelemetryAreRejected() {
        for (JSONObject change : new JSONObject[]{object("type", "HELMET"), object("type", "WATCH"),
                object("source", "DIRECT_HELMET"), object("source", "PLATFORM"),
                object("deviceNumber", "../wrong"), object("worn", true), object("capabilities", JSONArray.of("hook"))}) {
            JSONObject request = request(); request.getJSONObject("data").putAll(change);
            assertThrows(AdminQueryService.QueryFailed.class, () -> devices.execute("demo-system", "devices.create", request));
        }
        verifyNoInteractions(hats);
        verify(ledger, never()).write(any());
    }

    @Test void identityCannotCollideAcrossTypesOrChangeAfterRegistration() {
        JSONObject created = create();
        for (String source : new String[]{"DIRECT_BELT", "DIRECT_HELMET"}) {
            JSONObject next = request();
            next.put("operationId", "duplicate-" + source);
            JSONObject data = next.getJSONObject("data");
            data.put("source", source); data.put("type", "DIRECT_BELT".equals(source) ? "BELT" : "HELMET");
            data.put("code", "DIFFERENT-CODE"); data.put("sn", "DIFFERENT-SN");
            assertEquals(409, assertThrows(AdminQueryService.QueryFailed.class,
                    () -> devices.execute("demo-system", "devices.create", next)).code);
        }
        JSONObject update = object("siteId", "site-1", "id", created.getString("id"), "expectedVersion", 1,
                "operationId", "replace-identity", "data", object("sn", "CHANGED"));
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class,
                () -> devices.execute("demo-system", "devices.update", update)).code);
        verify(ledger, times(1)).write(any());
    }

    @Test void issueAndReturnPreserveLoginIdentityAndCurrentWearer() {
        JSONObject created = create();
        JSONObject person = rows(state, "people").getJSONObject(0);
        state.put("assignments", new JSONArray());
        JSONObject issue = object("siteId", "site-1", "personId", person.getString("id"),
                "personVersion", person.getIntValue("version"), "items", JSONArray.of(
                        object("deviceId", created.getString("id"), "deviceVersion", 1)),
                "operationId", "issue-belt", "acknowledged", true);
        AdminAssignmentService assignmentService = new AdminAssignmentService(ledger, guardian, queries);
        assignmentService.execute("demo-system", "assignments.issue", issue);
        PlatformProjection.apply(snapshot, state);
        JSONObject belt = find(snapshot, "devices", "BELT-LOGIN-100");
        assertEquals("B", belt.getString("type"));
        assertEquals("DIRECT_BELT", belt.getString("source"));
        DirectBeltTelemetryService telemetry = new DirectBeltTelemetryService(ledger, guardian);
        assertEquals(person.getString("portalId"), telemetry.registered("BELT-LOGIN-100").getString("userId"));
        JSONObject assignment = rows(state, "assignments").getJSONObject(0);
        JSONObject giveBack = object("siteId", "site-1", "personId", person.getString("id"),
                "personVersion", find(state, "people", person.getString("id")).getIntValue("version"),
                "items", JSONArray.of(object("deviceId", created.getString("id"), "deviceVersion", 2,
                        "assignmentId", assignment.getString("id"), "assignmentVersion", 1, "condition", "GOOD")),
                "operationId", "return-belt", "acknowledged", true);
        assignmentService.execute("demo-system", "assignments.return", giveBack);
        PlatformProjection.apply(snapshot, state);
        assertEquals("", telemetry.registered("BELT-LOGIN-100").getString("userId"));
        assertEquals("BELT-LOGIN-100", find(state, "devices", created.getString("id")).getString("deviceNumber"));
        assertFalse(rows(snapshot, "bindings").stream().anyMatch(raw -> {
            JSONObject binding = (JSONObject) raw;
            return "BELT-LOGIN-100".equals(binding.getString("deviceId")) && binding.get("end") == null;
        }));
    }

    @Test void restartKeepsPreviouslyReportingBeltOfflineInsteadOfUnconnected() {
        create();PlatformProjection.apply(snapshot,state);
        JSONObject belt=find(snapshot,"devices","BELT-LOGIN-100");
        belt.put("online",false);belt.put("sourceTime",null);belt.put("lastSeenAt",null);belt.put("updated",null);
        belt.put("telemetryReportedAt","2026-10-20T12:00:00Z");
        JSONObject input=object("siteId","site-1","source","DIRECT_BELT","keyword","BELT-LOGIN-100");
        List<JSONObject> result=(List<JSONObject>)queries.query("demo-system","devices",input).get("rows");
        assertEquals("OFFLINE",result.get(0).getString("communication"));
        assertEquals("2026-10-20T12:00:00Z",result.get(0).getString("sourceTime"));
        belt.put("telemetryReportedAt",null);
        result=(List<JSONObject>)queries.query("demo-system","devices",input).get("rows");
        assertEquals("NOT_CONNECTED",result.get(0).getString("communication"));
    }
    @Test void adminQueryKeepsRawHookValuesUnknownAndStaleWithoutInventingSafety() {
        create(); PlatformProjection.apply(snapshot, state);
        JSONObject belt = find(snapshot, "devices", "BELT-LOGIN-100");
        DirectBeltProjection.applyStatus(belt, object("online", true, "freshness", "CURRENT", "battery", 57,
                "isWeared", 1, "hangerAStatus", "7", "hangerBStatus", "8", "lastSeenAt", "2026-10-20T12:00:00Z"));
        JSONObject input = object("siteId", "site-1", "source", "DIRECT_BELT", "keyword", "BELT-LOGIN-100");
        List<JSONObject> rows = (List<JSONObject>) queries.query("demo-system", "devices", input).get("rows");
        assertEquals(1, rows.size());
        JSONObject result = rows.get(0);
        assertEquals("ONLINE", result.getString("communication"));
        assertEquals(57, result.getIntValue("battery"));
        assertEquals("7", result.getString("hangerAStatus"));
        assertNull(result.get("worn")); assertNull(result.get("hookAEngaged"));
        DirectBeltProjection.applyStatus(belt, object("online", false, "freshness", "STALE"));
        rows = (List<JSONObject>) queries.query("demo-system", "devices", input).get("rows");
        assertEquals("OFFLINE", rows.get(0).getString("communication"));
        assertEquals("STALE", rows.get(0).getString("freshness"));
    }
}
