package com.ruoyi.wear.web.v1;

import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import com.ruoyi.common.annotation.Anonymous;
import com.ruoyi.common.annotation.RateLimiter;
import com.ruoyi.common.enums.LimitType;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.framework.web.service.SysLoginService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.person.AccountRecoveryService;

@RestController
@RequestMapping("/api/v1/account-recovery")
public class WearAccountRecoveryController {
    @Autowired private AccountRecoveryService recovery;
    @Autowired private SysLoginService login;

    @Anonymous
    @RateLimiter(time=600, count=5, limitType=LimitType.IP)
    @PostMapping("/requests")
    public R<Map<String,Object>> submit(@RequestBody Map<String,Object> body) {
        login.validateCaptcha("account-recovery", Objects.toString(body.get("code"), ""), Objects.toString(body.get("uuid"), ""));
        return R.ok(recovery.submit(body));
    }
    @GetMapping("/requests")
    public R<WearPage<Map<String,Object>>> page(@RequestParam(defaultValue="1") int current,
        @RequestParam(defaultValue="20") int size, @RequestParam(defaultValue="pending") String status) {
        return R.ok(recovery.page(current, size, status));
    }
    @GetMapping("/accounts")
    public R<List<Map<String,Object>>> accounts(@RequestParam(required=false) String q) {
        return R.ok(recovery.accounts(q));
    }
    @PostMapping("/requests/{id}/approve")
    public R<Void> approve(@PathVariable String id, @RequestBody Map<String,Object> body) {
        recovery.review(id, true, body); return R.ok();
    }
    @PostMapping("/requests/{id}/reject")
    public R<Void> reject(@PathVariable String id, @RequestBody Map<String,Object> body) {
        recovery.review(id, false, body); return R.ok();
    }
}
