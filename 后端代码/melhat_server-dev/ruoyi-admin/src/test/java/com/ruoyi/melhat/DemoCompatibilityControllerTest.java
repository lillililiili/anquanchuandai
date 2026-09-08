package com.ruoyi.melhat;

import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.mapper.DemoCompatRecordMapper;
import com.ruoyi.helmet.pojo.po.DemoCompatRecord;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.service.DemoCompatibilityService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import com.ruoyi.helmet.service.impl.DemoCompatibilityServiceImpl;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import com.ruoyi.melhat.controller.DemoCompatibilityController;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 缺失旧页面接口的 HTTP 契约：所有响应均明确标记为本地演示。
 */
class DemoCompatibilityControllerTest {

    @Test
    void allListsReturnRuoYiPageContractWithDemoRecords() throws Exception {
        assertList("/system/space/list");
        assertList("/system/module/list");
        assertList("/system/hat/list");
        assertList("/aip/head/band/list");
    }

    @Test
    void detailsAndWritesReturnAjaxResultWithDemoMarker() throws Exception {
        MockMvc mockMvc = mockMvc();
        mockMvc.perform(get("/system/space/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.id").value(1))
                .andExpect(jsonPath("$.demo").value(true));

        mockMvc.perform(post("/system/module")
                        .contentType("application/json")
                        .content("{\"moduleName\":\"演示模块\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.demo").value(true));

        mockMvc.perform(delete("/aip/head/band/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.demo").value(true));
    }

    @Test
    void editGetDetailLocationAndSyncUseTheirExactLegacyMappings() throws Exception {
        DemoCompatibilityService service = mock(DemoCompatibilityService.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        ISafetyHatLocationRecordService locations = mock(ISafetyHatLocationRecordService.class);
        when(service.update(anyString(), anyLong(), anyMap())).thenReturn(true);
        when(service.detail(anyString(), anyLong())).thenReturn(record(1L));
        SafetyHatInfo hat = hat(91L, 81L, "MH-DEMO-091");
        when(hats.list(any())).thenReturn(Collections.singletonList(hat));
        when(hats.getHatByUserId(81L)).thenReturn(hat);
        when(locations.list(any())).thenReturn(Collections.singletonList(location(91L, 81L, "MH-DEMO-091")));
        MockMvc mockMvc = standaloneSetup(new DemoCompatibilityController(service, hats, locations)).build();

        mockMvc.perform(put("/system/space").contentType("application/json").content("{\"id\":1,\"name\":\"空间\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(put("/system/module").contentType("application/json").content("{\"id\":1,\"moduleName\":\"模块\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(put("/system/hat/edit").contentType("application/json").content("{\"id\":1,\"hatNumber\":\"MH\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(put("/aip/head/band/edit").contentType("application/json").content("{\"id\":1,\"name\":\"人员\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(get("/system/hat/getDetail/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value(1));
        mockMvc.perform(get("/system/hat/getUserOnlineHatAddress"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].id").value(91))
                .andExpect(jsonPath("$.data[0].hatNumber").value("MH-DEMO-091"));
        mockMvc.perform(get("/system/hat/getUserRealTimeLocation/81"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.userId").value(81))
                .andExpect(jsonPath("$.data.hatNumber").value("MH-DEMO-091"));
        mockMvc.perform(get("/aip/head/band/sync/device/info"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.demo").value(true));

        verify(service).update(eq("space"), eq(1L), anyMap());
        verify(service).update(eq("module"), eq(1L), anyMap());
        verify(service).update(eq("systemHat"), eq(1L), anyMap());
        verify(service).update(eq("headBand"), eq(1L), anyMap());
        verify(service).detail("systemHat", 1L);
    }

    @Test
    void updateMergesFieldsAndKeepsExistingPayloadValues() {
        DemoCompatRecordMapper mapper = mock(DemoCompatRecordMapper.class);
        DemoCompatRecord current = new DemoCompatRecord();
        current.setId(1L);
        current.setModuleKey("systemHat");
        current.setBusinessKey("demo-systemhat-01");
        current.setPayload("{\"hatNumber\":\"MH-DEMO-001\",\"name\":\"旧名称\",\"demo\":true}");
        when(mapper.selectOne(any())).thenReturn(current);
        when(mapper.updateById(any(DemoCompatRecord.class))).thenReturn(1);

        new DemoCompatibilityServiceImpl(mapper).update("systemHat", 1L,
                new LinkedHashMap<String, Object>() {{ put("id", 1L); put("name", "新名称"); put("demo", false); }});

        org.mockito.ArgumentCaptor<DemoCompatRecord> saved = org.mockito.ArgumentCaptor.forClass(DemoCompatRecord.class);
        verify(mapper).updateById(saved.capture());
        Map<String, Object> payload = com.alibaba.fastjson2.JSON.parseObject(saved.getValue().getPayload());
        org.junit.jupiter.api.Assertions.assertEquals("MH-DEMO-001", payload.get("hatNumber"));
        org.junit.jupiter.api.Assertions.assertEquals("新名称", payload.get("name"));
        org.junit.jupiter.api.Assertions.assertTrue(payload.containsKey("demo"));
    }

    @Test
    void locationEndpointsRejectNonDemoHatCandidatesAndQueryOnlyDemoOnlineHats() throws Exception {
        DemoCompatibilityService service = mock(DemoCompatibilityService.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        ISafetyHatLocationRecordService locations = mock(ISafetyHatLocationRecordService.class);
        SafetyHatInfo nonDemo = hat(901L, 801L, "MH-EXTERNAL-901");
        nonDemo.setCreateBy("external");
        when(hats.list(any())).thenReturn(Collections.singletonList(nonDemo));
        when(hats.getHatByUserId(801L)).thenReturn(nonDemo);
        MockMvc mockMvc = standaloneSetup(new DemoCompatibilityController(service, hats, locations)).build();

        mockMvc.perform(get("/system/hat/getUserOnlineHatAddress"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.length()").value(0));
        org.junit.jupiter.api.Assertions.assertThrows(ServiceException.class,
                () -> new DemoCompatibilityController(service, hats, locations).realTimeLocation(801L));
        verify(hats, never()).getHatByUserId(801L);
        verify(hats, never()).getById(801L);
    }

    private void assertList(String path) throws Exception {
        mockMvc().perform(get(path).param("pageNum", "1").param("pageSize", "10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.rows.length()").value(org.hamcrest.Matchers.greaterThanOrEqualTo(3)))
                .andExpect(jsonPath("$.total").value(org.hamcrest.Matchers.greaterThanOrEqualTo(3)))
                .andExpect(jsonPath("$.demo").value(true));
    }

    private MockMvc mockMvc() {
        DemoCompatibilityService service = mock(DemoCompatibilityService.class);
        Map<String, Object> page = new LinkedHashMap<>();
        page.put("rows", Arrays.asList(record(1L), record(2L), record(3L)));
        page.put("total", 3);
        when(service.page(anyString(), anyMap(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt())).thenReturn(page);
        when(service.detail(anyString(), anyLong())).thenReturn(record(1L));
        when(service.create(anyString(), anyMap())).thenReturn(4L);
        when(service.delete(anyString(), anyLong())).thenReturn(true);
        return standaloneSetup(new DemoCompatibilityController(service,
                mock(ISafetyHatInfoService.class), mock(ISafetyHatLocationRecordService.class))).build();
    }

    private Map<String, Object> record(Long id) {
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("id", id);
        record.put("businessKey", "demo-" + id);
        record.put("demo", true);
        return record;
    }

    private SafetyHatInfo hat(Long id, Long userId, String number) {
        SafetyHatInfo hat = new SafetyHatInfo();
        hat.setId(id);
        hat.setBindUserId(userId);
        hat.setBindUserName("演示人员");
        hat.setHatNumber(number);
        hat.setStatus("1");
        hat.setCreateBy("demo");
        hat.setDelFlag("0");
        return hat;
    }

    private SafetyHatLocationRecord location(Long hatId, Long userId, String number) {
        SafetyHatLocationRecord record = new SafetyHatLocationRecord();
        record.setHatId(hatId);
        record.setUserId(userId);
        record.setHatNumber(number);
        record.setLng("118.4968");
        record.setLat("37.4615");
        record.setTimestamp("2026-08-29 12:00:00");
        return record;
    }
}
