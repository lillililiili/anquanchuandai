package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.headband.pojo.param.TtsSingleBroadcastParam;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.headband.pojo.param.TtsBroadcastParam;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.mapper.TtsTextSynthesisBroadcastMapper;
import com.ruoyi.helmet.pojo.po.TtsRequest;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;
import com.ruoyi.helmet.service.ITtsTextSynthesisBroadcastService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

/**
 * <p>
 * TTS文字语音合成广播记录表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class TtsTextSynthesisBroadcastServiceImpl extends ServiceImpl<TtsTextSynthesisBroadcastMapper, TtsTextSynthesisBroadcast> implements ITtsTextSynthesisBroadcastService {

    @Autowired
    private HeadbandService headbandService;

    @Autowired
    private ISafetyHatInfoService safetyHatInfoService;
    @Autowired
    private TtsTextSynthesisBroadcastMapper ttsTextSynthesisBroadcastMapper;

    @Override
    public IPage<TtsTextSynthesisBroadcast> pageWithFilter(int current, int size, String broadcastType, Date sendTimeFrom, Date sendTimeTo) {
        LambdaQueryWrapper<TtsTextSynthesisBroadcast> wrapper = new LambdaQueryWrapper<>();

        if (broadcastType != null && !broadcastType.isEmpty()) {
            wrapper.eq(TtsTextSynthesisBroadcast::getBroadcastType, broadcastType);
        }
        if (sendTimeFrom != null) {
            wrapper.ge(TtsTextSynthesisBroadcast::getSendTime, sendTimeFrom);
        }
        if (sendTimeTo != null) {
            wrapper.le(TtsTextSynthesisBroadcast::getSendTime, sendTimeTo);
        }

        // 只查未删除的记录
        wrapper.eq(TtsTextSynthesisBroadcast::getDelFlag, "0");
        wrapper.orderByDesc(TtsTextSynthesisBroadcast::getSendTime);

        return this.page(new Page<>(current, size), wrapper);
    }

    /**
     * tts单播
     * @param record
     * @param request
     * @return
     * @throws Exception
     */
    @Override
    public boolean createSingleBroadcast(TtsTextSynthesisBroadcast record, TtsRequest request) throws Exception {
        Date date = new Date();
        record.setDelFlag("0");
        record.setCreateTime(date);
        record.setSendTime(date); // 默认发送时间为当前时间
        record.setContent(request.getContent());
        record.setOperator(SecurityUtils.getUsername());
        if ("01".equals(record.getBroadcastType())) {
            record.setHatNumber(request.getHatNumber());
            record.setRecipient(request.getParticipant());
            record.setRecipientCount(1);
        } else {
            throw new ServiceException("不支持的广播类型: " + record.getBroadcastType());
        }
        boolean save = this.save(record);

        //广播给帽子
        List<String> helmetSnList = new ArrayList<>();
        helmetSnList.add(request.getHatNumber());

        TtsBroadcastParam param = new TtsBroadcastParam(helmetSnList, record.getContent());
        headbandService.groupBroadcast(param);

      /*  TtsSingleBroadcastParam param = new TtsSingleBroadcastParam();
        param.setTargetHelmetId(request.getHatNumber());
        param.setContent(request.getContent());
        headbandService.singleBroadcast(param);*/
        return save;
    }

    /**
     * tts群播/组播
     * @param record
     * @param request
     * @return
     * @throws Exception
     */
    @Override
    public boolean createBroadcast(TtsTextSynthesisBroadcast record, TtsRequest request) throws Exception {
        Date date = new Date();
        record.setDelFlag("0");
        record.setCreateTime(date);
        record.setSendTime(date); // 默认发送时间为当前时间
        record.setContent(request.getContent());
        record.setOperator(SecurityUtils.getUsername());

        String broadcastType = record.getBroadcastType();
        List<String> helmetSnList = new ArrayList<>();
        if ("02".equals(broadcastType)) {//群呼
            String[] snArr = request.getHatNumber().split(",");
            for (String sn : snArr) {
                String s = sn.trim();
                if (!s.isEmpty()) {
                    helmetSnList.add(s);
                }
            }
            if (helmetSnList.isEmpty()) {
                throw new ServiceException("帽子编号列表不能为空");
            }
            record.setHatNumber(request.getHatNumber());
            record.setRecipient(request.getParticipant());
        } else if ("03".equals(broadcastType)) {//组呼
            // broadcastType=03时，recipient为组编号，需要查数据库获取该组下所有帽子的编号
            String groupId = request.getGroupId();
            List<SafetyHatInfo> hatList = safetyHatInfoService.getHatNumbersByGroupNumber(Long.valueOf(groupId));
            List<String> snList = hatList.stream().map(SafetyHatInfo::getHatNumber)
                    .filter(hatNumber -> hatNumber != null && !hatNumber.trim().isEmpty())
                    .collect(Collectors.toList());
            if (snList == null || snList.isEmpty()) {
                throw new ServiceException("该组下没有相关的安全帽,请先绑定或选择其他组");
            }
            helmetSnList.addAll(snList);
            String numbers = hatList.stream().map(x -> x.getHatNumber()).collect(Collectors.joining(","));
            String users = hatList.stream().map(x -> x.getBindUserName()).collect(Collectors.joining(","));
            record.setHatNumber(numbers);
            record.setRecipient(users);
        } else {
            throw new ServiceException("不支持的广播类型: " + broadcastType);
        }
        record.setRecipientCount(helmetSnList.size());
        boolean save = this.save(record);

        //广播给帽子
        TtsBroadcastParam param = new TtsBroadcastParam(helmetSnList, record.getContent());
        headbandService.groupBroadcast(param);
        return save;
    }

    @Override
    public TtsTextSynthesisBroadcast getById(Long id) {
        return ttsTextSynthesisBroadcastMapper.selectById(id);
    }

    @Override
    public boolean deleteById(Long id) {
        return this.update(null,new LambdaUpdateWrapper<TtsTextSynthesisBroadcast>()
                .eq(TtsTextSynthesisBroadcast::getId, id)
                .set(TtsTextSynthesisBroadcast::getDelFlag,"2")
                .set(TtsTextSynthesisBroadcast::getUpdateTime,new Date()));
    }
}
