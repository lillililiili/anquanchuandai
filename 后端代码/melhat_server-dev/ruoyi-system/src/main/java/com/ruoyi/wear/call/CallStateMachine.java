package com.ruoyi.wear.call;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public final class CallStateMachine
{
    public static final String REQUESTING = "requesting";
    public static final String OFFERED = "offered";
    public static final String CONNECTED = "connected";
    public static final String ENDED = "ended";
    public static final String FAILED = "failed";
    public static final String TIMED_OUT = "timed_out";

    private static final Set<String> TERMINAL = new HashSet<String>(
            Arrays.asList(ENDED, FAILED, TIMED_OUT));

    private CallStateMachine()
    {
    }

    public static boolean isTerminal(String status)
    {
        return status != null && TERMINAL.contains(status);
    }

    public static boolean canJoin(String status)
    {
        return OFFERED.equals(status);
    }

    public static boolean isConnectedDisplay(String status)
    {
        return CONNECTED.equals(status);
    }

    public static boolean ttsHeard(String commandStatus)
    {
        return false;
    }
}
