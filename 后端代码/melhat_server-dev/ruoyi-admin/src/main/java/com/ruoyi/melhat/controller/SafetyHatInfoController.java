package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.vo.SafetyHatListVO;
import com.ruoyi.helmet.vo.SafetyHatQueryVO;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * <p>
 * 安全帽信息表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/safety/info")
@Api(tags = "安全帽接口")
public class SafetyHatInfoController extends BaseController {

    @Autowired
    private ISafetyHatInfoService safetyHatService;

    /**
     * 分页查询
     */
    @GetMapping("/page")
    @ApiOperation(value = "安全帽分页列表")
    public R<Page> pageQuery(
            @ModelAttribute SafetyHatQueryVO queryVO,
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size) {

        Page<SafetyHatListVO> ipage = safetyHatService.pageQuery(queryVO, current, size);
        return R.ok(ipage);
    }

    /**
     * 获取所有列表（不分页）
     */
    @GetMapping("/list")
    @ApiOperation(value = "获取所有列表（不分页）")
    public R<List<SafetyHatListVO>> listAll() {
        List<SafetyHatListVO> safetyHatListVOS = safetyHatService.listAll();
        return R.ok(safetyHatListVOS);
    }

    /**
     * 根据ID获取详情
     */
    @GetMapping("/{id}")
    @ApiOperation(value = "根据id获取详情")
    public R<SafetyHatInfo> getById(@PathVariable Long id) {
        return R.ok(safetyHatService.getById(id));
    }


    /**
     * 根据userId获取绑定安全帽的信息
     */
    @GetMapping("/user/{userId}")
    @ApiOperation(value = "根据userId获取绑定安全帽的信息")
    public R<SafetyHatInfo> getByUserId(@PathVariable Long userId) {
        return R.ok(safetyHatService.getHatByUserId(userId));
    }

    /**
     * 新增或修改
     */
    @PostMapping("/save")
    @ApiOperation(value = "新增安全帽")
    public R save(@RequestBody SafetyHatInfo safetyHat) {
        safetyHatService.saveOrUpdate(safetyHat);
        return R.ok();
    }

    @PostMapping("/updte")
    @ApiOperation(value = "修改安全帽")
    public R update(@RequestBody SafetyHatInfo safetyHat) {
        safetyHatService.saveOrUpdate(safetyHat);
        return R.ok();
    }

    /**
     * 单个删除（逻辑删除）
     */
    @DeleteMapping("/{id}")
    @ApiOperation(value = "删除安全帽")
    public R deleteById(@PathVariable Long id) {
        safetyHatService.deleteById(id);
        return R.ok();
    }

    /**
     * 批量删除
     */
    @PostMapping("/batch-delete")
    @ApiOperation(value = "删除安全帽")
    public R batchDelete(@RequestBody List<Long> ids) {
        safetyHatService.batchDelete(ids);
        return R.ok();
    }

    /**
     * 修改状态
     */
    @PutMapping("/{id}/status")
    @ApiOperation(value = "修改状态")
    public R updateStatus(@PathVariable Long id, @RequestParam String status) {
        safetyHatService.updateStatus(id, status);
        return R.ok();
    }

    /**
     * 根据编号获取安全帽
     */
    @GetMapping("/number/{hatNumber}")
    @ApiOperation(value = "根据编号获取安全帽")
    public R<SafetyHatListVO> getByNumber(@PathVariable String hatNumber) {
        SafetyHatListVO vo = safetyHatService.getByHatNumber(hatNumber);
        return R.ok(vo);
    }
}
