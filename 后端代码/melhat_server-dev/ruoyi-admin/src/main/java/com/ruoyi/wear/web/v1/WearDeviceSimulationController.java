package com.ruoyi.wear.web.v1;

import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.*;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.device.DeviceSimulationStateService;

@Profile("!prod")
@ConditionalOnProperty(name = "melhat.call-lab.enabled", havingValue = "true")
@RestController
@RequestMapping("/api/v1/simulation/devices")
public class WearDeviceSimulationController
{
    @Autowired private DeviceSimulationStateService states;

    @PostMapping("/{id}/state")
    public R<Map<String, Object>> report(@PathVariable Long id, @RequestBody Map<String, Object> body)
    {
        return R.ok(states.report(id, body));
    }
}
