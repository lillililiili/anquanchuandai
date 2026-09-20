package com.ruoyi.wear.device.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.device.domain.WearDevice;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface WearDeviceMapper extends BaseMapper<WearDevice>
{
    @Select("SELECT id, manufacturer_code, sn, model_id, site_id, asset_status, current_assignment_id, "
            + "external_code, online, battery, last_reported_at, last_telemetry_at, version, del_flag, create_by, create_time, "
            + "update_by, update_time FROM wear_device WHERE id = #{id} AND del_flag = '0' FOR UPDATE")
    WearDevice selectByIdForUpdate(@Param("id") Long id);

    // Explicit console state commands are serialized by the service's row lock.
    // They use backend receipt time rather than replay/device event-time ordering.
    @org.apache.ibatis.annotations.Update("UPDATE wear_device SET last_reported_at = #{receivedAt}, last_telemetry_at = #{receivedAt}, "
            + "online = #{online}, version = version + 1, update_time = NOW() WHERE id = #{id} AND del_flag = '0'")
    int applySimulationState(@Param("id") Long id, @Param("receivedAt") java.util.Date receivedAt,
            @Param("online") String online);

    @org.apache.ibatis.annotations.Update("UPDATE wear_device SET last_reported_at = #{occurredAt}, last_telemetry_at = #{occurredAt}, "
            + "online = #{online}, battery = COALESCE(#{battery}, battery), version = version + 1, update_time = NOW() "
            + "WHERE id = #{id} AND del_flag = '0' AND (last_telemetry_at IS NULL OR last_telemetry_at <= #{occurredAt})")
    int applyTelemetryIfNewer(@Param("id") Long id, @Param("occurredAt") java.util.Date occurredAt,
            @Param("online") String online, @Param("battery") java.math.BigDecimal battery);
}
