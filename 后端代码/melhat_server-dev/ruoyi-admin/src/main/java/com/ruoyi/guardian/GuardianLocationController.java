package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.*;
import javax.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api/guardian/v1/locations")
public class GuardianLocationController {
    private final GuardianLocations locations;
    public GuardianLocationController(GuardianLocations locations) { this.locations=locations; }
    @GetMapping("/history") public JSONObject history(HttpServletRequest request,
            @RequestParam(required=false) String personId,@RequestParam(required=false) String deviceId,
            @RequestParam String from,@RequestParam String to,@RequestParam(required=false) String cursor,
            @RequestParam(defaultValue="500") int limit) {
        return locations.history(WearableSessions.actor(request),personId,deviceId,from,to,cursor,limit);
    }
    @GetMapping("/people/{id}") public JSONObject current(HttpServletRequest request,@PathVariable String id) {
        return locations.current(WearableSessions.actor(request),id);
    }
}
