package com.ruoyi.wear.work;

import com.ruoyi.wear.helmet.TelemetryFreshness;

public final class EquipmentCheck
{
    public static final String MISSING = "missing";
    public static final String OK = "ok";
    public static final String UNKNOWN = "unknown";

    private EquipmentCheck()
    {
    }

    /**
     * Belt never reports ok without a real protocol. Helmet ok only when connectionQuality is ok.
     */
    public static String result(String requiredType, boolean hasIssued, String connectionQuality)
    {
        if (!hasIssued)
        {
            return MISSING;
        }
        if ("belt".equals(requiredType))
        {
            return UNKNOWN;
        }
        if (TelemetryFreshness.OK.equals(connectionQuality))
        {
            return OK;
        }
        return UNKNOWN;
    }
}
