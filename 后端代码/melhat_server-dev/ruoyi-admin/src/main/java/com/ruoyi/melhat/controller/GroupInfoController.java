package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.pojo.po.GroupInfo;
import com.ruoyi.helmet.service.IGroupInfoService;
import com.ruoyi.helmet.service.impl.GroupInfoServiceImpl;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.stereotype.Controller;

import java.util.List;

/**
 * <p>
 * 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/group/info")
@Api(tags = "分组管理接口")
public class GroupInfoController extends BaseController {

    @Autowired
    private IGroupInfoService groupInfoService;

    /**
     * 分页查询 + 条件搜索
     * GET /api/groups?pageNo=1&pageSize=10&groupName=项目A
     */
    @GetMapping
    @ApiOperation(value = "分组信息")
    public R<IPage<GroupInfo>> pageGroups(
            @RequestParam(defaultValue = "1") long current,
            @RequestParam(defaultValue = "10") long size,
            @RequestParam(required = false) String groupName) {

        Page<GroupInfo> page = new Page<>(current, size);
        LambdaQueryWrapper<GroupInfo> wrapper = new LambdaQueryWrapper<>();
        if (groupName != null && !groupName.trim().isEmpty()) {
            wrapper.like(GroupInfo::getGroupName, groupName);
        }
        wrapper.eq(GroupInfo::getDelFlag, "0"); // 只查未删除
        wrapper.orderByDesc(GroupInfo::getCreateTime); // 按创建时间倒序
        IPage<GroupInfo> iPage = groupInfoService.page(page, wrapper);
        return R.ok(iPage);
    }

    /**
     * 根据ID查询详情
     * GET /api/groups/{id}
     */
    @GetMapping("/{id}")
    @ApiOperation(value = "根据id查询详情")
    public R<GroupInfo> getGroupById(@PathVariable Long id) {
        GroupInfo group = groupInfoService.getById(id);
        if (group == null || "2".equals(group.getDelFlag())) {
            throw new ServiceException("分组不存在");
        }
        return R.ok(group);
    }

    /**
     * 新增分组
     * POST /api/groups
     * Body: { "groupName": "项目D组", "groupDesc": "负责D区域日常", "safetyCount": 50 }
     */
    @PostMapping
    @ApiOperation(value = "新增分组")
    public R addGroup(@RequestBody GroupInfo group) {
        // 前端传参可能不包含 groupId/delFlag等，由后端填充
        group.setCreateBy(getUsername());
        groupInfoService.addGroup(group);
        return R.ok();
    }

    /**
     * 编辑分组
     * PUT /api/groups
     * Body: { "groupId": 1, "groupName": "项目A组修改", "groupDesc": "新描述", "safetyCount": 70 }
     */
    @PutMapping
    @ApiOperation(value = "编辑分组")
    public R editGroup(@RequestBody GroupInfo group) {
        group.setUpdateBy(getUsername());
        groupInfoService.editGroup(group);
        return  R.ok();
    }

    /**
     * 删除分组（逻辑删除）
     * DELETE /api/groups/{id}
     */
    @DeleteMapping("/{id}")
    @ApiOperation(value = "删除分组（逻辑删除）")
    public R deleteGroup(@PathVariable Long id) {
        groupInfoService.deleteGroup(id);
        return R.ok();
    }
}
