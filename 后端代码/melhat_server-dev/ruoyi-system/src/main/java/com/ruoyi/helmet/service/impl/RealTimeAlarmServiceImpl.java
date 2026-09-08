package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.helmet.mapper.RealTimeAlarmMapper;
import com.ruoyi.helmet.pojo.po.IntercomRecord;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.helmet.service.IRealTimeAlarmService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Date;

/**
 * <p>
 * 实时告警表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class RealTimeAlarmServiceImpl extends ServiceImpl<RealTimeAlarmMapper, RealTimeAlarm> implements IRealTimeAlarmService {
    @Autowired
    private RealTimeAlarmMapper realTimeAlarmMapper;
    @Override
    public IPage<RealTimeAlarm> pageWithFilter(int current, int size, String alarmType, String userName,
                                               Date startTimeFrom, Date startTimeTo, Integer isHandled) {
        LambdaQueryWrapper<RealTimeAlarm> wrapper = new LambdaQueryWrapper<>();

        if (alarmType != null && !alarmType.isEmpty() && !"全部".equals(alarmType)) {
            wrapper.eq(RealTimeAlarm::getAlarmType, alarmType);
        }
        if (userName != null && !userName.isEmpty()) {
            wrapper.like(RealTimeAlarm::getUserName, userName);
        }
        if (startTimeFrom != null) {
            wrapper.ge(RealTimeAlarm::getAlarmStartTime, startTimeFrom);
        }
        if (startTimeTo != null) {
            wrapper.le(RealTimeAlarm::getAlarmStartTime, startTimeTo);
        }
        if (isHandled != null) {
            wrapper.eq(RealTimeAlarm::getIsHandled, isHandled);
        }

        // 只查未删除的记录
        wrapper.eq(RealTimeAlarm::getDelFlag, "0");

        return this.page(new Page<>(current, size), wrapper);
    }

    @Override
    public boolean markAsHandled(Long alarmId, String description) {
        RealTimeAlarm alarm = this.getById(alarmId);
        if (alarm == null) {
            return false;
        }
        if(alarm.getIsHandled() == 1){
            throw new ServiceException("已处理");
        }
        alarm.setIsHandled(1);
        Date date  = new Date();
        alarm.setHandleTime(date);
        alarm.setDescription(description);
        alarm.setUpdateTime(date);
        alarm.setUpdateBy(SecurityUtils.getUsername());
        return this.updateById(alarm);
    }

    @Override
    public long getUnHandledCount() {
        LambdaQueryWrapper<RealTimeAlarm> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(RealTimeAlarm::getIsHandled, 0)
                .eq(RealTimeAlarm::getDelFlag, "0");
        return this.count(wrapper);
    }

    @Override
    public RealTimeAlarm getById(Long alarmId) {
        return realTimeAlarmMapper.selectById(alarmId);
    }

    @Override
    public boolean deleteById(Long alarmId) {
        return this.update(null,new LambdaUpdateWrapper<RealTimeAlarm>()
                .eq(RealTimeAlarm::getId, alarmId)
                .set(RealTimeAlarm::getDelFlag,"2")
                .set(RealTimeAlarm::getUpdateTime,new Date()));
    }
}
