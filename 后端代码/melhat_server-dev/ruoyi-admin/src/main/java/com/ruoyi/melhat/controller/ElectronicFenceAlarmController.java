package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.ElectronicFenceAlarm;
import com.ruoyi.helmet.service.ElectronicFenceAlarmService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;

import java.util.Date;
import java.util.Map;

@RestController
@RequestMapping("/hat/fence/alarm")
@Api(tags = "电子围栏报警接口")
public class ElectronicFenceAlarmController extends BaseController {

    @Autowired
    private ElectronicFenceAlarmService alarmService;

    @GetMapping("/page")
    @ApiOperation(value = "电子围栏报警列表")
    public R<Page<ElectronicFenceAlarm>> getPage(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String alarmType,
            @RequestParam(required = false) String userName,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date startTime,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date endTime
    ) {
        return R.ok(alarmService.pageWithFilter(current, size, alarmType, userName, startTime, endTime));
    }

    @GetMapping("/{id}")
    @ApiOperation(value = "根据id查询电子围栏报警信息")
    public R<ElectronicFenceAlarm> getById(@PathVariable Long id) {
        return R.ok(alarmService.getByIdWithFenceName(id));
    }

    @PutMapping("/handle")
    @ApiOperation(value = "根据id处理电子围栏报警信息")
    public R handle(@RequestBody ElectronicFenceAlarm alarm) {
        alarmService.markAsHandled(alarm.getId(), alarm.getDescription());
        return R.ok();
    }

    @DeleteMapping("/{id}")
    @ApiOperation(value = "根据id删除电子围栏报警信息")
    public R delete(@PathVariable Long id) {
        ElectronicFenceAlarm alarm = new ElectronicFenceAlarm();
        alarm.setId(id);
        alarm.setDelFlag("2");
        alarm.setUpdateTime(new Date());
        alarmService.updateById(alarm);
        return  R.ok();
    }
}
