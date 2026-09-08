package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.helmet.pojo.po.IntercomRecord;
import com.ruoyi.helmet.pojo.po.IntercomRecordRequest;
import com.ruoyi.helmet.service.IIntercomRecordService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;

import java.util.Date;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * <p>
 * 对讲记录表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/intercom/record")
@Api(tags = "对讲记录接口")
public class IntercomRecordController extends BaseController {
    @Autowired
    private IIntercomRecordService intercomRecordService;

    @Autowired
    private ISafetyHatInfoService hatInfoService;

    @Value("${melhat.demo-mode:false}")
    private boolean demoMode;

    /**
     * 分页查询对讲记录（支持条件过滤）
     */
    @GetMapping("/page")
    @ApiOperation(value = "对讲记录列表（分页）")
    public R<IPage<IntercomRecord>> getPage(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String intercomType,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date startTimeFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date startTimeTo
    ) {
        IPage<IntercomRecord> intercomRecordIPage= intercomRecordService.pageWithFilter(current, size, intercomType, startTimeFrom, startTimeTo);
        return R.ok(intercomRecordIPage);
    }

    /**
     * 根据ID获取对讲记录详情
     */
    @GetMapping("/{id}")
    @ApiOperation(value = "根据ID获取对讲记录详情")
    public R<IntercomRecord> getById(@PathVariable Integer id) {
         intercomRecordService.getById(id);
         return  R.ok();
    }

    /**
     * 结束对讲
     */
    @PutMapping("/end")
    @ApiOperation(value = "结束对讲")
    public R end(@RequestBody IntercomRecord record) throws Exception {
         intercomRecordService.endIntercom(record.getId());
         return  R.ok();
    }


    /**
     * 结束对讲
     */
    @PutMapping("/agoraEnd")
    @ApiOperation(value = "声网结束对讲")
    public R agoraEnd(@RequestBody String channel) throws Exception {
        ResponseVO responseVO = intercomRecordService.endIntercom(channel);
        return  R.ok(responseVO);
    }

    /**
     * 逻辑删除对讲记录
     */
    @DeleteMapping("/{id}")
    @ApiOperation(value = "逻辑删除对讲记录")
    public R delete(@PathVariable Long id) {
         intercomRecordService.deleteById(id);
         return  R.ok();
    }

    /**
     * 快捷创建单呼
     */
    @PostMapping("/single-call")
    @ApiOperation(value = "创建单呼")
    public R<Object> createSingleCall(@RequestBody IntercomRecordRequest request) throws Exception {
        IntercomRecord record = new IntercomRecord();
        record.setIntercomType("01");
        if(StringUtils.isBlank(request.getHatNumber())){
            throw new ServiceException("安全帽编号不能是空");
        }
        if(StringUtils.isBlank(request.getParticipant())){
            throw new ServiceException("呼叫人员不能是空");
        }
        if (demoMode) {
            return createDemoIntercom(record, request, "single");
        }
        ResponseVO responseVO = intercomRecordService.createIntercom(record, request);
        return  R.ok(responseVO.getData());
    }

    /**
     * 快捷创建群呼
     */
    @PostMapping("/group-call")
    @ApiOperation(value = "创建群呼")
    public R<Object> createGroupCall(@RequestBody IntercomRecordRequest request) throws Exception {
        IntercomRecord record = new IntercomRecord();
        record.setIntercomType("02");
        if(StringUtils.isBlank(request.getHatNumber())){
            throw new ServiceException("安全帽编号不能是空");
        }
        if(StringUtils.isBlank(request.getParticipant())){
            throw new ServiceException("呼叫人员不能是空");
        }
        if (demoMode) {
            return createDemoIntercom(record, request, "group");
        }
        ResponseVO responseVO = intercomRecordService.createIntercom(record,request);
         return R.ok(responseVO.getData());
    }

    /**
     * 快捷创建组呼
     */
    @PostMapping("/team-call")
    @ApiOperation(value = "创建组呼")
    public R<Object> createTeamCall(@RequestBody IntercomRecordRequest request) throws Exception {
        IntercomRecord record = new IntercomRecord();
        record.setIntercomType("03");
        if(StringUtils.isBlank(request.getGroupId())){
            throw new ServiceException("组呼编号不能是空");
        }
        if (demoMode) {
            return createDemoIntercom(record, request, "team");
        }
        ResponseVO responseVO =intercomRecordService.createIntercom(record,request);
        return  R.ok(responseVO.getData());
    }

    /**
     * 演示模式只保存本地记录，不进入 service 的 RTC/Headband 调用分支。
     * intercomType 仍使用页面已有的 01/02/03，mode 提供计划中的 single/group/team 术语。
     */
    private R<Object> createDemoIntercom(IntercomRecord record, IntercomRecordRequest request, String mode) {
        Date now = new Date();
        record.setDelFlag("0");
        record.setCreateTime(now);
        record.setStartTime(now);
        // 演示记录统一标识为 demo；实际登录操作人保留在 updateBy 便于追溯。
        record.setCreateBy("demo");
        record.setUpdateBy(currentOperator());
        List<SafetyHatInfo> hats = resolveDemoHats(request, "03".equals(record.getIntercomType()));
        record.setHatNumber(hats.stream().map(SafetyHatInfo::getHatNumber).collect(Collectors.joining(",")));
        record.setParticipant(hats.stream().map(SafetyHatInfo::getBindUserName).collect(Collectors.joining(",")));
        record.setRecipientCount(hats.size());
        if (!intercomRecordService.save(record)) {
            throw new ServiceException("本地模拟通话记录保存失败");
        }
        return R.ok(demoPayload(record, mode), "本地模拟通话已记录，未发起外部 RTC 调用");
    }

    private Map<String, Object> demoPayload(IntercomRecord record, String mode) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("id", record.getId());
        data.put("demo", true);
        data.put("mode", mode);
        data.put("intercomType", record.getIntercomType());
        data.put("hatNumber", record.getHatNumber());
        data.put("participant", record.getParticipant());
        data.put("recipientCount", record.getRecipientCount());
        data.put("startTime", record.getStartTime());
        data.put("createBy", record.getCreateBy());
        data.put("updateBy", record.getUpdateBy());
        data.put("operator", record.getUpdateBy());
        data.put("message", "本地模拟通话");
        return data;
    }

    private List<SafetyHatInfo> resolveDemoHats(IntercomRecordRequest request, boolean team) {
        List<SafetyHatInfo> hats;
        if (team) {
            Long groupId = parseGroupId(request.getGroupId());
            hats = hatInfoService.list(new LambdaQueryWrapper<SafetyHatInfo>()
                    .eq(SafetyHatInfo::getBindGroupId, groupId)
                    .eq(SafetyHatInfo::getCreateBy, "demo")
                    .eq(SafetyHatInfo::getDelFlag, "0")
                    .likeRight(SafetyHatInfo::getHatNumber, "MH-DEMO-"));
            if (hats == null || hats.isEmpty()) {
                throw new ServiceException("该组下没有演示安全帽");
            }
            hats = new ArrayList<>(hats);
            hats.sort(java.util.Comparator.comparing(SafetyHatInfo::getHatNumber));
        } else {
            List<String> requestedNumbers = parseHatNumbers(request.getHatNumber());
            List<SafetyHatInfo> found = hatInfoService.list(new LambdaQueryWrapper<SafetyHatInfo>()
                    .in(SafetyHatInfo::getHatNumber, requestedNumbers)
                    .eq(SafetyHatInfo::getCreateBy, "demo")
                    .eq(SafetyHatInfo::getDelFlag, "0")
                    .likeRight(SafetyHatInfo::getHatNumber, "MH-DEMO-"));
            Map<String, SafetyHatInfo> byNumber = new HashMap<>();
            if (found != null) {
                for (SafetyHatInfo hat : found) {
                    if (hat != null && StringUtils.isNotBlank(hat.getHatNumber())) {
                        byNumber.put(hat.getHatNumber(), hat);
                    }
                }
            }
            hats = requestedNumbers.stream().map(byNumber::get).collect(Collectors.toList());
            if (hats.contains(null)) {
                throw new ServiceException("存在不存在或非演示安全帽");
            }
        }
        if (hats.stream().anyMatch(hat -> StringUtils.isBlank(hat.getBindUserName()))) {
            throw new ServiceException("演示安全帽未绑定人员");
        }
        return hats;
    }

    private List<String> parseHatNumbers(String value) {
        if (StringUtils.isBlank(value)) {
            throw new ServiceException("安全帽编号不能是空");
        }
        List<String> values = Arrays.stream(value.split(",", -1)).map(String::trim).collect(Collectors.toList());
        if (values.stream().anyMatch(StringUtils::isBlank) || new LinkedHashSet<>(values).size() != values.size()) {
            throw new ServiceException("安全帽编号不能包含空项或重复项");
        }
        return values;
    }

    private Long parseGroupId(String value) {
        try {
            return Long.valueOf(value);
        } catch (NumberFormatException e) {
            throw new ServiceException("组呼编号不合法");
        }
    }

    private String currentOperator() {
        Authentication authentication = SecurityUtils.getAuthentication();
        LoginUser loginUser = authentication != null && authentication.getPrincipal() instanceof LoginUser
                ? (LoginUser) authentication.getPrincipal() : null;
        return loginUser != null && StringUtils.isNotBlank(loginUser.getUsername()) ? loginUser.getUsername() : "demo";
    }
}
