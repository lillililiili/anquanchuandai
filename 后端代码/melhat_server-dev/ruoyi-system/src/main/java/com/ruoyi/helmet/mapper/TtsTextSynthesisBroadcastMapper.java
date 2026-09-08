package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Map;

/**
 * TTS 文字语音合成广播记录表 Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface TtsTextSynthesisBroadcastMapper extends BaseMapper<TtsTextSynthesisBroadcast> {

    /**
     * 统计 TTS 广播记录数量
     * @return TTS 广播记录总数
     */
    Integer countTtsBroadcastRecords();
    
    /**
     * 统计今日 TTS 广播记录数量
     * @return 今日 TTS 广播记录数量
     */
    Integer countTodayTtsBroadcastRecords();
    
    /**
     * 统计 TTS 广播类型数量（按类型分组）
     * @return Map<广播类型，数量>
     */
    List<Map<String, Object>> countTtsByType();

}
