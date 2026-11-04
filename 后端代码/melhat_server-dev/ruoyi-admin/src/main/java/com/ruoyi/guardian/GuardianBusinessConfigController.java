package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/guardian/v1/business-config")
public class GuardianBusinessConfigController {
    private final GuardianAccess access;private final WearableBusinessPolicy policy;
    public GuardianBusinessConfigController(GuardianAccess access,WearableBusinessPolicy policy){this.access=access;this.policy=policy;}
    @GetMapping public JSONObject config(HttpServletRequest request){access.context(WearableSessions.actor(request));return policy.config();}
}
