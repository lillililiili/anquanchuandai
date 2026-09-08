package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.ElectronicFenceAlarm;

import java.util.Date;

public interface ElectronicFenceAlarmService extends IService<ElectronicFenceAlarm> {

    Page<ElectronicFenceAlarm> pageWithFilter(int current, int size, String alarmType, String userName, Date startTime, Date endTime);

    boolean markAsHandled(Long alarmId, String description);

    ElectronicFenceAlarm getByIdWithFenceName(Long alarmId);
}
