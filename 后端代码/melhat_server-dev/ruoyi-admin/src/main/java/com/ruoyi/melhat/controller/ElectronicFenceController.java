package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.ElectronicFence;
import com.ruoyi.helmet.pojo.po.ElectronicFenceLatitude;
import com.ruoyi.helmet.service.IElectronicFenceService;
import com.ruoyi.helmet.vo.SaveFenceRequest;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import io.swagger.annotations.ApiParam;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;
import org.springframework.stereotype.Controller;

import java.util.Date;
import java.util.List;

/**
 * <p>
 * 电子围栏记录表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/electronic/fence")
@Api(tags = "电子围栏接口")
public class ElectronicFenceController extends BaseController {
    @Autowired
    private IElectronicFenceService fenceService;

    @GetMapping("/page")
    @ApiOperation(value = "电子围栏列表")
    public R<Page<ElectronicFence>> getPage(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String fenceName,
            @RequestParam(required = false) String fenceType,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date startTime,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date endTime
    ) {
        return R.ok(fenceService.pageWithFilter(current, size, fenceName, fenceType, startTime, endTime));
    }

    @GetMapping("/{id}")
    @ApiOperation(value = "根据id查询电子围栏详情")
    public R<ElectronicFence> getById(@PathVariable Long id) {
        return R.ok(fenceService.getByIdWithCoordinates(id));
    }

    @PostMapping
    @ApiOperation(value = "保存电子围栏")
    public R save(@ApiParam(value = "坐标数据放到coordinates") @RequestBody SaveFenceRequest request) {
         fenceService.saveWithCoordinates(request.getFence(), request.getCoordinates());
        return  R.ok();
    }

    @PutMapping
    @ApiOperation(value = "修改电子围栏")
    public R update(@ApiParam(value = "坐标数据放到coordinates") @RequestBody SaveFenceRequest request) {
        fenceService.updateWithCoordinates(request.getFence(), request.getCoordinates());
        return  R.ok();
    }

    @DeleteMapping("/{id}")
    @ApiOperation(value = "删除电子围栏")
    public R delete(@PathVariable Long id) {
        fenceService.deleteFence(id);
        return R.ok();
    }


}
