package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.mapper.GroupInfoMapper;
import com.ruoyi.helmet.pojo.po.GroupInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.IGroupInfoService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;

import java.util.Collections;
import java.util.Date;
import java.util.List;

/**
 * <p>
 * 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class GroupInfoServiceImpl extends ServiceImpl<GroupInfoMapper, GroupInfo> implements IGroupInfoService {
    @Autowired
    private ISafetyHatInfoService safetyHatInfoService;

    @Override
    public List<GroupInfo> searchGroupsByName(String groupName) {
        LambdaQueryWrapper<GroupInfo> wrapper = new LambdaQueryWrapper<>();
        if (groupName != null && !groupName.trim().isEmpty()) {
            wrapper.like(GroupInfo::getGroupName, groupName);
        }
        // 只查询未删除的数据
        wrapper.eq(GroupInfo::getDelFlag, "0");
        return this.list(wrapper);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean addGroup(GroupInfo group) {
        // 设置默认值
        group.setDelFlag("0"); // 默认未删除
        Date date = new Date();
        group.setCreateTime(date);
        group.setUpdateTime(date);
        return this.save(group);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean editGroup(GroupInfo group) {
        // 校验是否存在
        GroupInfo existing = this.getById(group.getId());
        if (existing == null || "2".equals(existing.getDelFlag())) {
            throw new ServiceException("分组不存在或已被删除");
        }
        group.setUpdateTime(new Date());
        return this.updateById(group);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean deleteGroup(Long groupId) {
        GroupInfo group = this.getById(groupId);
        if (group == null) {
            throw new ServiceException("分组不存在");
        }
        // 校验是否有安全帽关联
        List<SafetyHatInfo> hatList = safetyHatInfoService.getHatNumbersByGroupNumber(groupId);
        if (!CollectionUtils.isEmpty(hatList)) {
            throw new ServiceException("该组下有安全帽关联，请先解除绑定");
        }
        // 逻辑删除：设置 del_flag = '1'
        return this.update(null,new LambdaUpdateWrapper<GroupInfo>()
                .eq(GroupInfo::getId,groupId)
                .set(GroupInfo::getDelFlag,"1")
                .set(GroupInfo::getUpdateTime,new Date()));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void decreaseCountById(Long groupId) {
        GroupInfo group = this.getById(groupId);
        if (group != null) {
            Integer count = group.getSafetyCount();
            if (count != null && count > 0) {
                group.setSafetyCount(count - 1);
                group.setUpdateTime(new Date());
                this.updateById(group);
            }
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void increaseCountById(Long groupId) {
        GroupInfo group = this.getById(groupId);
        if (group != null) {
            Integer count = group.getSafetyCount();
            if (count == null) {
                count = 0;
            }
            group.setSafetyCount(count + 1);
            group.setUpdateTime(new Date());
            this.updateById(group);
        }
    }
}