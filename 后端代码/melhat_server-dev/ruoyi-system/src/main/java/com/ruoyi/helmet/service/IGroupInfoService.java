package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.GroupInfo;

import java.util.List;

/**
 * <p>
 *  服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface IGroupInfoService extends IService<GroupInfo> {

    /**
     * 根据分组名称模糊查询
     */
    List<GroupInfo> searchGroupsByName(String groupName);

    /**
     * 新增分组（带默认值）
     */
    boolean addGroup(GroupInfo group);

    /**
     * 编辑分组（更新时设置更新时间/人）
     */
    boolean editGroup(GroupInfo group);

    /**
     * 逻辑删除分组
     */
    boolean deleteGroup(Long groupId);

    /**
     * 减少分组安全帽数量
     */
    void decreaseCountById(Long groupId);

    /**
     * 增加分组安全帽数量
     */
    void increaseCountById(Long groupId);
}