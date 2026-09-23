package com.ruoyi.wear.event;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
public final class EventReminderPolicy {
    public static final String SQL="(COALESCE(severity,'')='warning')";
    private EventReminderPolicy() {}
    public static boolean isReminder(WearSafetyEvent event) { return EventSeverityPolicy.WARNING.equals(event.getSeverity()); }
}
