package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.helmet.mapper.SafetyHatLocationRecordMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * <p>
 * 安全帽定位记录表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class SafetyHatLocationRecordServiceImpl extends ServiceImpl<SafetyHatLocationRecordMapper, SafetyHatLocationRecord> implements ISafetyHatLocationRecordService {
    @Autowired
    private SafetyHatLocationRecordMapper locationRecordMapper;
    @Autowired
    private ISafetyHatInfoService safetyHatInfoService;

    @Override
    public List<SafetyHatLocationRecord> getTrajectoryPoints(List<Long> hatIds, String startTime, String endTime) {
        List<SafetyHatLocationRecord> records = locationRecordMapper.selectTrajectoryPoints(hatIds, startTime, endTime);

        // 组装 deviceInfo 字段
        for (SafetyHatLocationRecord record : records) {
            record.setDeviceInfo(getDeviceInfoByHatId(record.getHatId()));
            // 可选：设置关联视频URL //todo 根据时间查询关联的视频？
            // record.setRelatedVideoUrl(getRelatedVideoUrl(record.getId()));
        }

        return records;
    }

    @Override
    public SafetyHatInfo getDeviceInfoByHatId(Long hatId) {
        SafetyHatInfo hatInfo = safetyHatInfoService.getById(hatId);
        return hatInfo;
    }

}
