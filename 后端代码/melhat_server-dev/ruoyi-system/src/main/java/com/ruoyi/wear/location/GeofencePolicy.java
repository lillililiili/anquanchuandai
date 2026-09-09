package com.ruoyi.wear.location;

import java.util.Date;
import com.ruoyi.wear.helmet.TelemetryFreshness;

public final class GeofencePolicy
{
    public static final String ENTER = "enter";
    public static final String LEAVE = "leave";

    private GeofencePolicy()
    {
    }

    public static boolean sampleEligible(String locationQuality, Date occurredAt, Date now, int staleAfterSeconds)
    {
        if (!TelemetryFreshness.OK.equals(locationQuality) || occurredAt == null)
        {
            return false;
        }
        return TelemetryFreshness.OK.equals(TelemetryFreshness.connectionQuality(occurredAt, now, staleAfterSeconds));
    }

    public static boolean debounceReady(Date since, Date now, int debounceSeconds)
    {
        if (debounceSeconds <= 0)
        {
            return true;
        }
        if (since == null || now == null)
        {
            return false;
        }
        return now.getTime() - since.getTime() >= debounceSeconds * 1000L;
    }

    public static String transition(boolean wasInside, boolean nowInside)
    {
        if (!wasInside && nowInside)
        {
            return ENTER;
        }
        if (wasInside && !nowInside)
        {
            return LEAVE;
        }
        return null;
    }

    public static boolean isHelmetType(String typeCode)
    {
        return "helmet".equals(typeCode);
    }
}
