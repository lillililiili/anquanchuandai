package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.ElectronicFence;
import com.ruoyi.helmet.pojo.po.ElectronicFenceLatitude;

import java.util.Date;
import java.util.List;

/**
 * <p>
 * 电子围栏记录表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface IElectronicFenceService extends IService<ElectronicFence> {
    Page<ElectronicFence> pageWithFilter(int current, int size, String fenceName, String fenceType, Date startTime, Date endTime);

    ElectronicFence getByIdWithCoordinates(Long id);

    boolean saveWithCoordinates(ElectronicFence fence, List<ElectronicFenceLatitude> coordinates);

    boolean updateWithCoordinates(ElectronicFence fence, List<ElectronicFenceLatitude> coordinates);

    boolean toggleStatus(Long id);

    long getAlarmCountByFenceId(Long fenceId);

    boolean deleteFence(Long id);
}
