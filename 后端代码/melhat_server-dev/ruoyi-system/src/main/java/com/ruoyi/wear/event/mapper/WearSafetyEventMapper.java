package com.ruoyi.wear.event.mapper;

import java.util.Date;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.event.domain.WearSafetyEvent;

@Mapper
public interface WearSafetyEventMapper extends BaseMapper<WearSafetyEvent>
{
    @Update("UPDATE wear_safety_event SET status = 'claimed', claimant_user_id = #{claimantUserId}, "
            + "version = version + 1, update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND status = 'open' AND version = #{version}")
    int claimIfOpen(@Param("id") Long id, @Param("claimantUserId") Long claimantUserId,
            @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET status = #{toStatus}, version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status IN ('open', 'claimed', 'handling')")
    int handleIfActive(@Param("id") Long id, @Param("toStatus") String toStatus,
            @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET claimant_user_id = #{claimantUserId}, version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status IN ('claimed', 'handling')")
    int transferIfActive(@Param("id") Long id, @Param("claimantUserId") Long claimantUserId,
              @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET claimant_user_id=#{toUserId}, version=version+1, update_by=#{actor}, update_time=NOW() "
            + "WHERE id=#{id} AND site_id=#{siteId} AND claimant_user_id=#{fromUserId} AND version=#{version} AND status<>'closed'")
    int transferDuty(@Param("id") Long id, @Param("siteId") Long siteId, @Param("fromUserId") Long fromUserId,
                     @Param("toUserId") Long toUserId, @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET status = 'closed', version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status = #{fromStatus}")
    int closeIfStatus(@Param("id") Long id, @Param("fromStatus") String fromStatus,
            @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET status = 'open', claimant_user_id = NULL, version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status = 'closed'")
    int reopenIfClosed(@Param("id") Long id, @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET status='pending_review', version=version+1, update_by=#{actor}, update_time=NOW() "
            + "WHERE id=#{id} AND version=#{version} AND status='closed' AND source='manual_sos' AND event_type='sos'")
    int reopenManualSos(@Param("id") Long id, @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_safety_event SET repeat_count = repeat_count + 1, update_time = NOW() WHERE id = #{id}")
    int bumpRepeat(@Param("id") Long id);

    @Update("UPDATE wear_safety_event SET escalated = 1, version = version + 1, update_time = NOW() "
            + "WHERE id = #{id} AND status = 'open' AND escalated = 0")
    int markEscalated(@Param("id") Long id);

    @Select("SELECT * FROM wear_safety_event WHERE event_type = 'sos' AND status = 'open' AND escalated = 0 "
            + "AND occurred_at < #{before}")
    List<WearSafetyEvent> selectDueSos(@Param("before") Date before);

    @Update("UPDATE wear_safety_event SET task_id = #{taskId}, task_match = #{match} WHERE id = #{id}")
    int applyMatch(@Param("id") Long id, @Param("taskId") Long taskId, @Param("match") String match);

    @Update("UPDATE wear_safety_event SET task_id = #{taskId}, task_match = #{match}, version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() WHERE id = #{id} AND version = #{version}")
    int assignTask(@Param("id") Long id, @Param("taskId") Long taskId, @Param("match") String match,
            @Param("version") Integer version, @Param("actor") String actor);
}
