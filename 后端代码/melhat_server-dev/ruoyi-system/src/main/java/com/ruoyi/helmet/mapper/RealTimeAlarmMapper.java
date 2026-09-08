package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Map;

/**
 * 实时告警表 Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface RealTimeAlarmMapper extends BaseMapper<RealTimeAlarm> {

    /**
     * 统计需要处理的告警数（未处理的告警）
     * @return 未处理告警数量
     */
    Integer countUnhandledAlarms();
    
    /**
     * 统计今日告警数量
     * @return 今日告警数量
     */
    Integer countTodayAlarms();
    
    /**
     * 统计各类告警数量（按告警类型分组）
     * @return Map<告警类型，数量>
     */
    List<Map<String, Object>> countAlarmByType();

}
