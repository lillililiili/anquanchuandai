package com.ruoyi.portal.demo;

import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.*;
import com.ruoyi.portal.PortalModels.Envelope;

@RestController @Profile("portal-demo") @RequestMapping("/api/portal/v1")
public class DemoAssignmentController {
    private final DemoAssignmentService service;
    public DemoAssignmentController(DemoAssignmentService service){this.service=service;}
    public static class Issue { public String siteId,personId,deviceId; }
    public static class Return { public String siteId;public Long version; }
    @GetMapping("/equipment-assignments/options") public Envelope<Object> options(@RequestParam String siteId,@RequestParam String personId){return new Envelope<>(200,"模拟装备选项",null,service.options(siteId,personId));}
    @PostMapping("/equipment-assignments") public Envelope<Object> issue(@RequestHeader("Idempotency-Key")String key,@RequestBody Issue body){return new Envelope<>(200,"演示领用已保存",null,service.issue(key,body));}
    @PostMapping("/equipment-assignments/{id}/return") public Envelope<Object> giveBack(@PathVariable String id,@RequestHeader("Idempotency-Key")String key,@RequestBody Return body){return new Envelope<>(200,"演示归还已保存",null,service.giveBack(id,key,body));}
}
