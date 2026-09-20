package com.ruoyi.wear.helmet;

import java.math.BigDecimal;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.alibaba.fastjson2.JSON;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.headband.pojo.param.GnssNotifyParam;
import com.ruoyi.headband.pojo.param.HelmatAlarm;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.pojo.po.SosAlarmRecord;
import com.ruoyi.helmet.service.IRealTimeAlarmService;
import com.ruoyi.helmet.service.ISafetyHatLocationRecordService;
import com.ruoyi.helmet.service.ISosAlarmRecordService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearDeviceLegacyHat;
import com.ruoyi.wear.device.mapper.WearDeviceLegacyHatMapper;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.event.EventIngestService;
import com.ruoyi.wear.event.domain.WearEventLegacy;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.dto.IngestRequest;
import com.ruoyi.wear.event.mapper.WearEventLegacyMapper;
import com.ruoyi.wear.helmet.domain.WearAdapterAlert;
import com.ruoyi.wear.helmet.domain.WearDeviceSample;
import com.ruoyi.wear.helmet.domain.WearIngestRaw;
import com.ruoyi.wear.helmet.mapper.WearAdapterAlertMapper;
import com.ruoyi.wear.helmet.mapper.WearDeviceSampleMapper;
import com.ruoyi.wear.helmet.mapper.WearIngestRawMapper;
import com.ruoyi.wear.location.GeofenceEngine;

@Service
public class HelmetAdapter
{
    @Autowired
    private WearIngestRawMapper rawMapper;
    @Autowired
    private WearDeviceSampleMapper sampleMapper;
    @Autowired
    private WearAdapterAlertMapper alertMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearDeviceLegacyHatMapper legacyHatMapper;
    @Autowired
    private WearEventLegacyMapper eventLegacyMapper;
    @Autowired
    private EventIngestService eventIngestService;
    @Autowired
    private IRealTimeAlarmService realTimeAlarmService;
    @Autowired
    private ISafetyHatLocationRecordService locationRecordService;
    @Autowired
    private ISosAlarmRecordService sosAlarmRecordService;
    @Autowired
    @Lazy
    private GeofenceEngine geofenceEngine;

    @Transactional(rollbackFor = Exception.class)
    public ResponseVO handleAlarm(HelmatAlarm param)
    {
        Map<String, Object> payload = new LinkedHashMap<String, Object>();
        payload.put("type", param == null ? null : param.getType());
        payload.put("alarmName", param == null ? null : param.getAlarmName());
        payload.put("alarmDescription", param == null ? null : param.getAlarmDescription());
        payload.put("helmetSn", param == null ? null : param.getHelmetSn());
        payload.put("startTime", param == null ? null : param.getStartTime());
        payload.put("endTime", param == null ? null : param.getEndTime());
        return process("/ext/helmetAlarm", payload, false);
    }

    @Transactional(rollbackFor = Exception.class)
    public ResponseVO handleGnss(GnssNotifyParam param)
    {
        return process("/ext/notifyGnss", gnssMap(param), false);
    }

    @Transactional(rollbackFor = Exception.class)
    public ResponseVO handleSos(GnssNotifyParam param)
    {
        return process("/ext/sosCall", gnssMap(param), false);
    }

    @Transactional(rollbackFor = Exception.class)
    public ResponseVO replay(String path, Map<String, Object> payload)
    {
        return process(path, payload == null ? new LinkedHashMap<String, Object>() : payload, true);
    }

    private ResponseVO process(String path, Map<String, Object> payload, boolean demoReplay)
    {
        Date now = new Date();
        String helmetSn = str(payload.get("helmetSn"));
        String alarmType = str(payload.get("type"));
        String startTime = str(payload.get("startTime"));
        String timestamp = str(payload.get("timestamp"));
        String messageKey = HelmetTypeMapping.messageKey(path, helmetSn, alarmType, startTime, timestamp);
        WearIngestRaw raw = new WearIngestRaw();
        raw.setPath(path);
        raw.setHelmetSn(helmetSn);
        raw.setMessageKey(messageKey);
        raw.setReceivedAt(now);
        raw.setPayloadJson(JSON.toJSONString(payload));
        raw.setAuthOk(1);
        raw.setProcessStatus("accepted");
        raw.setCreateTime(now);
        if (StringUtils.isEmpty(helmetSn))
        {
            raw.setProcessStatus("ignored");
            raw.setError("帽子编号不能是空");
            rawMapper.insert(raw);
            return ok("帽子编号不能是空");
        }
        WearDevice device = findDevice(helmetSn);
        if (device == null)
        {
            raw.setProcessStatus("ignored");
            raw.setError("帽子不存在");
            rawMapper.insert(raw);
            alert("unknown-sn", "未知帽号 " + helmetSn);
            return ok("帽子不存在");
        }
        raw.setDeviceId(device.getId());
        if (device.getSiteId() == null)
        {
            raw.setProcessStatus("ignored");
            raw.setError("设备未分配厂站");
            rawMapper.insert(raw);
            return ok("success");
        }
        Date occurred = parseVendorTime(firstNonEmpty(startTime, timestamp), now);
        boolean gnss = path != null && path.contains("notifyGnss");
        BigDecimal lat = decimal(payload.get("latitude"));
        BigDecimal lng = decimal(payload.get("longitude"));
        try
        {
            saveSample(device.getId(), occurred, now, lat, lng, str(payload.get("altitude")), str(payload.get("speed")));
        }
        catch (DataIntegrityViolationException ignored)
        {
        }
        deviceMapper.applyTelemetryIfNewer(device.getId(), occurred, "1", null);
        if (lat != null && lng != null)
        {
            try
            {
                geofenceEngine.onHelmetSample(device, occurred, lat, lng, "ok");
            }
            catch (Exception ex)
            {
                alert("geofence", "围栏判定失败 " + helmetSn + " " + ex.getMessage());
            }
        }
        if (gnss)
        {
            dualWriteLocation(device, helmetSn, lat, lng, str(payload.get("speed")), str(payload.get("altitude")), timestamp, now);
            rawMapper.insert(raw);
            return ok("success");
        }
        String eventType = HelmetTypeMapping.eventType(path, alarmType);
        if (eventType == null)
        {
            raw.setProcessStatus("ignored");
            raw.setError("不支持的告警类型");
            rawMapper.insert(raw);
            return ok("告警类型不能是空");
        }
        boolean demo = demoReplay || "demo".equals(device.getCreateBy());
        IngestRequest ingest = new IngestRequest();
        ingest.setSource("helmet");
        ingest.setSourceEventId(messageKey);
        ingest.setType(eventType);
        ingest.setAlarmCode("helmet." + ("sos".equals(eventType) ? "sos" : alarmType));
        ingest.setAlarmName(str(payload.get("alarmName")));
        ingest.setAlarmDescription(str(payload.get("alarmDescription")));
        ingest.setSiteId(String.valueOf(device.getSiteId()));
        ingest.setDeviceId(String.valueOf(device.getId()));
        ingest.setOccurredAt(occurred);
        ingest.setLat(lat);
        ingest.setLng(lng);
        ingest.setLocationQuality(lat != null && lng != null ? "ok" : "unknown");
        ingest.setDemo(demo);
        ingest.setActor("helmet");
        EventDto event = eventIngestService.ingest(ingest);
        if (event.getRepeatCount() != null && event.getRepeatCount().intValue() >= 1)
        {
            raw.setProcessStatus("duplicate");
        }
        rawMapper.insert(raw);
        dualWriteEvent(path, eventType, device, helmetSn, event, alarmType, occurred, lat, lng, now);
        return ok("success");
    }

    private void saveSample(Long deviceId, Date occurred, Date now, BigDecimal lat, BigDecimal lng, String alt, String speed)
    {
        WearDeviceSample sample = new WearDeviceSample();
        sample.setDeviceId(deviceId);
        sample.setOccurredAt(occurred);
        sample.setReceivedAt(now);
        sample.setLat(lat);
        sample.setLng(lng);
        sample.setAltitude(alt);
        sample.setSpeed(speed);
        sample.setOnline("1");
        sample.setLocationQuality(lat != null && lng != null ? "ok" : "unknown");
        sample.setCreateTime(now);
        sampleMapper.insert(sample);
    }

    private void dualWriteEvent(String path, String eventType, WearDevice device, String helmetSn, EventDto event,
            String alarmType, Date occurred, BigDecimal lat, BigDecimal lng, Date now)
    {
        try
        {
            Long hatId = legacyHatId(device.getId());
            Long personUserId = null;
            String personName = event.getPersonName();
            if (path != null && path.contains("sosCall"))
            {
                SosAlarmRecord record = new SosAlarmRecord();
                record.setHatId(hatId);
                record.setHatNumber(helmetSn);
                record.setUserId(personUserId);
                record.setUserName(personName);
                record.setLat(lat == null ? null : lat.toPlainString());
                record.setLng(lng == null ? null : lng.toPlainString());
                record.setCallTime(occurred);
                record.setCreateTime(now);
                sosAlarmRecordService.save(record);
                mapLegacy("sos", record.getId(), event.getId());
            }
            else
            {
                RealTimeAlarm alarm = new RealTimeAlarm();
                alarm.setHatId(hatId);
                alarm.setHatNumber(helmetSn);
                alarm.setUserId(personUserId);
                alarm.setUserName(personName);
                alarm.setAlarmType(alarmType);
                alarm.setAlarmLevel("2");
                alarm.setAlarmStartTime(occurred);
                alarm.setCreateTime(now);
                alarm.setIsHandled(0);
                realTimeAlarmService.save(alarm);
                mapLegacy("realtime", alarm.getId(), event.getId());
            }
        }
        catch (Exception ex)
        {
            alert("legacy-write", "旧表双写失败 " + helmetSn + " " + ex.getMessage());
        }
    }

    private void dualWriteLocation(WearDevice device, String helmetSn, BigDecimal lat, BigDecimal lng,
            String speed, String altitude, String timestamp, Date now)
    {
        try
        {
            SafetyHatLocationRecord record = new SafetyHatLocationRecord();
            record.setHatId(legacyHatId(device.getId()));
            record.setHatNumber(helmetSn);
            record.setLat(lat == null ? null : lat.toPlainString());
            record.setLng(lng == null ? null : lng.toPlainString());
            record.setSpeed(speed);
            record.setAltitude(altitude);
            record.setTimestamp(timestamp);
            record.setCreateTime(now);
            locationRecordService.save(record);
        }
        catch (Exception ex)
        {
            alert("legacy-location", "旧位置表失败 " + helmetSn + " " + ex.getMessage());
        }
    }

    private void mapLegacy(String kind, Long oldId, String eventId)
    {
        if (oldId == null || StringUtils.isEmpty(eventId))
        {
            return;
        }
        WearEventLegacy row = new WearEventLegacy();
        row.setSourceKind(kind);
        row.setOldId(oldId);
        row.setEventId(Long.valueOf(eventId));
        row.setCreateTime(new Date());
        try
        {
            eventLegacyMapper.insert(row);
        }
        catch (DataIntegrityViolationException ignored)
        {
        }
    }

    private WearDevice findDevice(String helmetSn)
    {
        WearDevice bySn = deviceMapper.selectOne(new LambdaQueryWrapper<WearDevice>()
                .eq(WearDevice::getSn, helmetSn).last("LIMIT 1"));
        if (bySn != null)
        {
            return bySn;
        }
        return deviceMapper.selectOne(new LambdaQueryWrapper<WearDevice>()
                .eq(WearDevice::getExternalCode, helmetSn).last("LIMIT 1"));
    }

    private Long legacyHatId(Long deviceId)
    {
        WearDeviceLegacyHat map = legacyHatMapper.selectOne(new LambdaQueryWrapper<WearDeviceLegacyHat>()
                .eq(WearDeviceLegacyHat::getDeviceId, deviceId).last("LIMIT 1"));
        return map == null ? null : map.getHatId();
    }

    private void alert(String kind, String summary)
    {
        WearAdapterAlert row = new WearAdapterAlert();
        row.setKind(kind);
        row.setSummary(summary);
        row.setCreateTime(new Date());
        alertMapper.insert(row);
    }

    private Map<String, Object> gnssMap(GnssNotifyParam param)
    {
        Map<String, Object> payload = new LinkedHashMap<String, Object>();
        payload.put("helmetSn", param == null ? null : param.getHelmetSn());
        payload.put("latitude", param == null ? null : param.getLatitude());
        payload.put("longitude", param == null ? null : param.getLongitude());
        payload.put("speed", param == null ? null : param.getSpeed());
        payload.put("altitude", param == null ? null : param.getAltitude());
        payload.put("timestamp", param == null ? null : param.getTimestamp());
        return payload;
    }

    private ResponseVO ok(String msg)
    {
        return new ResponseVO(200, msg, null);
    }

    private String str(Object value)
    {
        return value == null ? null : String.valueOf(value);
    }

    private String firstNonEmpty(String a, String b)
    {
        if (StringUtils.isNotEmpty(a))
        {
            return a;
        }
        return b;
    }

    private BigDecimal decimal(Object value)
    {
        if (value == null || String.valueOf(value).trim().isEmpty())
        {
            return null;
        }
        try
        {
            return new BigDecimal(String.valueOf(value).trim());
        }
        catch (NumberFormatException ex)
        {
            return null;
        }
    }

    private Date parseVendorTime(String raw, Date fallback)
    {
        if (StringUtils.isEmpty(raw))
        {
            return fallback;
        }
        try
        {
            return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(raw.trim());
        }
        catch (ParseException ignored)
        {
        }
        try
        {
            return Date.from(java.time.OffsetDateTime.parse(raw.trim()).toInstant());
        }
        catch (Exception ignored)
        {
        }
        return fallback;
    }
}
