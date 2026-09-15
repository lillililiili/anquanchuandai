package com.ruoyi.wear.web.v1;

import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.wear.admin.AdminOverviewService;

@RestController
@RequestMapping("/api/v1/admin")
public class WearAdminController
{
    @Autowired private AdminOverviewService adminOverviewService;

    @GetMapping("/overview")
    public R<Map<String, Object>> overview()
    {
        return R.ok(adminOverviewService.overview());
    }
}
