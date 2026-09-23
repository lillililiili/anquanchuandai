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

    private EventStateMachine()
    {
    }

    public static boolean isKnownType(String type)
    {
        return type != null && TYPES.contains(type);
    }

    public static boolean canClaim(String status)
    {
        return false;
    }

    public static boolean canHandle(String status)
    {
        return OPEN.equals(status) || CLAIMED.equals(status) || HANDLING.equals(status);
    }

    public static String handleTarget(String severity)
    {
        return EventSeverityPolicy.EMERGENCY.equals(severity) ? PENDING_REVIEW : CLOSED;
    }

    public static boolean canTransfer(String status)
    {
        return false;
    }

    public static boolean canDutyClose(String type, String status)
    {
        return false;
    }

    public static boolean canReviewerClose(String severity, String status)
    {
        return EventSeverityPolicy.EMERGENCY.equals(severity) && PENDING_REVIEW.equals(status);
    }

    public static boolean canReopen(String status)
    {
        return CLOSED.equals(status);
    }
}
