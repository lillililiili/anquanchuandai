package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.helmet.pojo.po.TtsRequest;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.ITtsTextSynthesisBroadcastService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
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
 * TTS文字语音合成广播记录表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/tts/broadcast")
@Api(tags = "TTS文字语音合成广播记录接口")
public class TtsTextSynthesisBroadcastController extends BaseController {
    @Autowired
    private ITtsTextSynthesisBroadcastService broadcastRecordService;

    @Autowired
    private ISafetyHatInfoService hatInfoService;

    @Value("${melhat.demo-mode:false}")
    private boolean demoMode;

    /**
     * 分页查询广播记录（支持条件过滤）
     */
    @GetMapping("/page")
    @ApiOperation(value = "分页查询广播记录")
    public R<IPage<TtsTextSynthesisBroadcast>> getPage(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String broadcastType,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date sendTimeFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date sendTimeTo
    ) {
        IPage<TtsTextSynthesisBroadcast> ttsTextSynthesisBroadcastIPage = broadcastRecordService.pageWithFilter(current, size, broadcastType, sendTimeFrom, sendTimeTo);
        return R.ok(ttsTextSynthesisBroadcastIPage);
    }

    /**
     * 根据ID获取广播记录详情
     */
    @GetMapping("/{id}")
    @ApiOperation(value = "根据ID获取广播记录详情")
    public R<TtsTextSynthesisBroadcast> getById(@PathVariable Long id) {
        TtsTextSynthesisBroadcast ttsTextSynthesisBroadcast = broadcastRecordService.getById(id);
        return R.ok(ttsTextSynthesisBroadcast);
    }

    /**
     * 逻辑删除广播记录
     */
    @DeleteMapping("/{id}")
    @ApiOperation(value = "逻辑删除广播记录")
    public R delete(@PathVariable Long id) {
        broadcastRecordService.deleteById(id);
        return R.ok();
    }

    /**
     * 快捷创建单播
     */
    @PostMapping("/single-broadcast")
    @ApiOperation(value = "创建单播")
    public R createSingleBroadcast(@RequestBody TtsRequest request) throws Exception {
        TtsTextSynthesisBroadcast record = new TtsTextSynthesisBroadcast();
        record.setBroadcastType("01");
        if(StringUtils.isBlank(request.getHatNumber())){
            throw new ServiceException("安全帽编号不能是空");
        }
        if(StringUtils.isBlank(request.getParticipant())){
            throw new ServiceException("呼叫人员不能是空");
        }
        normalizeContent(request);
        if (demoMode) {
            return createDemoBroadcast(record, request, "single");
        }
        broadcastRecordService.createSingleBroadcast(record,request);
        return R.ok();
    }

    /**
     * 快捷创建群播
     */
    @PostMapping("/group-broadcast")
    @ApiOperation(value = "创建群播")
    public R createGroupBroadcast(@RequestBody TtsRequest request) throws Exception {
        TtsTextSynthesisBroadcast record = new TtsTextSynthesisBroadcast();
        record.setBroadcastType("02");
        if(StringUtils.isBlank(request.getHatNumber())){
            throw new ServiceException("安全帽编号不能是空");
        }
        if(StringUtils.isBlank(request.getParticipant())){
            throw new ServiceException("呼叫人员不能是空");
        }
        normalizeContent(request);
        if (demoMode) {
            return createDemoBroadcast(record, request, "group");
        }
        broadcastRecordService.createBroadcast(record,request);
        return  R.ok();
    }

    /**
     * 快捷创建组播
     */
    @PostMapping("/team-broadcast")
    @ApiOperation(value = "创建组播")
    public R createTeamBroadcast(@RequestBody TtsRequest request) throws Exception {
        TtsTextSynthesisBroadcast record = new TtsTextSynthesisBroadcast();
        record.setBroadcastType("03");
        if(StringUtils.isBlank(request.getGroupId())){
            throw new ServiceException("组呼编号不能是空");
        }
        normalizeContent(request);
        if (demoMode) {
            return createDemoBroadcast(record, request, "team");
        }
        broadcastRecordService.createBroadcast(record,request);
        return R.ok();
    }

    /**
     * 演示模式只写本地广播记录，不进入 service 的 TTS/Headband 调用分支。
     * broadcastType 保持页面已有的 01/02/03，mode 返回 single/group/team 映射。
     */
    private R<Map<String, Object>> createDemoBroadcast(TtsTextSynthesisBroadcast record, TtsRequest request, String mode) {
        Date now = new Date();
        record.setDelFlag("0");
        record.setCreateTime(now);
        record.setSendTime(now);
        record.setContent(request.getContent());
        record.setOperator(currentOperator());
        // 演示记录统一标识为 demo；operator/updateBy 记录实际登录操作人。
        record.setCreateBy("demo");
        record.setUpdateBy(currentOperator());
        List<SafetyHatInfo> hats = resolveDemoHats(request, "03".equals(record.getBroadcastType()));
        record.setHatNumber(hats.stream().map(SafetyHatInfo::getHatNumber).collect(Collectors.joining(",")));
        record.setRecipient(hats.stream().map(SafetyHatInfo::getBindUserName).collect(Collectors.joining(",")));
        record.setRecipientCount(hats.size());
        if (!broadcastRecordService.save(record)) {
            throw new ServiceException("本地模拟广播记录保存失败");
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("id", record.getId());
        data.put("demo", true);
        data.put("mode", mode);
        data.put("broadcastType", record.getBroadcastType());
        data.put("hatNumber", record.getHatNumber());
        data.put("recipient", record.getRecipient());
        data.put("recipientCount", record.getRecipientCount());
        data.put("sendTime", record.getSendTime());
        data.put("createBy", record.getCreateBy());
        data.put("operator", record.getOperator());
        data.put("updateBy", record.getUpdateBy());
        data.put("message", "本地模拟广播");
        return R.ok(data, "本地模拟广播已记录，未发起外部 TTS 调用");
    }

    private void normalizeContent(TtsRequest request) {
        String content = request.getContent() == null ? null : request.getContent().trim();
        if (StringUtils.isBlank(content)) {
            throw new ServiceException("广播内容不能为空");
        }
        request.setContent(content);
    }

    private List<SafetyHatInfo> resolveDemoHats(TtsRequest request, boolean team) {
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
            throw new ServiceException("组播编号不合法");
        }
    }

    private String currentOperator() {
        Authentication authentication = SecurityUtils.getAuthentication();
        LoginUser loginUser = authentication != null && authentication.getPrincipal() instanceof LoginUser
                ? (LoginUser) authentication.getPrincipal() : null;
        return loginUser != null && StringUtils.isNotBlank(loginUser.getUsername()) ? loginUser.getUsername() : "demo";
    }
}
