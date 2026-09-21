package com.ruoyi.wear.work.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.work.domain.WearDutyHandover;

@Mapper
public interface WearDutyHandoverMapper extends BaseMapper<WearDutyHandover>
{
    @Update("UPDATE wear_duty_handover SET status='cancelled', version=version+1, update_by=#{actor}, update_time=NOW() WHERE id=#{id} AND status='pending'")
    int cancelIfPending(@Param("id") Long id, @Param("actor") String actor);
    @Update("UPDATE wear_duty_handover SET status = 'confirmed', confirmed_at = NOW(), version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND status = 'pending' AND to_user_id = #{toUserId}")
    int confirmIfPending(@Param("id") Long id, @Param("toUserId") Long toUserId, @Param("actor") String actor);
}
