package com.ruoyi.melhat.controller;

import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.helmet.service.PlatformDeviceSyncService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/hat/safety/info/platform")
@ConditionalOnProperty(name = "melhat.demo-mode", havingValue = "false", matchIfMissing = true)
@PreAuthorize("@ss.hasRole('admin')")
public class PlatformDeviceSyncController {
    private final PlatformDeviceSyncService service;
    public PlatformDeviceSyncController(PlatformDeviceSyncService service) { this.service = service; }

    @GetMapping("/devices")
    public R<List<HeadbandVO>> preview() throws Exception { return R.ok(service.preview()); }

    @PostMapping("/sync")
    public synchronized R<Map<String, Integer>> sync() throws Exception {
        return R.ok(service.sync(SecurityUtils.getUsername()));
    }
}
