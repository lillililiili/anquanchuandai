package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

/**
 * 安全帽定位记录表Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface SafetyHatLocationRecordMapper extends BaseMapper<SafetyHatLocationRecord> {
    /**
     * 查询指定设备在指定时间范围内的轨迹点
     * 支持多个 hatId 查询
     */
    @Select("<script>" +
            "SELECT * FROM safety_hat_location_record " +
            "WHERE del_flag = 0 " +
            "<if test='hatIds != null and !hatIds.isEmpty()'> " +
            "   AND hat_id IN <foreach item='id' collection='hatIds' open='(' separator=',' close=')'>#{id}</foreach> " +
            "</if>" +
            "<if test='startTime != null'> AND timestamp &gt;= #{startTime} </if>" +
            "<if test='endTime != null'> AND timestamp &lt;= #{endTime} </if>" +
            "ORDER BY timestamp ASC" +
            "</script>")
    List<SafetyHatLocationRecord> selectTrajectoryPoints(
            @Param("hatIds") List<Long> hatIds,
            @Param("startTime") String startTime,
            @Param("endTime") String endTime
    );

    /**
     * 查询指定设备在指定时间范围内的轨迹点
     */
    @Select("<script>" +
            "SELECT * FROM safety_hat_location_record " +
            "WHERE del_flag = 0 " +
            "<if test='hatNumber != null'> " +
            "   AND hat_number = #{hatNumber} " +
            "</if>" +
            "<if test='startTime != null'> AND timestamp &gt;= #{startTime} </if>" +
            "<if test='endTime != null'> AND timestamp &lt;= #{endTime} </if>" +
            "ORDER BY timestamp ASC" +
            "</script>")
    List<SafetyHatLocationRecord>  selectRelatedVideo(
            @Param("hatNumber") String hatNumber,
            @Param("startTime") String startTime,
            @Param("endTime") String endTime);

}