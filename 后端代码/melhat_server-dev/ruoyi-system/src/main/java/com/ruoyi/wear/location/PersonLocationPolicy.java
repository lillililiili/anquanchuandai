package com.ruoyi.wear.location;

import com.ruoyi.wear.helmet.TelemetryFreshness;

public final class PersonLocationPolicy
{
    public static final String SOURCE_HELMET = "helmet";
    public static final String SOURCE_NONE = "none";
    public static final String FLOOR_SOURCE_UNKNOWN = "unknown";

    private PersonLocationPolicy()
    {
    }

    public static boolean canContributeLocation(String typeCode)
    {
        return GeofencePolicy.isHelmetType(typeCode);
    }

    public static String source(boolean hasIssuedHelmet)
    {
        return hasIssuedHelmet ? SOURCE_HELMET : SOURCE_NONE;
    }

    public static String qualityWithoutFix()
    {
        return TelemetryFreshness.UNKNOWN;
    }

    public static String floorSource()
    {
        return FLOOR_SOURCE_UNKNOWN;
    }

    public static String floor()
    {
        return null;
    }
}
