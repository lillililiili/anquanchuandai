package com.ruoyi.wear.device;

import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.dto.DeviceDto;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;

/** Main-platform owned test telemetry. The lab is a writer, never the read authority. */
@Service
public class DeviceSimulationStateService
{
    @Autowired private RedisCache redis;
    @Autowired private WearDeviceMapper devices;
    @Autowired private SiteAccessService access;
    @Value("${melhat.call-lab.enabled:false}") private boolean enabled;
    private String key(Long id) { return "wear:simulation:device:" + id; }

    @Transactional
    public Map<String, Object> report(Long id, Map<String, Object> body)
    {
        access.assertCanSimulateEvent();
        Long siteId = access.requireCurrentSiteForWrite();
        WearDevice device = devices.selectByIdForUpdate(id);
        if (device == null || !siteId.equals(device.getSiteId()))
            throw new ServiceException("设备不在当前厂站", HttpStatus.FORBIDDEN);
        if (!enabled || body == null || !(body.get("online") instanceof Boolean))
            throw new ServiceException("必须提供设备 online 布尔值", HttpStatus.BAD_REQUEST);
        String status = String.valueOf(body.getOrDefault("status", "normal"));
        String label = String.valueOf(body.getOrDefault("statusLabel", "正常"));
        if (!status.matches("[a-z][a-z0-9_.-]{0,63}") || label.length() > 40)
            throw new ServiceException("设备状态格式无效", HttpStatus.BAD_REQUEST);
        // Timestamp belongs to the receiving backend. It cannot be forged by the console.
        // wear_device stores second precision; truncate to avoid MySQL rounding
        // a heartbeat into the future and rejecting the next report in that second.
        Date now = new Date(System.currentTimeMillis() / 1000 * 1000);
        if (devices.applySimulationState(id, now, Boolean.TRUE.equals(body.get("online")) ? "1" : "0") != 1)
            throw new ServiceException("设备已有更新的遥测数据，请刷新", HttpStatus.CONFLICT);
        Map<String, Object> state = new HashMap<>();
        state.put("deviceId", String.valueOf(id));
        state.put("siteId", String.valueOf(siteId));
        state.put("online", body.get("online"));
        state.put("status", status);
        state.put("statusLabel", label);
        state.put("receivedAt", now.getTime());
        state.put("simulation", true);
        redis.setCacheObject(key(id), state, 7, TimeUnit.DAYS);
        return state;
    }

    public void enrich(DeviceDto dto)
    {
        if (!enabled) return;
        Map<String, Object> state = redis.getCacheObject(key(Long.valueOf(dto.getId())));
        if (state == null || !String.valueOf(state.get("siteId")).equals(dto.getSiteId())) return;
        long received = ((Number) state.get("receivedAt")).longValue();
        // A subsequent physical-device report takes precedence over simulated telemetry.
        if (dto.getLastReportedAt() != null && dto.getLastReportedAt().getTime() > received + 1000) return;
        boolean expired = System.currentTimeMillis() - received > 30000;
        dto.setSimulation(true);
        dto.setSource("simulation");
        dto.setOnline(!expired && Boolean.TRUE.equals(state.get("online")) ? "1" : "0");
        dto.setConnectionQuality("ok");
        dto.setSimulationStatus(String.valueOf(state.get("status")));
        dto.setSimulationStatusLabel(String.valueOf(state.get("statusLabel")));
    }
}
