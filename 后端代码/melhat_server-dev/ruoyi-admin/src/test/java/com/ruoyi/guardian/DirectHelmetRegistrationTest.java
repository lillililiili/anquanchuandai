package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.PlatformDeviceSyncService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;

import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.List;

import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DirectHelmetRegistrationTest {
    private JSONObject state;
    private JSONObject snapshot;
    private AdminLedgerStore ledger;
    private GuardianHatArchive archive;
    private GuardianStore guardian;
    private AdminQueryService queries;
    private AdminDeviceService devices;

    @BeforeEach void setup() throws Exception {
        state = seed("admin-seed.json");
        snapshot = seed("guardian-seed.json");
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> JSON.parseObject(state.toJSONString()));
        doAnswer(i -> {
            JSONObject next = i.getArgument(0);
            state.clear();
            state.putAll(next);
            return null;
        }).when(ledger).write(any());
        archive = mock(GuardianHatArchive.class);
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenAnswer(i -> JSON.parseObject(snapshot.toJSONString()));
        queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
        devices = new AdminDeviceService(ledger, archive);
        ReflectionTestUtils.setField(devices, "queries", queries);
    }

    private JSONObject seed(String name) throws Exception {
        return JSON.parseObject(StreamUtils.copyToString(new ClassPathResource(name).getInputStream(), StandardCharsets.UTF_8));
    }

    private JSONObject request() {
        return object("siteId", "site-1", "operationId", "register-direct-1", "data",
                object("type", "HELMET", "source", "DIRECT_HELMET", "deviceNumber", "TEST-LOGIN-100",
                        "code", "ASSET-100", "sn", "SERIAL-900", "manufacturer", "测试厂商", "name", "测试一体帽"));
    }

    private JSONObject create() {
        return devices.execute("demo-system", "devices.create", request()).getJSONObject("data");
    }

    @Test void registrationKeepsLoginIdAssetCodeAndSerialSeparateAndReplayDoesNotReregister() {
        JSONObject created = create();
        assertEquals("TEST-LOGIN-100", created.getString("deviceNumber"));
        assertEquals("TEST-LOGIN-100", created.getString("portalDeviceId"));
        assertEquals("ASSET-100", created.getString("code"));
        assertEquals("SERIAL-900", created.getString("sn"));
        assertEquals("SIP", created.getString("communicationProtocol"));
        assertTrue(created.getJSONArray("capabilities").isEmpty());
        assertNull(created.get("online"));
        assertEquals("UNKNOWN", created.getString("freshness"));
        assertEquals(created.toJSONString(), devices.execute("demo-system", "devices.create", request()).getJSONObject("data").toJSONString());
        verify(archive, times(1)).ensureDirectUnassigned("TEST-LOGIN-100");
        verify(archive, never()).ensureUnassigned(anyString());
        verify(ledger, times(1)).write(any());
    }

    @Test void loginIdCanAlsoBeUsedAsDefaultAssetCode() {
        JSONObject input = request();
        input.getJSONObject("data").remove("code");
        JSONObject created = devices.execute("demo-system", "devices.create", input).getJSONObject("data");
        assertEquals("TEST-LOGIN-100", created.getString("code"));
        assertEquals("SERIAL-900", created.getString("sn"));
    }

    @Test void invalidSourceTypeIdAndClientClaimedCapabilitiesNeverReachArchive() {
        for (JSONObject changed : new JSONObject[]{
                object("source", "PLATFORM"), object("type", "BELT"), object("deviceNumber", "../bad"),
                object("capabilities", JSONArray.of("VIDEO"))}) {
            JSONObject input = request();
            input.getJSONObject("data").putAll(changed);
            assertThrows(AdminQueryService.QueryFailed.class, () -> devices.execute("demo-system", "devices.create", input));
        }
        verifyNoInteractions(archive);
        verify(ledger, never()).write(any());
    }

    @Test void identityCollisionAndLaterIdentityChangesAreRejected() {
        JSONObject created = create();
        JSONObject duplicate = request();
        duplicate.put("operationId", "duplicate");
        duplicate.getJSONObject("data").put("code", "DIFFERENT-ASSET");
        duplicate.getJSONObject("data").put("sn", "DIFFERENT-SERIAL");
        assertEquals(409, assertThrows(AdminQueryService.QueryFailed.class,
                () -> devices.execute("demo-system", "devices.create", duplicate)).code);
        JSONObject update = object("siteId", "site-1", "id", created.getString("id"), "expectedVersion", 1,
                "operationId", "replace-sn", "data", object("sn", "REPLACEMENT"));
        assertEquals(400, assertThrows(AdminQueryService.QueryFailed.class,
                () -> devices.execute("demo-system", "devices.update", update)).code);
        verify(archive, times(1)).ensureDirectUnassigned(anyString());
        verify(ledger, times(1)).write(any());
    }

    @Test void ordinaryIssueProjectsTheLoginIdIntoGuardianBinding() {
        JSONObject created = create();
        JSONObject person = state.getJSONArray("people").getJSONObject(0);
        state.put("assignments", new JSONArray());
        JSONArray items = new JSONArray();
        items.add(object("deviceId", created.getString("id"), "deviceVersion", 1));
        JSONObject issue = object("siteId", "site-1", "personId", person.getString("id"),
                "personVersion", person.getIntValue("version"), "items", items,
                "operationId", "issue-direct", "acknowledged", true);
        new AdminAssignmentService(ledger, guardian, queries).execute("demo-system", "assignments.issue", issue);
        assertEquals("TEST-LOGIN-100", WearableModel.find(state, "devices", created.getString("id")).getString("portalDeviceId"));
        assertTrue(PlatformProjection.apply(snapshot, state));
        JSONObject projected = AdminPlatformService.find(snapshot.getJSONArray("devices"), "id", "TEST-LOGIN-100");
        assertEquals("DIRECT_HELMET", projected.getString("source"));
        assertEquals("H", projected.getString("type"));
        assertEquals("SERIAL-900", projected.getString("sn"));
        assertNull(projected.get("online"));
        assertTrue(projected.getJSONArray("capabilities").isEmpty());
        JSONObject binding = AdminPlatformService.find(snapshot.getJSONArray("bindings"), "deviceId", "TEST-LOGIN-100");
        assertNotNull(binding);
        assertNull(binding.get("end"));
        assertEquals(WearableModel.find(state, "people", person.getString("id")).getString("portalId"), binding.getString("personId"));
        JSONObject assignment = state.getJSONArray("assignments").getJSONObject(0);
        JSONObject giveBack = object("siteId", "site-1", "personId", person.getString("id"),
                "personVersion", WearableModel.find(state, "people", person.getString("id")).getIntValue("version"),
                "items", JSONArray.of(object("deviceId", created.getString("id"), "deviceVersion", 2,
                        "assignmentId", assignment.getString("id"), "assignmentVersion", 1, "condition", "GOOD")),
                "operationId", "return-direct", "acknowledged", true);
        new AdminAssignmentService(ledger, guardian, queries).execute("demo-system", "assignments.return", giveBack);
        PlatformProjection.apply(snapshot, state);
        assertEquals("TEST-LOGIN-100", WearableModel.find(state, "devices", created.getString("id")).getString("portalDeviceId"));
        assertNotNull(binding.get("end"));
    }

    @Test void adminQueryPreservesUnknownAndStaleDirectTelemetryAndSearchesLoginId() {
        create();
        PlatformProjection.apply(snapshot, state);
        JSONObject remote = AdminPlatformService.find(snapshot.getJSONArray("devices"), "id", "TEST-LOGIN-100");
        remote.put("online", null);
        remote.put("freshness", "UNKNOWN");
        JSONObject input = object("siteId", "site-1", "source", "DIRECT_HELMET", "keyword", "TEST-LOGIN-100");
        List<JSONObject> result = (List<JSONObject>) queries.query("demo-system", "devices", input).get("rows");
        assertEquals(1, result.size());
        assertEquals("UNKNOWN", result.get(0).getString("communication"));
        assertNull(result.get(0).get("online"));
        remote.put("online", false);
        remote.put("freshness", "STALE");
        remote.put("sourceTime", "2026-10-20T10:00:00Z");
        remote.put("battery", 52);
        remote.put("isWeared", 2);
        remote.put("latitude", 30.1);
        remote.put("locationReportedAt", "2026-10-20T09:59:00Z");
        result = (List<JSONObject>) queries.query("demo-system", "devices", input).get("rows");
        assertEquals("OFFLINE", result.get(0).getString("communication"));
        assertEquals("STALE", result.get(0).getString("freshness"));
        assertEquals("2026-10-20T10:00:00Z", result.get(0).getString("sourceTime"));
        assertEquals(2, result.get(0).getIntValue("isWeared"));
        assertEquals(52, result.get(0).getIntValue("battery"));
        assertEquals("SERIAL-900", result.get(0).getString("sn"));
    }

    @Test void platformSyncCannotTakeOverByLoginIdOrSerialOrAssetCode() throws Exception {
        create();
        PlatformDeviceSyncService platform = mock(PlatformDeviceSyncService.class);
        AdminPlatformService sync = new AdminPlatformService(ledger, queries, platform);
        clearInvocations(ledger);
        for (String number : new String[]{"TEST-LOGIN-100", "SERIAL-900", "ASSET-100"}) {
            HeadbandVO hat = new HeadbandVO();
            hat.setHelmetSn(number);
            hat.setOnline("1");
            when(platform.preview()).thenReturn(Collections.singletonList(hat));
            assertEquals(409, assertThrows(AdminQueryService.QueryFailed.class,
                    () -> sync.sync("demo-system", "site-1")).code);
        }
        verify(ledger, never()).write(any());
        verify(platform, never()).syncRecords(anyList(), any());
    }

    @Test void archiveRegistrationUsesProtocolIdAndNeverPromotesAnExistingGuardianHat() {
        SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
        when(mapper.findIncludingDeleted("TEST-LOGIN-100")).thenReturn(Collections.emptyList());
        when(mapper.insert(any())).thenReturn(1);
        GuardianHatArchive hats = new GuardianHatArchive(mapper);
        hats.ensureDirectUnassigned("TEST-LOGIN-100");
        ArgumentCaptor<SafetyHatInfo> inserted = ArgumentCaptor.forClass(SafetyHatInfo.class);
        verify(mapper).insert(inserted.capture());
        assertEquals("TEST-LOGIN-100", inserted.getValue().getHatNumber());
        assertEquals("direct-helmet", inserted.getValue().getCreateBy());
        assertEquals("0", inserted.getValue().getStatus());
        SafetyHatInfo existing = new SafetyHatInfo();
        existing.setCreateBy("guardian");
        existing.setDelFlag("0");
        when(mapper.findIncludingDeleted("OTHER-ID")).thenReturn(Collections.singletonList(existing));
        assertEquals(409, assertThrows(AdminQueryService.QueryFailed.class, () -> hats.ensureDirectUnassigned("OTHER-ID")).code);
        existing.setCreateBy("direct-helmet");
        existing.setDelFlag("1");
        assertThrows(AdminQueryService.QueryFailed.class, () -> hats.ensureDirectUnassigned("OTHER-ID"));
        existing.setCreateBy("direct-helmet-disabled");
        existing.setDelFlag("0");
        assertThrows(AdminQueryService.QueryFailed.class, () -> hats.ensureDirectUnassigned("OTHER-ID"));
        verify(mapper, never()).update(any(), any());
    }

    @Test void snapshotCannotCreateDirectProtocolRegistration() {
        SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
        GuardianHatArchive hats = new GuardianHatArchive(mapper);
        when(mapper.findIncludingDeleted(anyString())).thenReturn(Collections.emptyList());
        JSONObject direct = object("devices", JSONArray.of(object("id", "TEST-LOGIN-100", "type", "H", "source", "DIRECT_HELMET")));
        assertThrows(IllegalStateException.class, () -> hats.sync(direct));
        verify(mapper, never()).insert(any());
    }

    @Test void directArchiveBindingAndTelemetrySyncOnlyTouchesMatchingOwner() {
        SafetyHatInfoMapper mapper = mock(SafetyHatInfoMapper.class);
        GuardianHatArchive hats = new GuardianHatArchive(mapper);
        SafetyHatInfo registered = new SafetyHatInfo();
        registered.setId(100L);
        registered.setHatNumber("TEST-LOGIN-100");
        registered.setCreateBy("direct-helmet");
        registered.setDelFlag("0");
        when(mapper.findIncludingDeleted("TEST-LOGIN-100")).thenReturn(Collections.singletonList(registered));
        when(mapper.selectList(any())).thenReturn(Collections.singletonList(registered));
        when(mapper.update(any(), any())).thenReturn(1);
        JSONObject direct = object("devices", JSONArray.of(object("id", "TEST-LOGIN-100", "type", "H",
                "source", "DIRECT_HELMET", "active", true, "online", true, "battery", 80)),
                "people", JSONArray.of(object("id", "person-a", "name", "测试人员")),
                "bindings", JSONArray.of(object("deviceId", "TEST-LOGIN-100", "personId", "person-a", "end", null)));
        hats.sync(direct);
        ArgumentCaptor<Wrapper<SafetyHatInfo>> update = ArgumentCaptor.forClass(Wrapper.class);
        verify(mapper).update(isNull(), update.capture());
        String sql = update.getValue().getSqlSet();
        assertTrue(sql.contains("bind_user_name"));
        assertTrue(sql.contains("electricity_usage"));
        assertTrue(((UpdateWrapper<SafetyHatInfo>) update.getValue()).getParamNameValuePairs().containsValue("测试人员"));
        verify(mapper, never()).insert(any());
        clearInvocations(mapper);
        direct.getJSONArray("devices").getJSONObject(0).put("active", false);
        hats.sync(direct);
        verify(mapper).update(isNull(), update.capture());
        assertTrue(((UpdateWrapper<SafetyHatInfo>) update.getValue()).getParamNameValuePairs().containsValue("direct-helmet-disabled"));
        clearInvocations(mapper);
        registered.setCreateBy("direct-helmet-disabled");
        direct.getJSONArray("devices").getJSONObject(0).put("active", true);
        hats.sync(direct);
        verify(mapper).update(isNull(), update.capture());
        assertTrue(((UpdateWrapper<SafetyHatInfo>) update.getValue()).getParamNameValuePairs().containsValue("direct-helmet"));
        clearInvocations(mapper);
        direct.getJSONArray("devices").getJSONObject(0).remove("source");
        hats.sync(direct);
        verify(mapper, never()).update(any(), any());
    }
}
