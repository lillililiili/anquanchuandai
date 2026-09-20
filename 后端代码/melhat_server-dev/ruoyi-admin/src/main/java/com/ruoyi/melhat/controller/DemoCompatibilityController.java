package com.ruoyi.melhat.controller;

import com.ruoyi.common.core.domain.AjaxResult;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.service.DemoCompatibilityService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 只服务于离线演示的旧页面 API，不访问设备或第三方服务。 */
@RestController
@ConditionalOnProperty(name = "melhat.demo-mode", havingValue = "true")
@RequestMapping
public class DemoCompatibilityController {

    private final DemoCompatibilityService demoService;
    private final ISafetyHatInfoService safetyHatInfoService;
    private final ISafetyHatLocationRecordService safetyHatLocationRecordService;

    public DemoCompatibilityController(DemoCompatibilityService demoService,
                                       ISafetyHatInfoService safetyHatInfoService,
                                       ISafetyHatLocationRecordService safetyHatLocationRecordService) {
        this.demoService = demoService;
        this.safetyHatInfoService = safetyHatInfoService;
        this.safetyHatLocationRecordService = safetyHatLocationRecordService;
    }

    @GetMapping({"/system/space/list", "/system/module/list", "/system/hat/list", "/aip/head/band/list"})
    public Map<String, Object> list(@RequestParam Map<String, String> params,
                                    org.springframework.web.context.request.WebRequest request) {
        String moduleKey = moduleFor(request.getDescription(false));
        int pageNum = number(params.get("pageNum"), params.get("current"), 1);
        int pageSize = number(params.get("pageSize"), params.get("size"), 10);
        return table(demoService.page(moduleKey, params, pageNum, pageSize));
    }

    @GetMapping("/system/space/{id}")
    public AjaxResult spaceDetail(@PathVariable Long id) { return detail("space", id); }

    @GetMapping("/system/module/{id}")
    public AjaxResult moduleDetail(@PathVariable Long id) { return detail("module", id); }

    @GetMapping("/system/hat/{id}")
    public AjaxResult systemHatDetail(@PathVariable Long id) { return detail("systemHat", id); }

    @GetMapping("/system/hat/getDetail/{id}")
    public AjaxResult systemHatPageDetail(@PathVariable Long id) { return detail("systemHat", id); }

    @GetMapping("/aip/head/band/{id}")
    public AjaxResult headBandDetail(@PathVariable Long id) { return detail("headBand", id); }

    @PostMapping({"/system/space", "/system/module", "/system/hat"})
    public AjaxResult create(@RequestBody Map<String, Object> payload,
                             org.springframework.web.context.request.WebRequest request) {
        return success("本地模拟新增成功", Collections.singletonMap("id", demoService.create(moduleFor(request.getDescription(false)), payload)));
    }

    @PutMapping({"/system/space", "/system/module", "/system/hat/edit", "/aip/head/band/edit"})
    public AjaxResult update(@RequestBody Map<String, Object> payload,
                             org.springframework.web.context.request.WebRequest request) {
        Long id = longValue(payload.get("id"));
        boolean changed = demoService.update(moduleFor(request.getDescription(false)), id, payload);
        return success("本地模拟更新成功", Collections.singletonMap("updated", changed));
    }

    @DeleteMapping({"/system/space/{id}", "/system/module/{id}", "/system/hat/{id}", "/aip/head/band/{id}"})
    public AjaxResult delete(@PathVariable Long id, org.springframework.web.context.request.WebRequest request) {
        boolean changed = demoService.delete(moduleFor(request.getDescription(false)), id);
        return success("本地模拟删除成功", Collections.singletonMap("deleted", changed));
    }

    @GetMapping("/aip/head/band/sync/device/info")
    public AjaxResult syncHeadBands() {
        return success("本地模拟同步完成，未访问真实设备", Collections.singletonMap("synced", 3));
    }

    @GetMapping("/system/hat/getUserOnlineHatAddress")
    public AjaxResult onlineHatAddress() {
        List<Map<String, Object>> locations = safetyHatInfoService.list(new LambdaQueryWrapper<SafetyHatInfo>()
                        .eq(SafetyHatInfo::getCreateBy, "demo")
                        .eq(SafetyHatInfo::getDelFlag, "0")
                        .eq(SafetyHatInfo::getStatus, "1")
                        .likeRight(SafetyHatInfo::getHatNumber, "MH-DEMO-")
                        .orderByAsc(SafetyHatInfo::getId))
                .stream()
                .filter(this::isDemoOnlineHat)
                .map(this::location)
                .collect(java.util.stream.Collectors.toList());
        return success("本地模拟在线位置", locations);
    }

    @GetMapping("/system/hat/getUserRealTimeLocation/{id}")
    public AjaxResult realTimeLocation(@PathVariable Long id) {
        SafetyHatInfo hat = findDemoHatByUserId(id);
        if (hat == null) {
            hat = findDemoHatById(id);
        }
        if (hat == null || hat.getId() == null || !isDemoOnlineHat(hat)) {
            throw new ServiceException("未找到绑定安全帽的本地演示位置，userId/hatId=" + id);
        }
        return success("本地模拟实时位置", location(hat));
    }

    private Map<String, Object> table(Map<String, Object> page) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("code", 200);
        result.put("msg", "查询成功（本地模拟）");
        result.put("rows", page.get("rows"));
        result.put("total", page.get("total"));
        result.put("demo", true);
        return result;
    }

    private AjaxResult detail(String moduleKey, Long id) { return success("查询成功（本地模拟）", demoService.detail(moduleKey, id)); }

    private AjaxResult success(String message, Object data) { return AjaxResult.success(message, data).put("demo", true); }

    private Map<String, Object> location(SafetyHatInfo hat) {
        SafetyHatLocationRecord latest = safetyHatLocationRecordService.list(new LambdaQueryWrapper<SafetyHatLocationRecord>()
                        .eq(SafetyHatLocationRecord::getHatId, hat.getId())
                        .orderByDesc(SafetyHatLocationRecord::getTimestamp)
                        .last("LIMIT 1"))
                .stream()
                .findFirst()
                .orElseThrow(() -> new ServiceException("安全帽缺少本地演示定位记录，hatId=" + hat.getId()));
        Map<String, Object> location = new LinkedHashMap<>();
        location.put("id", hat.getId());
        location.put("hatId", hat.getId());
        location.put("userId", latest.getUserId() == null ? hat.getBindUserId() : latest.getUserId());
        location.put("userName", latest.getUserName() == null ? hat.getBindUserName() : latest.getUserName());
        location.put("hatNumber", latest.getHatNumber() == null ? hat.getHatNumber() : latest.getHatNumber());
        location.put("longitude", latest.getLng());
        location.put("latitude", latest.getLat());
        location.put("lng", latest.getLng());
        location.put("lat", latest.getLat());
        location.put("timestamp", latest.getTimestamp());
        location.put("address", "东营市演示作业区（本地模拟）");
        location.put("status", hat.getStatus());
        location.put("demo", true);
        return location;
    }

    private SafetyHatInfo findDemoHatByUserId(Long userId) {
        return safetyHatInfoService.list(demoOnlineHatQuery()
                        .eq(SafetyHatInfo::getBindUserId, userId)
                        .orderByAsc(SafetyHatInfo::getId))
                .stream()
                .filter(this::isDemoOnlineHat)
                .findFirst()
                .orElse(null);
    }

    private SafetyHatInfo findDemoHatById(Long hatId) {
        return safetyHatInfoService.list(demoOnlineHatQuery()
                        .eq(SafetyHatInfo::getId, hatId))
                .stream()
                .filter(this::isDemoOnlineHat)
                .findFirst()
                .orElse(null);
    }

    private LambdaQueryWrapper<SafetyHatInfo> demoOnlineHatQuery() {
        return new LambdaQueryWrapper<SafetyHatInfo>()
                .eq(SafetyHatInfo::getCreateBy, "demo")
                .eq(SafetyHatInfo::getDelFlag, "0")
                .eq(SafetyHatInfo::getStatus, "1")
                .likeRight(SafetyHatInfo::getHatNumber, "MH-DEMO-");
    }

    private boolean isDemoOnlineHat(SafetyHatInfo hat) {
        return hat != null
                && "demo".equals(hat.getCreateBy())
                && "0".equals(hat.getDelFlag())
                && "1".equals(hat.getStatus())
                && hat.getHatNumber() != null
                && hat.getHatNumber().startsWith("MH-DEMO-");
    }

    private int number(String primary, String alternative, int fallback) {
        try { return Integer.parseInt(primary == null ? (alternative == null ? String.valueOf(fallback) : alternative) : primary); }
        catch (NumberFormatException ignored) { return fallback; }
    }

    private Long longValue(Object value) {
        if (value == null) { return null; }
        try { return Long.valueOf(String.valueOf(value)); }
        catch (NumberFormatException ex) { return null; }
    }

    private String moduleFor(String description) {
        if (description.contains("/system/space")) return "space";
        if (description.contains("/system/module")) return "module";
        if (description.contains("/aip/head/band")) return "headBand";
        return "systemHat";
    }
}
