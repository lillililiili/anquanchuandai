package com.ruoyi.melhat.controller;

import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.service.IFileRecordService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import io.swagger.annotations.ApiParam;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.stereotype.Controller;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * <p>
 * 安全帽定位记录表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/location/record")
@Api(tags = "安全帽定位记录接口")
public class SafetyHatLocationRecordController extends BaseController {
    @Autowired
    private ISafetyHatLocationRecordService safetyHatLocationRecordService;
    @Autowired
    private IFileRecordService fileRecordService;

    /**
     * 查询轨迹点（支持多设备、时间范围）
     * 请求示例：
     * POST /api/trajectory/query
     * Body: {
     * "hatIds": [1, 2, 3],
     * "startTime": "2023-11-15 08:00:00",
     * "endTime": "2023-11-15 18:00:00"
     * }
     */
    @PostMapping("/query")
    @ApiOperation(value = "查询轨迹点")
    public R<List<SafetyHatLocationRecord>> queryTrajectory(@ApiParam(value = "hatIds：帽子id数组;开始时间：startTime，结束时间:endTime")
                                                            @RequestBody Map<String, Object> params) {
        List<Long> hatIds = (List<Long>) params.get("hatIds");
        String startTime = (String) params.get("startTime");
        String endTime = (String) params.get("endTime");

        List<SafetyHatLocationRecord> recordList = safetyHatLocationRecordService.getTrajectoryPoints(hatIds, startTime, endTime);
        return R.ok(recordList);
    }

    /**
     * 获取单个设备的历史轨迹（简化版）
     */
    @GetMapping("/single/{hatId}")
    @ApiOperation(value = "获取单个设备的历史轨迹")
    public R<List<SafetyHatLocationRecord>> getSingleTrajectory(
            @PathVariable Long hatId,
            @RequestParam(required = false) String startTime,
            @RequestParam(required = false) String endTime
    ) {
        List list = new ArrayList();
        list.add(hatId);
        List<SafetyHatLocationRecord> safetyHatLocationRecords = safetyHatLocationRecordService.getTrajectoryPoints(list, startTime, endTime);
        return R.ok(safetyHatLocationRecords);
    }

    /**
     * 获取设备信息（用于前端标签显示）
     */
    @GetMapping("/device-info/{hatId}")
    @ApiOperation(value = "获取设备信息")
    public R<SafetyHatInfo> getDeviceInfo(@PathVariable Long hatId) {
        SafetyHatInfo safetyHatInfo = safetyHatLocationRecordService.getDeviceInfoByHatId(hatId);
        return R.ok(safetyHatInfo);
    }

    /**
     * 获取轨迹点关联视频（可选）
     */
    @GetMapping("/relatedFiles")
    @ApiOperation(value = "获取轨迹关联文件")
    public R<List<FileRecord>> getRelatedFiles(@RequestParam(value = "hatNumber",required = true) String hatNumber,
                                     @RequestParam(value = "fileType",required = false) String fileType,
                                     @RequestParam(value = "startTime",required = false) String startTime,
                                     @RequestParam(value = "endTime",required = false) String endTime) {
        List<FileRecord> fileRecords = fileRecordService.getRelatedFiles(hatNumber,fileType,startTime,endTime);
        return R.ok(fileRecords);
    }
}
