package com.ruoyi.wear.event;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public final class EventStateMachine
{
    public static final String OPEN = "open";
    public static final String CLAIMED = "claimed";
    public static final String HANDLING = "handling";
    public static final String PENDING_REVIEW = "pending_review";
    public static final String CLOSED = "closed";

    public static final String SOS = "sos";
    public static final String FALL = "fall";
    public static final String IMPACT = "impact";
    public static final String GEOFENCE = "geofence";
    public static final String REALTIME = "realtime";

    private static final Set<String> TYPES = new HashSet<String>(
            Arrays.asList(SOS, FALL, IMPACT, GEOFENCE, REALTIME));
    private static final Set<String> HIGH = new HashSet<String>(
            Arrays.asList(SOS, FALL, IMPACT));

    private EventStateMachine()
    {
    }

    public static boolean isKnownType(String type)
    {
        return type != null && TYPES.contains(type);
    }

    public static boolean isHighRisk(String type)
    {
        return type != null && HIGH.contains(type);
    }

    public static String severityOf(String type)
    {
        return isHighRisk(type) ? "high" : "low";
    }

    public static boolean canClaim(String status)
    {
        return OPEN.equals(status);
    }

    public static boolean canHandle(String status)
    {
        return CLAIMED.equals(status) || HANDLING.equals(status);
    }

    public static String handleTarget(String type)
    {
        return isHighRisk(type) ? PENDING_REVIEW : HANDLING;
    }

    public static boolean canTransfer(String status)
    {
        return CLAIMED.equals(status) || HANDLING.equals(status);
    }

    public static boolean canDutyClose(String type, String status)
    {
        return !isHighRisk(type) && HANDLING.equals(status);
    }

    public static boolean canReviewerClose(String type, String status)
    {
        return isHighRisk(type) && PENDING_REVIEW.equals(status);
    }

    public static boolean canReopen(String status)
    {
        return CLOSED.equals(status);
    }
}
