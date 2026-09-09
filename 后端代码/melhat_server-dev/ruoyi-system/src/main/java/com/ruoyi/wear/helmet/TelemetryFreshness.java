package com.ruoyi.wear.helmet;

import java.util.Date;

public final class TelemetryFreshness
{
    public static final String UNKNOWN = "unknown";
    public static final String OK = "ok";
    public static final String STALE = "stale";

    private TelemetryFreshness()
    {
    }

    public static String connectionQuality(Date lastReportedAt, Date now, int staleAfterSeconds)
    {
        if (lastReportedAt == null)
        {
            return UNKNOWN;
        }
        Date baseline = now == null ? new Date() : now;
        long ageMs = baseline.getTime() - lastReportedAt.getTime();
        if (ageMs < 0)
        {
            return OK;
        }
        int window = staleAfterSeconds < 1 ? 180 : staleAfterSeconds;
        if (ageMs <= window * 1000L)
        {
            return OK;
        }
        return STALE;
    }

    public static boolean shouldApply(Date incomingOccurredAt, Date lastTelemetryAt)
    {
        if (incomingOccurredAt == null)
        {
            return false;
        }
        if (lastTelemetryAt == null)
        {
            return true;
        }
        return !incomingOccurredAt.before(lastTelemetryAt);
    }
}
