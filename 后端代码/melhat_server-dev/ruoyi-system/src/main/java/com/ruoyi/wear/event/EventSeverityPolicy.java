package com.ruoyi.wear.event;

import java.util.Locale;
import com.ruoyi.wear.event.domain.WearSafetyEvent;

/** Workflow levels use the actual source device; fall is a device alarm, not a person-fall diagnosis. */
public final class EventSeverityPolicy {
    public static final String WARNING="warning", ABNORMAL="abnormal", EMERGENCY="emergency";
    private EventSeverityPolicy() {}
    public static String classify(WearSafetyEvent event) {
        String device=value(event.getDeviceType()).toLowerCase(Locale.ROOT);
        String code=value(event.getAlarmCode()).toLowerCase(Locale.ROOT);
        if ("sos".equals(event.getEventType())) return EMERGENCY;
        // Never apply a watch or belt rule to a helmet, even if a sender mislabels the code.
        if (("helmet".equals(device) || "belt".equals(device) || "watch".equals(device))
                && (code.equals(device+".battery") || code.equals(device+".low_battery"))) return WARNING;
        return ABNORMAL;
    }
    /** Original SOS type is authoritative even when newer snapshot fields are absent. */
    public static String effectiveSeverity(WearSafetyEvent event) {
        return "sos".equals(event.getEventType()) ? EMERGENCY : event.getSeverity();
    }
    public static boolean isEmergency(WearSafetyEvent event) { return EMERGENCY.equals(effectiveSeverity(event)); }
    private static String value(String v) { return v==null?"":v.trim(); }
}
