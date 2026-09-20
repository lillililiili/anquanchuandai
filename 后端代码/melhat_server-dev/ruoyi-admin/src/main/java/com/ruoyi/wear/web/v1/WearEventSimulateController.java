package com.ruoyi.wear.web.v1;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.event.EventIngestService;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.dto.SimulateRequest;

@Profile("!prod")
@ConditionalOnExpression("${melhat.demo-mode:false} or ${melhat.simulation-enabled:false}")
@RestController
@RequestMapping("/api/v1/events")
public class WearEventSimulateController
{
    @Autowired
    private EventIngestService ingestService;
    @Autowired
    private com.ruoyi.wear.auth.SiteAccessService siteAccessService;

    @org.springframework.web.bind.annotation.GetMapping("/simulation-scenarios")
    public R<com.alibaba.fastjson2.JSONArray> scenarios()
    {
        siteAccessService.requireLogin();
        return R.ok(com.ruoyi.wear.event.SimulationScenarios.list());
    }

    @PostMapping("/simulate")
    public R<EventDto> simulate(@RequestBody SimulateRequest request)
    {
        return R.ok(ingestService.simulate(request));
    }
}
