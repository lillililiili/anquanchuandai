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
import java.util.Map;

import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdminDeviceModelTest {
    private JSONObject state;
    private AdminLedgerStore ledger;
    private AdminDeviceService devices;
    private AdminQueryService queries;
    private AdminAssignmentService assignments;
    private int operation;

    @BeforeEach void setup() throws Exception {
        state = JSONObject.parseObject(StreamUtils.copyToString(
                new ClassPathResource("admin-seed.json").getInputStream(), StandardCharsets.UTF_8));
        migrate(state);
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> copy(state));
        doAnswer(i -> { JSONObject next = i.getArgument(0); state.clear(); state.putAll(next); return null; })
                .when(ledger).write(any());
        GuardianStore guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenReturn(object("devices", new JSONArray()));
        queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
        devices = new AdminDeviceService(ledger, mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(devices, "queries", queries);
        assignments = new AdminAssignmentService(ledger, guardian, queries);
    }

    private JSONObject create(JSONObject extra) {
        JSONObject data = object("type", "BELT", "code", "CUSTOM-MODEL-" + operation,
                "name", "自定义型号安全带", "manufacturer", "测试厂商", "sn", "CUSTOM-SN-" + operation);
        data.putAll(extra);
        return devices.execute("demo-system", "devices.create", object("siteId", "site-1",
                "operationId", "model-test-" + operation++, "data", data)).getJSONObject("data");
    }

    private JSONObject update(JSONObject row, JSONObject data) {
        return devices.execute("demo-system", "devices.update", object("siteId", "site-1", "id", row.getString("id"),
                "expectedVersion", row.getIntValue("version"), "operationId", "model-test-" + operation++, "data", data))
                .getJSONObject("data");
    }

    private Map<String, Object> read(JSONObject row) {
        return queries.query("demo-system", "device", object("siteId", "site-1", "id", row.getString("id")));
    }

    @Test void arbitraryModelTextPersistsAndAppearsInDetailAndListWithoutTemplateId() {
        JSONObject created = create(object("modelName", "  HNRW-AQD1 / 定制型  "));
        assertEquals("unknown-BELT", created.getString("modelId"));
        assertEquals("HNRW-AQD1 / 定制型", created.getString("modelName"));
        assertEquals("HNRW-AQD1 / 定制型", find(ledger.read(), "devices", created.getString("id")).getString("modelName"));
        assertEquals("HNRW-AQD1 / 定制型", read(created).get("modelName"));
        List<JSONObject> result = (List<JSONObject>) queries.query("demo-system", "devices",
                object("siteId", "site-1", "keyword", created.getString("code"))).get("rows");
        assertEquals(1, result.size());
        assertEquals("HNRW-AQD1 / 定制型", result.get(0).getString("modelName"));
        assertEquals("NOT_CONNECTED", result.get(0).getString("communication"));
    }

    @Test void textOnlyUpdatesAndExplicitClearingKeepTheInternalTemplateAndSavedValue() {
        JSONObject row = create(object("modelName", "原型号"));
        JSONObject assemblies = object("legacy-module", "INSTALLED");
        find(state, "devices", row.getString("id")).put("assemblies", assemblies);
        row = update(row, object("modelName", " 新型号 "));
        assertEquals("新型号", read(row).get("modelName"));
        assertEquals("unknown-BELT", row.getString("modelId"));
        assertEquals(assemblies, row.getJSONObject("assemblies"));
        row = update(row, object("remark", "补充备注"));
        assertEquals("新型号", read(row).get("modelName"));
        assertEquals(assemblies, row.getJSONObject("assemblies"));
        row = update(row, object("modelName", "  "));
        assertTrue(row.containsKey("modelName"));
        assertEquals("", read(row).get("modelName"));
        assertEquals(assemblies, row.getJSONObject("assemblies"));
    }

    @Test void legacyRowsRetainFallbackUntilAnExplicitModelIsSaved() {
        JSONObject row = create(new JSONObject());
        assertFalse(row.containsKey("modelName"));
        assertEquals("安全带", read(row).get("modelName"));
        row = update(row, object("remark", "历史设备备注"));
        assertFalse(row.containsKey("modelName"));
        assertEquals("安全带", read(row).get("modelName"));
        row = update(row, object("modelName", ""));
        assertEquals("", read(row).get("modelName"));
    }

    @Test void modelTextValidatesTypeAndLengthBeforeWriting() {
        for (Object invalid : new Object[]{null, 123, new JSONObject(), String.join("", java.util.Collections.nCopies(101, "型"))}) {
            JSONObject data = new JSONObject(); data.put("modelName", invalid);
            AdminQueryService.QueryFailed error = assertThrows(AdminQueryService.QueryFailed.class, () -> create(data));
            assertEquals("VALIDATION_ERROR", error.errorCode);
        }
        verify(ledger, never()).write(any());
        String longest = String.join("", java.util.Collections.nCopies(100, "型"));
        assertEquals(longest, create(object("modelName", longest)).getString("modelName"));
    }

    @Test void assignedDeviceCannotChangeModelButCanRetainLegacyDisplayValue() {
        JSONObject row = create(new JSONObject());
        find(state, "devices", row.getString("id")).put("lifecycle", "IN_USE");
        AdminQueryService.QueryFailed error = assertThrows(AdminQueryService.QueryFailed.class,
                () -> update(row, object("modelName", "另一型号")));
        assertEquals("KEY_FIELDS_LOCKED", error.errorCode);
        assertFalse(find(state, "devices", row.getString("id")).containsKey("modelName"));
        JSONObject unchanged = update(row, object("modelName", "安全带", "remark", "描述变更"));
        assertEquals("描述变更", unchanged.getString("remark"));
    }

    @Test void assignmentWarningsRespectTextModelAndExplicitClearing() {
        JSONObject row = create(object("modelName", "用户输入型号"));
        JSONArray warnings = ReflectionTestUtils.invokeMethod(assignments, "warnings", row);
        assertFalse(warnings.contains("资料或型号待补充"));
        row.put("modelName", ""); row.put("modelId", "demo-belt");
        warnings = ReflectionTestUtils.invokeMethod(assignments, "warnings", row);
        assertTrue(warnings.contains("资料或型号待补充"));
        row.remove("modelName");
        warnings = ReflectionTestUtils.invokeMethod(assignments, "warnings", row);
        assertFalse(warnings.contains("资料或型号待补充"));
        row.put("modelId", "unknown-BELT");
        warnings = ReflectionTestUtils.invokeMethod(assignments, "warnings", row);
        assertTrue(warnings.contains("资料或型号待补充"));
    }
}
