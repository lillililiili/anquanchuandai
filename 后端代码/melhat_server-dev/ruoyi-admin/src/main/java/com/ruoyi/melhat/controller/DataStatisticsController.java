package com.ruoyi.melhat.controller;

import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.service.DataStatisticsService;
import com.ruoyi.helmet.vo.AppDataStat;
import com.ruoyi.helmet.vo.DashboardDataStat;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/hat/data/statistics")
@Api(tags = "数据统计接口")
public class DataStatisticsController extends BaseController {
    
    @Autowired
    private DataStatisticsService dataStatisticsService;
    
    @GetMapping("/app/query")
    @ApiOperation(value = "获取 APP 数据统计信息")
    public R<AppDataStat> appQuery() {
        return R.ok(dataStatisticsService.getAppDataStat());
    }
    
    @GetMapping("/dashboard/query")
    @ApiOperation(value = "获取 Dashboard 数据统计信息")
    public R<DashboardDataStat> dashboardQuery() {
        return R.ok(dataStatisticsService.getDashboardDataStat());
    }

}