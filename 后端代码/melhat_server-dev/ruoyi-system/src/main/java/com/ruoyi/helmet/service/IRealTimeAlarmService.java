package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;

import java.util.Date;

/**
 * <p>
 * 实时告警表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface IRealTimeAlarmService extends IService<RealTimeAlarm> {
    /**
     * 分页查询报警记录（支持多条件过滤）
     */
    IPage<RealTimeAlarm> pageWithFilter(
            int current,
            int size,
            String alarmType,
            String userName,
            Date startTimeFrom,
            Date startTimeTo,
            Integer isHandled
    );

    /**
     * 标记为已处理
     */
    boolean markAsHandled(Long alarmId, String description);

    /**
     * 获取未处理报警数量
     */
    long getUnHandledCount();

    /**
     * 根据ID获取报警详情
     */
    RealTimeAlarm getById(Long alarmId);

    /**
     * 逻辑删除报警记录
     */
    boolean deleteById(Long alarmId);

}
