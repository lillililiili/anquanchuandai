package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.mapper.RealTimeAlarmMapper;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.mapper.SafetyHatLocationRecordMapper;
import com.ruoyi.helmet.mapper.SosAlarmRecordMapper;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import com.ruoyi.helmet.pojo.po.SosAlarmRecord;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Propagation;
import java.text.SimpleDateFormat;
import java.util.Date;

/** Database-only transaction boundary. Never enters GuardianStore while database locks are held. */
@Service
public class DirectHelmetPersistence {
    private final SafetyHatInfoMapper hats;
    private final SafetyHatLocationRecordMapper locations;
    private final RealTimeAlarmMapper alarms;
    private final SosAlarmRecordMapper sosRecords;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private com.ruoyi.guardian.HelmetBusinessJournal journal;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private DirectHelmetLocationProfiles profiles;

    public DirectHelmetPersistence(SafetyHatInfoMapper hats, SafetyHatLocationRecordMapper locations,
            RealTimeAlarmMapper alarms, SosAlarmRecordMapper sosRecords) {
        this.hats = hats; this.locations = locations; this.alarms = alarms; this.sosRecords = sosRecords;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void connection(SafetyHatInfo hat, boolean online) {
        SafetyHatInfo patch = new SafetyHatInfo();
        patch.setId(hat.getId()); patch.setStatus(online ? "1" : "0");
        patch.setUpdateBy("direct-helmet"); patch.setUpdateTime(new Date());
        if (hats.updateById(patch) != 1) throw new IllegalStateException("设备状态保存失败");
    }

    @Transactional(propagation = Propagation.REQUIRED)
    public JSONObject receive(SafetyHatInfo hat, DirectHelmetMessage message, JSONObject context) {
        Date now = context!=null&&context.getString("receivedAt")!=null?Date.from(java.time.Instant.parse(context.getString("receivedAt"))):new Date();
        String timestamp = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(now);
        JSONObject result = context == null ? new JSONObject() : JSONObject.parseObject(context.toJSONString());
        result.put("receivedAt", now.toInstant().toString());
        result.put("reportedAt", now.toInstant().toString()); // Device supplies no observation timestamp.
        result.put("deviceReportedAt", null);
        result.put("receivedMillis", now.getTime());
        result.put("timestamp", timestamp);
        result.put("deviceId", hat.getHatNumber());
        if(result.getString("personId")==null) result.put("personId", "");
        result.put("longitude", message.longitude); result.put("latitude", message.latitude);
        result.put("locationSource", message.locationSource); result.put("gps", message.gps);
        result.put("accuracyMeters", message.accuracyMeters); result.put("firmware", message.firmware);
        result.put("source", "direct-helmet"); result.put("coordinateSystem", "UNKNOWN");
        result.put("locationQuality", "unknown");
        if(profiles!=null) profiles.apply(hat.getHatNumber(),result);
        result.put("locationReportedAt", message.hasLocation()?now.toInstant().toString():null);
        if(!"ca_report_location".equals(message.act)) {
            // Alarm frames may repeat a cached fix. They cannot prove a new observation.
            JSONObject device=result.getJSONObject("device");
            boolean corroborated=device!=null && "CURRENT".equals(device.getString("locationFreshness"))
                    && sameCoordinate(message.longitude,device.getString("longitude"))
                    && sameCoordinate(message.latitude,device.getString("latitude"));
            result.put("locationReportedAt",corroborated?device.get("locationReportedAt"):null);
            if(!corroborated) result.put("locationQuality","unknown");
        }
        result.put("act",message.act); result.put("rawType",message.alarmType);
        SafetyHatInfo patch = new SafetyHatInfo();
        patch.setId(hat.getId()); patch.setStatus("1");
        patch.setUpdateBy("direct-helmet"); patch.setUpdateTime(now);
        if ("ca_report_location".equals(message.act) && message.battery != null)
            patch.setElectricityUsage(message.battery);
        if (hats.updateById(patch) != 1) throw new IllegalStateException("设备状态保存失败");
        if ("ca_report_location".equals(message.act) && message.hasLocation()) {
            SafetyHatLocationRecord record = new SafetyHatLocationRecord();
            record.setHatId(hat.getId()); record.setHatNumber(hat.getHatNumber());
            record.setUserId(result.containsKey("rawUserId")?result.getLong("rawUserId"):hat.getBindUserId()); record.setUserName(result.containsKey("rawUserName")?result.getString("rawUserName"):hat.getBindUserName());
            record.setLng(message.longitude); record.setLat(message.latitude);
            record.setSpeed(message.speed); record.setTimestamp(timestamp);
            // relative_altitude is not sea-level altitude.
            record.setCreateBy("direct-helmet"); record.setCreateTime(now); record.setDelFlag(0);
            if (locations.insert(record) != 1) throw new IllegalStateException("设备定位保存失败");
            result.put("id", "HL-" + java.util.UUID.randomUUID());
            if(journal!=null) journal.location(result);
        } else if ("ca_sos".equals(message.act)) {
            String type = message.alarmType == null ? "unknown" : message.alarmType;
            RealTimeAlarm alarm = new RealTimeAlarm();
            alarm.setHatId(hat.getId()); alarm.setHatNumber(hat.getHatNumber());
            alarm.setUserId(result.containsKey("rawUserId")?result.getLong("rawUserId"):hat.getBindUserId()); alarm.setUserName(result.containsKey("rawUserName")?result.getString("rawUserName"):hat.getBindUserName());
            alarm.setAlarmType(type.length() <= 32 ? type : "unknown"); alarm.setAlarmLevel("2");
            alarm.setAlarmStartTime(now); alarm.setCreateTime(now);
            alarm.setCreateBy("direct-helmet"); alarm.setDelFlag("0"); alarm.setIsHandled(0);
            JSONObject source = new JSONObject();
            source.put("protocol", "direct-helmet"); source.put("act", message.act);
            source.put("rawType", message.alarmType);
            if (message.hasLocation()) {
                source.put("longitude", message.longitude); source.put("latitude", message.latitude);
            }
            alarm.setDescription(source.toJSONString());
            if (alarms.insert(alarm) != 1) throw new IllegalStateException("设备告警保存失败");
            result.put("sourceRecordType", "real_time_alarm"); result.put("sourceRecordId",alarm.getId());
        } else if ("ca_sip_sos".equals(message.act)) {
            SosAlarmRecord sos = new SosAlarmRecord();
            sos.setHatId(hat.getId()); sos.setHatNumber(hat.getHatNumber());
            sos.setUserId(result.containsKey("rawUserId")?result.getLong("rawUserId"):hat.getBindUserId()); sos.setUserName(result.containsKey("rawUserName")?result.getString("rawUserName"):hat.getBindUserName());
            sos.setLng(message.longitude); sos.setLat(message.latitude);
            sos.setCallTime(now); sos.setCreateTime(now); sos.setCreateBy("direct-helmet");
            sos.setDelFlag("0"); sos.setProcessStatus(false);
            sos.setDescription("一体式安全帽 SOS 已收到，待值守人员处置；收到求助不代表通话已接通");
            if (sosRecords.insert(sos) != 1) throw new IllegalStateException("设备 SOS 保存失败");
            result.put("sourceRecordType", "sos_alarm_record"); result.put("sourceRecordId",sos.getId());
        }
        if(result.containsKey("sourceRecordType")) {
            result.put("eventId", "HE-" + java.util.UUID.randomUUID());
            if(journal!=null) journal.event(result);
        }
        return result;
    }
    private static boolean sameCoordinate(String first,String second) {
        if(first==null || second==null) return false;
        try { return new java.math.BigDecimal(first).compareTo(new java.math.BigDecimal(second))==0; }
        catch(NumberFormatException error) { return false; }
    }
}
