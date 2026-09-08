package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.helmet.service.IRealTimeAlarmService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import io.swagger.annotations.ApiParam;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;
import org.springframework.stereotype.Controller;

import java.util.Date;
import java.util.HashMap;
import java.util.Map;

/**
 * <p>
 * 实时告警表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/alarm")
@Api(tags = "实时告警接口")
public class RealTimeAlarmController extends BaseController {
    @Autowired
    private IRealTimeAlarmService realTimeAlarmService;

    /**
     * 分页查询报警记录（支持多条件过滤）
     */
    @GetMapping("/page")
    @ApiOperation(value = "分页查询报警记录")
    public R<IPage<RealTimeAlarm>> getPage(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String alarmType,
            @RequestParam(required = false) String userName,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date startTimeFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date startTimeTo,
            @RequestParam(required = false) Integer isHandled
    ) {
        IPage<RealTimeAlarm> alarmIPage = realTimeAlarmService.pageWithFilter(current, size, alarmType, userName, startTimeFrom, startTimeTo, isHandled);
        return R.ok(alarmIPage);
    }

    /**
     * 获取未处理报警数量（用于前端 badge 显示）
     */
    @GetMapping("/unhandled-count")
    @ApiOperation(value = "获取未处理报警数量")
    public R<Map<String, Object>> getUnhandledCount() {
        Map<String, Object> result = new HashMap<>();
        result.put("count", realTimeAlarmService.getUnHandledCount());
        return R.ok(result);
    }

    /**
     * 根据ID获取报警详情
     */
    @GetMapping("/{id}")
    @ApiOperation(value = "根据ID获取报警详情")
    public R<RealTimeAlarm> getById(@PathVariable Long id) {
        RealTimeAlarm realTimeAlarm = realTimeAlarmService.getById(id);
        return R.ok(realTimeAlarm);
    }

    /**
     * 标记为已处理（带处理描述）
     */
    @PutMapping("/handle")
    @ApiOperation(value = "标记为已处理（带处理描述）")
    public R handle(@RequestBody RealTimeAlarm alarm) {
        realTimeAlarmService.markAsHandled(alarm.getId(), alarm.getDescription());
        return R.ok();
    }

    /**
     * 快捷“接听”操作（仅标记为处理中或记录接听时间，可根据业务扩展）
     */
    @PutMapping("/answer/{id}")
    @ApiOperation(value = "接听操作")
    public R answer(@PathVariable Long id) {
        // 此处可根据需求扩展：比如记录接听人、接听时间、触发语音通话等
        RealTimeAlarm alarm = realTimeAlarmService.getById(id);
        if (alarm != null && alarm.getIsHandled() == 0) {
            // 可选：设置一个临时状态或记录接听动作
            // 这里简单起见，不改变状态，仅返回成功
            return R.ok();
        }
        return R.fail();
    }

    /**
     * 逻辑删除报警记录
     */
    @DeleteMapping("/{id}")
    @ApiOperation(value = "逻辑删除报警记录")
    public R delete(@PathVariable Long id) {
         realTimeAlarmService.deleteById(id);
         return  R.ok();
    }

    /**
     * 模拟接收新报警（用于测试或设备上报）
     */
    @PostMapping("/receive")
    @ApiOperation(value = "接收新报警")
    public R receiveAlarm(@RequestBody RealTimeAlarm alarm) {
        alarm.setIsHandled(0);
        alarm.setDelFlag("0");
        alarm.setCreateTime(new Date());
        alarm.setAlarmStartTime(new Date());
        realTimeAlarmService.save(alarm);
        return  R.ok();
    }
}
