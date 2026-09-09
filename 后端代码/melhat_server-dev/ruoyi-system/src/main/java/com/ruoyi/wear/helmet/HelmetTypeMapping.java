package com.ruoyi.wear.helmet;

import com.ruoyi.wear.event.EventStateMachine;

public final class HelmetTypeMapping
{
    private HelmetTypeMapping()
    {
    }

    public static String eventType(String path, String alarmType)
    {
        if (path != null && path.contains("sosCall"))
        {
            return EventStateMachine.SOS;
        }
        if ("fall".equals(alarmType))
        {
            return EventStateMachine.FALL;
        }
        if ("silent".equals(alarmType) || "removal".equals(alarmType) || "proximity".equals(alarmType))
        {
            return EventStateMachine.REALTIME;
        }
        return null;
    }

    public static String messageKey(String path, String helmetSn, String alarmType, String startTime, String timestamp)
    {
        String sn = helmetSn == null ? "" : helmetSn.trim();
        if (path != null && path.contains("notifyGnss"))
        {
            return sn + "|gnss|" + nullToEmpty(timestamp);
        }
        if (path != null && path.contains("sosCall"))
        {
            String t = StringUtilsNotEmpty(timestamp) ? timestamp : startTime;
            return sn + "|sos|" + nullToEmpty(t);
        }
        return sn + "|" + nullToEmpty(alarmType) + "|" + nullToEmpty(startTime);
    }

    private static boolean StringUtilsNotEmpty(String value)
    {
        return value != null && !value.trim().isEmpty();
    }

    private static String nullToEmpty(String value)
    {
        return value == null ? "" : value.trim();
    }
}
