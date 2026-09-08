package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;

import java.util.List;

/**
 * <p>
 * 安全帽定位记录表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface ISafetyHatLocationRecordService extends IService<SafetyHatLocationRecord> {
    /**
     * 查询轨迹点（支持多设备、时间范围）
     */
    List<SafetyHatLocationRecord> getTrajectoryPoints(
            List<Long> hatIds,
            String startTime,
            String endTime
    );

    /**
     * 根据 hatId 获取设备基本信息（可选，用于组装 deviceInfo）
     */
    SafetyHatInfo getDeviceInfoByHatId(Long hatId);

}
