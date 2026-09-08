package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.mapper.ElectronicFenceAlarmMapper;
import com.ruoyi.helmet.pojo.po.ElectronicFenceAlarm;
import com.ruoyi.helmet.service.ElectronicFenceAlarmService;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

@Service
public class ElectronicFenceAlarmServiceImpl extends ServiceImpl<ElectronicFenceAlarmMapper, ElectronicFenceAlarm> implements ElectronicFenceAlarmService {

    @Override
    public Page<ElectronicFenceAlarm> pageWithFilter(int current, int size, String alarmType, String userName, Date startTime, Date endTime) {
        List<ElectronicFenceAlarm> list = this.baseMapper.selectWithFenceName(alarmType, userName, startTime, endTime);
        int total = list.size();
        int fromIndex = (current - 1) * size;
        int toIndex = Math.min(fromIndex + size, total);
        List<ElectronicFenceAlarm> pageList = fromIndex < total ? list.subList(fromIndex, toIndex) : new ArrayList<>();

        Page<ElectronicFenceAlarm> page = new Page<>(current, size, total);
        page.setRecords(pageList);

        // 组装 triggerPersonInfo
        for (ElectronicFenceAlarm record : pageList) {
            record.setTriggerPersonInfo(record.getUserName() + " (安全帽 #" + record.getHatNumber() + ")");
        }

        return page;
    }

    @Override
    public boolean markAsHandled(Long alarmId, String description) {
        ElectronicFenceAlarm alarm = this.getById(alarmId);
        if (alarm == null) return false;
        if( alarm.getIsHandled() == 1){
            throw new ServiceException("已处理");
        }
        alarm.setIsHandled(1);
        Date date = new Date();
        alarm.setHandleTime(date);
        alarm.setDescription(description);
        alarm.setUpdateTime(date);
        return this.updateById(alarm);
    }

    @Override
    public ElectronicFenceAlarm getByIdWithFenceName(Long alarmId) {
        ElectronicFenceAlarm alarm = this.getById(alarmId);
        if (alarm != null) {
            alarm.setTriggerPersonInfo(alarm.getUserName() + " (安全帽 #" + alarm.getHatNumber() + ")");
        }
        return alarm;
    }
}