package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin/v1/works")
public class AdminWorksController {
    private final AdminWorks works;
    public AdminWorksController(AdminWorks works){this.works=works;}
    @GetMapping public JSONObject list(HttpServletRequest r,@RequestParam(required=false)String siteId,@RequestParam(required=false)String keyword,@RequestParam(required=false)String date,@RequestParam(required=false)String status,@RequestParam(defaultValue="1")int pageNum,@RequestParam(defaultValue="20")int pageSize){return works.list(WearableSessions.actor(r),siteId,keyword,date,status,pageNum,pageSize);}
    @GetMapping("/options") public JSONObject options(HttpServletRequest r,@RequestParam(required=false)String siteId){return works.options(WearableSessions.actor(r),siteId);}
    @GetMapping("/{id}") public JSONObject detail(HttpServletRequest r,@PathVariable String id){return works.detail(WearableSessions.actor(r),id);}
    @PostMapping public JSONObject create(HttpServletRequest r,@RequestBody JSONObject body){return works.write(WearableSessions.actor(r),null,"create",body);}
    @PatchMapping("/{id}") public JSONObject update(HttpServletRequest r,@PathVariable String id,@RequestBody JSONObject body){return works.write(WearableSessions.actor(r),id,"update",body);}
    @PostMapping("/{id}/actions") public JSONObject action(HttpServletRequest r,@PathVariable String id,@RequestBody JSONObject body){return works.write(WearableSessions.actor(r),id,body.getString("action"),body);}
}
