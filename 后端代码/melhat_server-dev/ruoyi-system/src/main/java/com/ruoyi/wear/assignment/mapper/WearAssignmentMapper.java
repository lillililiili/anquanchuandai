package com.ruoyi.wear.assignment.mapper;

import java.util.Date;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface WearAssignmentMapper extends BaseMapper<WearAssignment>
{
    @Select("SELECT id, device_id, person_id, site_id, issued_at, returned_at, issued_by, returned_by, "
            + "return_reason, return_kind, version, create_by, create_time, update_by, update_time "
            + "FROM wear_assignment WHERE device_id = #{deviceId} AND issued_at <= #{at} "
            + "AND (returned_at IS NULL OR returned_at > #{at}) ORDER BY issued_at DESC LIMIT 1")
    WearAssignment findAtDeviceTime(@Param("deviceId") Long deviceId, @Param("at") Date at);
}
