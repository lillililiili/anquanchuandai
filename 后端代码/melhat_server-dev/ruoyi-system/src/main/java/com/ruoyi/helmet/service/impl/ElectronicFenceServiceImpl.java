package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.helmet.mapper.ElectronicFenceAlarmMapper;
import com.ruoyi.helmet.mapper.ElectronicFenceLatitudeMapper;
import com.ruoyi.helmet.mapper.ElectronicFenceMapper;
import com.ruoyi.helmet.pojo.po.ElectronicFence;
import com.ruoyi.helmet.pojo.po.ElectronicFenceAlarm;
import com.ruoyi.helmet.pojo.po.ElectronicFenceLatitude;
import com.ruoyi.helmet.service.IElectronicFenceService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * <p>
 * 电子围栏记录表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class ElectronicFenceServiceImpl extends ServiceImpl<ElectronicFenceMapper, ElectronicFence> implements IElectronicFenceService {
    @Autowired
    private ElectronicFenceMapper fenceMapper;

    @Autowired
    private ElectronicFenceLatitudeMapper latitudeMapper;

    @Autowired
    private ElectronicFenceAlarmMapper alarmMapper;

    @Override
    public Page<ElectronicFence> pageWithFilter(int current, int size, String fenceName, String fenceType, Date startTime, Date endTime) {
        List<ElectronicFence> list = fenceMapper.selectWithAlertCount(fenceName, fenceType, startTime, endTime);
        int total = list.size();
        int fromIndex = (current - 1) * size;
        int toIndex = Math.min(fromIndex + size, total);
        List<ElectronicFence> pageList = fromIndex < total ? list.subList(fromIndex, toIndex) : new ArrayList<>();

        Page<ElectronicFence> page = new Page<>(current, size, total);
        page.setRecords(pageList);
        return page;
    }

    @Override
    public ElectronicFence getByIdWithCoordinates(Long id) {
        ElectronicFence fence = this.getById(id);
        if (fence != null) {
            List<ElectronicFenceLatitude> coords = latitudeMapper.selectByFenceId(id);
            fence.setCoordinates(coords);
        }
        return fence;
    }

    @Override
    @Transactional
    public boolean saveWithCoordinates(ElectronicFence fence, List<ElectronicFenceLatitude> coordinates) {
        fence.setCreateTime(new Date());
        fence.setDelFlag("0");
        fence.setStatus(1); // 默认启用
        this.save(fence);

        if (coordinates != null && !coordinates.isEmpty()) {
            for (ElectronicFenceLatitude coord : coordinates) {
                coord.setFenceId(fence.getId());
                coord.setCreateTime(new Date());
                coord.setDelFlag(0);
                latitudeMapper.insert(coord);
            }
        }
        return true;
    }

    @Override
    @Transactional
    public boolean updateWithCoordinates(ElectronicFence fence, List<ElectronicFenceLatitude> coordinates) {
        fence.setUpdateTime(new Date());
        this.updateById(fence);

        // 先删除旧坐标
        latitudeMapper.deleteByFenceId(fence.getId());

        // 插入新坐标
        if (coordinates != null && !coordinates.isEmpty()) {
            for (ElectronicFenceLatitude coord : coordinates) {
                coord.setFenceId(fence.getId());
                coord.setUpdateTime(new Date());
                coord.setDelFlag(0);
                latitudeMapper.insert(coord);
            }
        }
        return true;
    }

    @Override
    public boolean toggleStatus(Long id) {
        ElectronicFence fence = this.getById(id);
        if (fence == null) return false;
        fence.setStatus(fence.getStatus() == 1 ? 0 : 1);
        fence.setUpdateTime(new Date());
        return this.updateById(fence);
    }

    @Override
    public long getAlarmCountByFenceId(Long fenceId) {
        LambdaQueryWrapper<ElectronicFenceAlarm> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(ElectronicFenceAlarm::getHatId, fenceId)
                .eq(ElectronicFenceAlarm::getDelFlag, "0");
        return alarmMapper.selectCount(wrapper);
    }

    @Override
    public boolean deleteFence(Long id){
        ElectronicFence fence = this.getById(id);
        //删除坐标
        if (fence != null) {
            latitudeMapper.deleteByFenceId(fence.getId());
        }
        //删除电子围栏
        fenceMapper.deleteById(id);
        return true;
    }
}
