package com.ruoyi.helmet.service.impl;

import com.alibaba.fastjson2.JSON;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.utils.DateUtils;
import com.ruoyi.common.utils.JacksonUtil;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.headband.pojo.param.GroupCallParam;
import com.ruoyi.headband.pojo.param.SingCallParam;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.mapper.FileRecordMapper;
import com.ruoyi.helmet.mapper.IntercomRecordMapper;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.pojo.po.IntercomRecord;
import com.ruoyi.helmet.pojo.po.IntercomRecordRequest;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.service.IIntercomRecordService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;

/**
 * <p>
 * 对讲记录表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
@Slf4j
public class IntercomRecordServiceImpl extends ServiceImpl<IntercomRecordMapper, IntercomRecord> implements IIntercomRecordService {

    @Autowired
    private IntercomRecordMapper intercomRecordMapper;
    @Autowired
    private ISafetyHatInfoService hatInfoService;
    @Autowired
    private HeadbandService headbandService;

    @Override
    public IPage<IntercomRecord> pageWithFilter(int current, int size, String intercomType, Date startTimeFrom, Date startTimeTo) {
        LambdaQueryWrapper<IntercomRecord> wrapper = new LambdaQueryWrapper<>();

        if (intercomType != null && !intercomType.isEmpty() && !"全部".equals(intercomType)) {
            wrapper.eq(IntercomRecord::getIntercomType, intercomType);
        }
        if (startTimeFrom != null) {
            wrapper.ge(IntercomRecord::getStartTime, startTimeFrom);
        }
        if (startTimeTo != null) {
            wrapper.le(IntercomRecord::getStartTime, startTimeTo);
        }

        // 只查未删除的记录
        wrapper.eq(IntercomRecord::getDelFlag, "0");

        return this.page(new Page<>(current, size), wrapper);
    }

    @Override
    public ResponseVO createIntercom(IntercomRecord record, IntercomRecordRequest request) throws Exception {
        Date now = new Date();
        record.setDelFlag("0");
        record.setCreateTime(now);
        record.setStartTime(now);
        record.setCreateBy(SecurityUtils.getUsername());
        List<String> hatNoList = new ArrayList<>();
        if("01".equals(record.getIntercomType())){
            record.setHatNumber(record.getHatNumber());
            record.setParticipant(request.getParticipant());
            record.setRecipientCount(1);
            hatNoList = Arrays.asList(request.getHatNumber().split(","));
        }else if("02".equals(record.getIntercomType())){
            record.setHatNumber(request.getHatNumber());
            record.setParticipant(request.getParticipant());
            String[] hatNoAry = request.getHatNumber().split(",");
            record.setRecipientCount(hatNoAry.length);
            hatNoList = Arrays.asList(hatNoAry);
        }else if("03".equals(record.getIntercomType())){
            String groupId = request.getGroupId();
            List<SafetyHatInfo> hats = hatInfoService.getHatNumbersByGroupNumber(Long.valueOf(groupId));
            String numbers = hats.stream().map(x -> x.getHatNumber()).collect(Collectors.joining(","));
            String users = hats.stream().map(x -> x.getBindUserName()).collect(Collectors.joining(","));
            record.setHatNumber(numbers);
            record.setParticipant(users);
            record.setRecipientCount(hats.size());
            hatNoList = hats.stream().map(x -> x.getHatNumber()).collect(Collectors.toList());
        }
        boolean save = this.save(record);
        
        // 创建一个新的可变列表，因为 Arrays.asList() 返回的是固定大小列表
        List<String> allNumbers = new ArrayList<>(hatNoList);
        //呼叫帽子

       /* if("01".equals(record.getIntercomType())){
            SingCallParam param = new SingCallParam(record.getHatNumber(),request.isEnableRecodring());
            headbandService.singleCall(param);
        }else{
            GroupCallParam param = new GroupCallParam(mutableHatNoList,request.isEnableRecodring());
            headbandService.groupCall(param);
        }*/

        Map<String, Object> param = new HashMap<>();
        param.put("helmetSnList", allNumbers);

        ResponseVO responseVO = headbandService.agoraToken(param);

        return responseVO;
    }

    @Override
    public ResponseVO endIntercom(String channelName) throws Exception {
        ResponseVO responseVO = headbandService.agoraEnd(channelName);
        return responseVO;
    }

    @Override
    public boolean endIntercom(Long id) throws Exception {
        IntercomRecord record = this.getById(id);
        if (record == null ) {
            log.error("呼叫记录不存在，id={}",id);
            return false; // 不存在
        }
        Date now = new Date();
        record.setEndTime(now);
        int duration = DateUtils.differentSecondsByMillisecond(record.getStartTime(),now);
        record.setDuration(String.valueOf(duration));
        record.setUpdateTime(now);
        boolean b = this.updateById(record);

        //结束呼叫
        headbandService.endCall(record.getHatNumber());
        return b;
    }

    @Override
    public IntercomRecord getById(Long id) {
        return intercomRecordMapper.selectById(id);
    }

    @Override
    public boolean deleteById(Long id) {
        return this.update(null,new LambdaUpdateWrapper<IntercomRecord>()
                .eq(IntercomRecord::getId, id)
                .set(IntercomRecord::getDelFlag,"2")
                .set(IntercomRecord::getUpdateTime,new Date()));
    }
}
