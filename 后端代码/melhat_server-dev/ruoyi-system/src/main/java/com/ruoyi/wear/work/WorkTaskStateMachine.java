package com.ruoyi.wear.work;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public final class WorkTaskStateMachine
{
    public static final String DRAFT = "draft";
    public static final String READY = "ready";
    public static final String IN_PROGRESS = "in_progress";
    public static final String PAUSED = "paused";
    public static final String ENDED = "ended";

    public static final String MATCH_NONE = "none";
    public static final String MATCHED = "matched";
    public static final String PENDING = "pending";

    private static final Set<String> TYPES = new HashSet<String>(Arrays.asList("patrol", "height", "other"));

    private WorkTaskStateMachine()
    {
    }

    public static boolean isKnownType(String workType)
    {
        return workType != null && TYPES.contains(workType);
    }

    public static boolean isEnded(String status)
    {
        return ENDED.equals(status);
    }

    public static boolean isMatchWindow(String status)
    {
        return IN_PROGRESS.equals(status) || PAUSED.equals(status);
    }

    public static boolean canStart(String status)
    {
        return READY.equals(status) || PAUSED.equals(status);
    }

    public static boolean canPause(String status)
    {
        return IN_PROGRESS.equals(status);
    }

    public static boolean canEnd(String status)
    {
        return IN_PROGRESS.equals(status) || PAUSED.equals(status) || READY.equals(status);
    }

    public static boolean canEditMembers(String status)
    {
        return !ENDED.equals(status);
    }

    public static String ticketStatus(boolean required, String ticketNo)
    {
        if (!required)
        {
            return "none";
        }
        if (ticketNo != null && !ticketNo.trim().isEmpty())
        {
            return "provided";
        }
        return "unverified";
    }

    public static String initialStatus(boolean hasMember, boolean hasWindow)
    {
        return hasMember && hasWindow ? READY : DRAFT;
    }
}
