package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.TtsRequest;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;

import java.util.Date;

/**
 * <p>
 * TTS文字语音合成广播记录表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface ITtsTextSynthesisBroadcastService extends IService<TtsTextSynthesisBroadcast> {
    /**
     * 分页查询广播记录（支持条件过滤）
     */
    IPage<TtsTextSynthesisBroadcast> pageWithFilter(
            int current,
            int size,
            String broadcastType,
            Date sendTimeFrom,
            Date sendTimeTo
    );

    boolean createSingleBroadcast(TtsTextSynthesisBroadcast record, TtsRequest request) throws Exception;

    /**
     * 创建新的广播记录
     */
    boolean createBroadcast(TtsTextSynthesisBroadcast record, TtsRequest request) throws Exception;

    /**
     * 根据ID获取广播记录
     */
    TtsTextSynthesisBroadcast getById(Long id);

    /**
     * 逻辑删除广播记录
     */
    boolean deleteById(Long id);
}
