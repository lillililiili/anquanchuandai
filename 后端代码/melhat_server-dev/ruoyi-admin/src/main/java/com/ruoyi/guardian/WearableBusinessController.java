package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;
import static com.ruoyi.guardian.WearableModel.object;

@RestController
@RequestMapping("/api/admin/v1")
public class WearableBusinessController {
    private final GuardianAccess access;private final WearableBusinessPolicy policy;private final ExternalDataStore external;
    public WearableBusinessController(GuardianAccess access,WearableBusinessPolicy policy,ExternalDataStore external){this.access=access;this.policy=policy;this.external=external;}
    private GuardianAccess.Context context(HttpServletRequest r){return access.context(WearableSessions.actor(r));}
    @GetMapping("/business-config") public JSONObject config(HttpServletRequest r){context(r);return policy.config();}
    @PatchMapping("/business-config") public JSONObject configure(@RequestBody JSONObject body,HttpServletRequest r){return policy.configure(body,context(r));}
    @GetMapping("/external/integrations") public JSONObject integrations(@RequestParam(required=false)String siteId,HttpServletRequest r){return object("items",external.integrations(context(r),siteId));}
    @GetMapping("/external/records") public JSONObject records(@RequestParam(required=false)String siteId,@RequestParam(required=false)String integrationId,@RequestParam(defaultValue="1")int page,@RequestParam(defaultValue="50")int pageSize,HttpServletRequest r){return external.records(context(r),siteId,integrationId,page,pageSize);}
}
