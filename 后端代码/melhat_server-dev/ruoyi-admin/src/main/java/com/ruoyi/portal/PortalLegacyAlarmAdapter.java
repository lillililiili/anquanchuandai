package com.ruoyi.portal;
import com.ruoyi.helmet.pojo.po.RealTimeAlarm;
import com.ruoyi.portal.PortalEventModels.Fact;
/** Pure mapping only. No repository calls, no inferred station/person/verification identity. */
public final class PortalLegacyAlarmAdapter {
    private PortalLegacyAlarmAdapter(){}
    public static Fact map(RealTimeAlarm old,String eventId,String confirmedSiteId,String confirmedDeviceId){
        if(old==null||old.getId()==null||!PortalQuery.id(eventId)||!PortalQuery.id(confirmedSiteId)||(confirmedDeviceId!=null&&!PortalQuery.id(confirmedDeviceId)))throw PortalException.invalid();
        Fact f=new Fact();f.eventId=eventId;f.siteId=confirmedSiteId;f.sourceSystem="LEGACY_HELMET";f.sourceEventId=old.getId().toString();f.eventCode=f.sourceEventId;f.title="遗留安全帽报警";
        f.rawType=old.getAlarmType();f.rawLevel=old.getAlarmLevel();f.legacyHandled=old.getIsHandled();f.deviceId=confirmedDeviceId;f.deviceCode=confirmedDeviceId==null?null:old.getHatNumber();
        f.occurredAt=old.getAlarmStartTime()==null?null:old.getAlarmStartTime().toInstant().toString();
        // Database modification time is only the source row update time, never device report time.
        f.sourceUpdatedAt=old.getUpdateTime()==null?null:old.getUpdateTime().toInstant().toString();return f;
    }
}
