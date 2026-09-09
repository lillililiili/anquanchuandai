package com.ruoyi.wear.helmet;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.helmet.domain.WearDeviceSample;
import com.ruoyi.wear.helmet.domain.WearIngestRaw;
import com.ruoyi.wear.helmet.mapper.WearDeviceSampleMapper;
import com.ruoyi.wear.helmet.mapper.WearIngestRawMapper;

@Service
public class HelmetQueryService
{
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearDeviceSampleMapper sampleMapper;
    @Autowired
    private WearIngestRawMapper rawMapper;
    @Autowired
    private SiteAccessService siteAccessService;

    public List<Map<String, Object>> samples(Long deviceId)
    {
        WearDevice device = requireDevice(deviceId);
        List<WearDeviceSample> rows = sampleMapper.selectList(new LambdaQueryWrapper<WearDeviceSample>()
                .eq(WearDeviceSample::getDeviceId, device.getId())
                .orderByDesc(WearDeviceSample::getOccurredAt)
                .last("LIMIT 20"));
        List<Map<String, Object>> list = new ArrayList<Map<String, Object>>();
        for (WearDeviceSample row : rows)
        {
            Map<String, Object> item = new LinkedHashMap<String, Object>();
            item.put("id", String.valueOf(row.getId()));
            item.put("occurredAt", row.getOccurredAt());
            item.put("receivedAt", row.getReceivedAt());
            item.put("lat", row.getLat());
            item.put("lng", row.getLng());
            item.put("altitude", row.getAltitude());
            item.put("speed", row.getSpeed());
            item.put("locationQuality", row.getLocationQuality());
            list.add(item);
        }
        return list;
    }

    public List<Map<String, Object>> ingest(Long deviceId)
    {
        WearDevice device = requireDevice(deviceId);
        boolean full = siteAccessService.canWriteDevice();
        List<WearIngestRaw> rows = rawMapper.selectList(new LambdaQueryWrapper<WearIngestRaw>()
                .eq(WearIngestRaw::getDeviceId, device.getId())
                .orderByDesc(WearIngestRaw::getId)
                .last("LIMIT 20"));
        List<Map<String, Object>> list = new ArrayList<Map<String, Object>>();
        for (WearIngestRaw row : rows)
        {
            Map<String, Object> item = new LinkedHashMap<String, Object>();
            item.put("id", String.valueOf(row.getId()));
            item.put("path", row.getPath());
            item.put("messageKey", row.getMessageKey());
            item.put("receivedAt", row.getReceivedAt());
            item.put("processStatus", row.getProcessStatus());
            item.put("error", row.getError());
            if (full)
            {
                item.put("payload", redact(row.getPayloadJson()));
            }
            list.add(item);
        }
        return list;
    }

    private WearDevice requireDevice(Long deviceId)
    {
        WearDevice device = deviceMapper.selectById(deviceId);
        siteAccessService.assertDeviceReadable(device);
        return device;
    }

    private String redact(String payload)
    {
        if (payload == null)
        {
            return null;
        }
        return payload.replaceAll("(?i)(token|password|signature)(\\\"\\s*:\\s*\\\")[^\\\"]*", "$1$2***");
    }
}
