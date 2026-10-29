package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api/admin/v1/maintenance")
public class WearableMaintenanceController {
    private final WearableMaintenance maintenance;
    public WearableMaintenanceController(WearableMaintenance maintenance){this.maintenance=maintenance;}
    @GetMapping public JSONObject status(HttpServletRequest request){WearableMaintenance.requireSystem(WearableSessions.actor(request));return maintenance.status();}
    @PostMapping public JSONObject change(@RequestBody JSONObject body,HttpServletRequest request){
        WearableMaintenance.requireSystem(WearableSessions.actor(request));
        String mode=body.getString("mode");
        if(!"ACTIVE".equals(mode)&&!"PAUSED".equals(mode))throw AdminQueryService.fail(400,"INVALID_MAINTENANCE_MODE","维护模式仅支持 ACTIVE 或 PAUSED");
        return maintenance.setPaused("PAUSED".equals(mode),WearableSessions.actor(request));
    }
}
