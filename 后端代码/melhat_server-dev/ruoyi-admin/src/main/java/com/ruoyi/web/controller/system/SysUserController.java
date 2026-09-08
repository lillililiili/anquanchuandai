package com.ruoyi.web.controller.system;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;
import javax.servlet.http.HttpServletResponse;

import com.alibaba.fastjson2.JSONObject;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.core.toolkit.IdWorker;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.config.RuoYiConfig;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.core.domain.entity.AssistDO;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.core.page.PageDomain;
import com.ruoyi.common.core.page.TableSupport;
import com.ruoyi.common.utils.file.FileUploadUtils;
import com.ruoyi.common.utils.file.MimeTypeUtils;
import com.ruoyi.framework.web.service.TokenService;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.system.mapper.SysUserMapper;
import com.ruoyi.system.service.*;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.ArrayUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import com.ruoyi.common.annotation.Log;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.AjaxResult;
import com.ruoyi.common.core.domain.entity.SysDept;
import com.ruoyi.common.core.domain.entity.SysRole;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.page.TableDataInfo;
import com.ruoyi.common.enums.BusinessType;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.common.utils.poi.ExcelUtil;

/**
 * 用户信息
 *
 * @author ruoyi
 */
@RestController
@RequestMapping("/system/user")
@Slf4j
@Api(tags = "用户信息（ruoyi)")
public class SysUserController extends BaseController {
    @Autowired
    private ISysUserService userService;

    @Autowired
    private ISysRoleService roleService;

    @Autowired
    private ISysDeptService deptService;

    @Autowired
    private ISysPostService postService;


    @Autowired
    private SysUserMapper sysUserMapper;

    @Autowired
    private TokenService tokenService;


    /**
     * 获取用户列表
     */
    @PreAuthorize("@ss.hasPermi('system:user:list')")
    @GetMapping("/list")
    @ApiOperation(value = "获取用户列表")
    public TableDataInfo list(SysUser user) {
        startPage();
        List<SysUser> list = userService.selectUserList(user);
        return getDataTable(list);
    }

    @GetMapping("/listAssist")
    @ApiOperation(value = "获取用户列表 app")
    public TableDataInfo listAssist(SysUser user) {
        startPage();
        List<SysUser> list = userService.selectUserListApp(user);
        return getDataTable(list);
    }

    @GetMapping("/app/user/list")
    @ApiOperation(value = "获取用户列表 app 专用")
    public R<IPage<SysUser>> listAappUser(SysUser user) {
        startPage();
        PageDomain pageDomain = TableSupport.buildPageRequest();
        List<SysUser> list = userService.selectUserListApp(user);
        TableDataInfo tableDataInfo = getDataTable(list);
        IPage<SysUser> page = new Page<>(pageDomain.getPageNum(), pageDomain.getPageSize(), tableDataInfo.getTotal());
        page.setRecords(list);
        return R.ok(page);
    }

    @PostMapping("/goAssist")
    public AjaxResult goAssist(@RequestBody AssistDO assist) {
        userService.sendAssist(assist);
        return AjaxResult.success();
    }


    /**
     * 获取场站外包人员数量
     */
    @PreAuthorize("@ss.hasPermi('system:user:query')")
    @GetMapping("/countByUserType")
    public Map<String, Integer> countByUserTypeAndStatus() {
        Map<String, Integer> result = new HashMap<>();
        result.put("online", null);
        result.put("outsourcing", sysUserMapper.countOutsourcingUsers());
        result.put("station", sysUserMapper.countStationUsers());
        return result;
    }

    @Log(title = "用户管理", businessType = BusinessType.EXPORT)
    @PreAuthorize("@ss.hasPermi('system:user:export')")
    @PostMapping("/export")
    public void export(HttpServletResponse response, SysUser user) {
        List<SysUser> list = userService.selectUserList(user);
        ExcelUtil<SysUser> util = new ExcelUtil<SysUser>(SysUser.class);
        util.exportExcel(response, list, "用户数据");
    }

    @Log(title = "用户管理", businessType = BusinessType.IMPORT)
    @PreAuthorize("@ss.hasPermi('system:user:import')")
    @PostMapping("/importData")
    public AjaxResult importData(MultipartFile file, boolean updateSupport) throws Exception {
        ExcelUtil<SysUser> util = new ExcelUtil<SysUser>(SysUser.class);
        List<SysUser> userList = util.importExcel(file.getInputStream());
        String operName = getUsername();
        String message = userService.importUser(userList, updateSupport, operName);
        return success(message);
    }

    @PostMapping("/importTemplate")
    public void importTemplate(HttpServletResponse response) {
        ExcelUtil<SysUser> util = new ExcelUtil<SysUser>(SysUser.class);
        util.importTemplateExcel(response, "用户数据");
    }

    /**
     * 根据用户编号获取详细信息
     */
    @PreAuthorize("@ss.hasPermi('system:user:query')")
    @GetMapping(value = {"/", "/{userId}"})
    @ApiOperation(value = "根据用户编号获取详细信息")
    public AjaxResult getInfo(@PathVariable(value = "userId", required = false) Long userId) {
        userService.checkUserDataScope(userId);
        AjaxResult ajax = AjaxResult.success();
        List<SysRole> roles = roleService.selectRoleAll();
        ajax.put("roles", SysUser.isAdmin(userId) ? roles : roles.stream().filter(r -> !r.isAdmin()).collect(Collectors.toList()));
        ajax.put("posts", postService.selectPostAll());
        if (StringUtils.isNotNull(userId)) {
            SysUser sysUser = userService.selectUserById(userId);
            ajax.put(AjaxResult.DATA_TAG, sysUser);
            ajax.put("postIds", postService.selectPostListByUserId(userId));
            ajax.put("roleIds", sysUser.getRoles().stream().map(SysRole::getRoleId).collect(Collectors.toList()));
        }
        return ajax;
    }

    /**
     * 新增用户
     */
    @PreAuthorize("@ss.hasPermi('system:user:add')")
    @Log(title = "用户管理", businessType = BusinessType.INSERT)
    @PostMapping
    public AjaxResult add(@Validated @RequestBody SysUser user) {
        if (!userService.checkUserNameUnique(user)) {
            return error("新增用户'" + user.getUserName() + "'失败，登录账号已存在");
        } else if (StringUtils.isNotEmpty(user.getPhonenumber()) && !userService.checkPhoneUnique(user)) {
            return error("新增用户'" + user.getUserName() + "'失败，手机号码已存在");
        } else if (StringUtils.isNotEmpty(user.getEmail()) && !userService.checkEmailUnique(user)) {
            return error("新增用户'" + user.getUserName() + "'失败，邮箱账号已存在");
        }
        //校验密码
        String passwordValidationResult = validatePasswordComplexity(user.getPassword(), user.getUserName());
        if (passwordValidationResult != null) {
            return error("新增用户'" + user.getUserName() + "'失败，" + passwordValidationResult);
        }

        if ("00".equals(user.getUserType())) {

        } else {
            //场站|外包人员 默认部门是  创建人所在的部门
            if (user.getDeptId() == null && !"admin".equals(SecurityUtils.getLoginUser().getUsername())) {
                user.setDeptId(SecurityUtils.getLoginUser().getDeptId());
            }
        }

        user.setCreateBy(getUsername());
        user.setPassword(SecurityUtils.encryptPassword(user.getPassword()));
        return toAjax(userService.insertUser(user));
    }

    /**
     * 密码规则:
     * 1.密码最少长度为8位
     * 2.密码应至少包含数字、大小写字母及特殊字符中的三种;
     * 3.禁止使用一个相同的数字或字符作为密码，如bbb、b34bb、2b3b4b等
     * 4.禁止使用三个连续升序或降序的数字或字母作为密码，如123456、abc、def等
     * 5.禁止使用用户账户号作为密码。
     */
    public String validatePasswordComplexity(String password, String username) {
        // 规则1: 密码最少长度为8位
        if (password == null || password.length() < 8) {
            return "密码长度至少为8位。";
        }

        int validTypes = 0;
        // 检查是否包含数字
        if (password.matches(".*\\d.*")) {
            validTypes++;
        }

        // 检查是否包含小写字母
        if (password.matches(".*[a-z].*")) {
            validTypes++;
        }

        // 检查是否包含大写字母
        if (password.matches(".*[A-Z].*")) {
            validTypes++;
        }

        // 检查是否包含特殊字符
        if (password.matches(".*[!@#$%^&*+=?-].*")) {
            validTypes++;
        }

        // 规则2: 密码应至少包含数字、大小写字母及特殊字符中的三种
        if (validTypes < 3) {
            return "密码应至少包含数字、大小写字母及特殊字符中的三种。";
        }

        // 规则3: 禁止使用相同的数字或字符作为密码超过两次
        if (!isUniqueCharacterRepeatAllowed(password)) {
            return "禁止使用相同的数字或字符作为密码超过两次。";
        }

        // 规则4: 禁止使用三个连续升序或降序的数字或字母作为密码
        if (hasSequentialChars(password)) {
            return "禁止使用三个连续升序或降序的数字或字母作为密码。";
        }

        // 规则5: 禁止使用用户账户号作为密码
        if (password.equals(username)) {
            return "禁止使用用户账户号作为密码。";
        }

        // 如果所有校验都通过，则返回null表示密码有效
        return null;
    }

    /**
     * 实现连续字符的校验逻辑
     */
    private boolean hasSequentialChars(String password) {
        // 实现连续字符的校验逻辑
        char[] chars = password.toCharArray();
        for (int i = 0; i < chars.length - 2; i++) {
            if (chars[i] + 1 == chars[i + 1] && chars[i + 1] + 1 == chars[i + 2] ||
                    chars[i] - 1 == chars[i + 1] && chars[i + 1] - 1 == chars[i + 2]) {
                return true;
            }
        }
        return false;
    }

    private boolean isUniqueCharacterRepeatAllowed(String password) {
        Map<Character, Integer> charCountMap = new HashMap<>();
        for (char ch : password.toCharArray()) {
            charCountMap.put(ch, charCountMap.getOrDefault(ch, 0) + 1);
            if (charCountMap.get(ch) > 2) {
                return false;
            }
        }
        return true;
    }

    /**
     * 修改用户
     */
    @PreAuthorize("@ss.hasPermi('system:user:edit')")
    @Log(title = "用户管理", businessType = BusinessType.UPDATE)
    @PutMapping
    public AjaxResult edit(@Validated @RequestBody SysUser user) {
        userService.checkUserAllowed(user);
        userService.checkUserDataScope(user.getUserId());
        if (!userService.checkUserNameUnique(user)) {
            return error("修改用户'" + user.getUserName() + "'失败，登录账号已存在");
        } else if (StringUtils.isNotEmpty(user.getPhonenumber()) && !userService.checkPhoneUnique(user)) {
            return error("修改用户'" + user.getUserName() + "'失败，手机号码已存在");
        } else if (StringUtils.isNotEmpty(user.getEmail()) && !userService.checkEmailUnique(user)) {
            return error("修改用户'" + user.getUserName() + "'失败，邮箱账号已存在");
        }
        user.setUpdateBy(getUsername());
        return toAjax(userService.updateUser(user));
    }

    /**
     * 删除用户
     */
    @PreAuthorize("@ss.hasPermi('system:user:remove')")
    @Log(title = "用户管理", businessType = BusinessType.DELETE)
    @DeleteMapping("/{userIds}")
    public AjaxResult remove(@PathVariable Long[] userIds) {
        if (ArrayUtils.contains(userIds, getUserId())) {
            return error("当前用户不能删除");
        }
        return toAjax(userService.deleteUserByIds(userIds));
    }

    /**
     * 重置密码
     */
    @PreAuthorize("@ss.hasPermi('system:user:resetPwd')")
    @Log(title = "用户管理", businessType = BusinessType.UPDATE)
    @PutMapping("/resetPwd")
    public AjaxResult resetPwd(@RequestBody SysUser user) {
        //校验密码
        String passwordValidationResult = validatePasswordComplexity(user.getPassword(), "此账号");
        if (passwordValidationResult != null) {
            return error("重置密码失败，" + passwordValidationResult);
        }
        userService.checkUserAllowed(user);
        userService.checkUserDataScope(user.getUserId());
        user.setPassword(SecurityUtils.encryptPassword(user.getPassword()));
        user.setUpdateBy(getUsername());
        return toAjax(userService.resetPwd(user));
    }

    /**
     * 状态修改
     */
    @PreAuthorize("@ss.hasPermi('system:user:edit')")
    @Log(title = "用户管理", businessType = BusinessType.UPDATE)
    @PutMapping("/changeStatus")
    public AjaxResult changeStatus(@RequestBody SysUser user) {
        userService.checkUserAllowed(user);
        userService.checkUserDataScope(user.getUserId());
        user.setUpdateBy(getUsername());
        return toAjax(userService.updateUserStatus(user));
    }

    /**
     * 根据用户编号获取授权角色
     */
    @PreAuthorize("@ss.hasPermi('system:user:query')")
    @GetMapping("/authRole/{userId}")
    @ApiOperation(value = "根据用户编号获取授权角色")
    public AjaxResult authRole(@PathVariable("userId") Long userId) {
        AjaxResult ajax = AjaxResult.success();
        SysUser user = userService.selectUserById(userId);
        List<SysRole> roles = roleService.selectRolesByUserId(userId);
        ajax.put("user", user);
        ajax.put("roles", SysUser.isAdmin(userId) ? roles : roles.stream().filter(r -> !r.isAdmin()).collect(Collectors.toList()));
        return ajax;
    }

    /**
     * 用户授权角色
     */
    @PreAuthorize("@ss.hasPermi('system:user:edit')")
    @Log(title = "用户管理", businessType = BusinessType.GRANT)
    @PutMapping("/authRole")
    @ApiOperation(value = "用户授权角色")
    public AjaxResult insertAuthRole(Long userId, Long[] roleIds) {
        userService.checkUserDataScope(userId);
        userService.insertUserAuth(userId, roleIds);
        return success();
    }

    /**
     * 获取部门树列表
     */
    @GetMapping("/deptTree")
    @ApiOperation(value = "获取部门树列表")
    public AjaxResult deptTree(SysDept dept) {
        return success(deptService.selectDeptTreeList(dept));
    }


    /**
     * 电子签名
     */
    @Log(title = "电子签名", businessType = BusinessType.UPDATE)
    @PostMapping("/signature")
    public AjaxResult signature(@RequestParam("signaturefile") MultipartFile file) throws Exception {
        if (!file.isEmpty()) {
            LoginUser loginUser = getLoginUser();
            String electronicSignature = FileUploadUtils.upload(RuoYiConfig.getUploadPath(), file, MimeTypeUtils.IMAGE_EXTENSION);
            if (userService.updateUserSignature(loginUser.getUsername(), electronicSignature)) {
                AjaxResult ajax = AjaxResult.success();
                ajax.put("imgUrl", electronicSignature);
                // 更新缓存电子签名
                loginUser.getUser().setElectronicSignature(electronicSignature);
                tokenService.setLoginUser(loginUser);
                return ajax;
            }
        }
        return error("上传电子签名异常，请联系管理员");
    }


}

