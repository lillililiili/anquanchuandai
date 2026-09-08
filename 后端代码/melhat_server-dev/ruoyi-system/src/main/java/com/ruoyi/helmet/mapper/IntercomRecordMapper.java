package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.IntercomRecord;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Map;

/**
 * 对讲记录表 Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface IntercomRecordMapper extends BaseMapper<IntercomRecord> {

    /**
     * 统计对讲记录数量
     * @return 对讲记录总数
     */
    Integer countIntercomRecords();
    
    /**
     * 统计今日对讲记录数量
     * @return 今日对讲记录数量
     */
    Integer countTodayIntercomRecords();
    
    /**
     * 统计对讲类型数量（按类型分组）
     * @return Map<对讲类型，数量>
     */
    List<Map<String, Object>> countIntercomByType();

}
