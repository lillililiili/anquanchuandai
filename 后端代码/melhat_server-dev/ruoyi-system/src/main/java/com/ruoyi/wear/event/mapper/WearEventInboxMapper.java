package com.ruoyi.wear.event.mapper;

import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.event.domain.WearEventInbox;

@Mapper
public interface WearEventInboxMapper extends BaseMapper<WearEventInbox>
{
    @Update("UPDATE wear_event_inbox SET acked = 1 WHERE user_id = #{userId} AND event_id = #{eventId}")
    int markAcked(@Param("userId") Long userId, @Param("eventId") Long eventId);

    @Insert("INSERT IGNORE INTO wear_event_inbox (user_id, event_id, acked, create_time) "
            + "VALUES (#{userId}, #{eventId}, 0, NOW())")
    int insertIgnore(@Param("userId") Long userId, @Param("eventId") Long eventId);
}
