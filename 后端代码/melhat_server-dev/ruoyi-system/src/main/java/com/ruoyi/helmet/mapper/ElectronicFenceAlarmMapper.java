package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.ElectronicFenceAlarm;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Date;
import java.util.List;

@Mapper
public interface ElectronicFenceAlarmMapper extends BaseMapper<ElectronicFenceAlarm> {

    /**
     * 查询报警记录（关联围栏名称）
     */
    /**
     * 查询报警记录（关联围栏名称）
     */
    @Select("<script>" +
            "SELECT efa.*, ef.fence_name " +
            "FROM electronic_fence_alarm efa " +
            "LEFT JOIN electronic_fence ef ON efa.fence_id = ef.id " +
            "WHERE efa.del_flag = '0' " +
            "<if test='alarmType != null and alarmType != \"\" and alarmType != \"全部\"'> AND efa.alarm_type = #{alarmType} </if>" +
            "<if test='userName != null and userName != \"\"'> AND efa.user_name LIKE CONCAT('%', #{userName}, '%') </if>" +
            "<if test='startTime != null'> AND efa.alarm_start_time &gt;= #{startTime} </if>" +
            "<if test='endTime != null'> AND efa.alarm_start_time &lt;= #{endTime} </if>" +
            "ORDER BY efa.alarm_start_time DESC" +
            "</script>")
    List<ElectronicFenceAlarm> selectWithFenceName(
            @Param("alarmType") String alarmType,
            @Param("userName") String userName,
            @Param("startTime") Date startTime,
            @Param("endTime") Date endTime
    );
}
