package com.ruoyi.wear.work.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.work.domain.WearWorkTask;

@Mapper
public interface WearWorkTaskMapper extends BaseMapper<WearWorkTask>
{
    @Update("UPDATE wear_work_task SET status = #{toStatus}, actual_start = IFNULL(actual_start, NOW()), "
            + "version = version + 1, update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status IN ('ready','paused')")
    int startIfReady(@Param("id") Long id, @Param("toStatus") String toStatus,
            @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_work_task SET status = 'paused', version = version + 1, update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status = 'in_progress'")
    int pauseIfActive(@Param("id") Long id, @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_work_task SET status = 'ended', actual_end = NOW(), version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status IN ('in_progress','paused','ready')")
    int endIfActive(@Param("id") Long id, @Param("version") Integer version, @Param("actor") String actor);

    @Update("UPDATE wear_work_task SET owner_user_id = #{ownerUserId}, version = version + 1, "
            + "update_by = #{actor}, update_time = NOW() "
            + "WHERE id = #{id} AND version = #{version} AND status <> 'ended'")
    int transferOwner(@Param("id") Long id, @Param("ownerUserId") Long ownerUserId,
            @Param("version") Integer version, @Param("actor") String actor);
}
