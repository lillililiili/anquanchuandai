package com.ruoyi.wear.assignment;

/**
 * One active helmet and one active belt per person. Used by issue checks and tests.
 */
public final class SameTypeSlot
{
    private SameTypeSlot()
    {
    }

    public static boolean occupied(int activeCountOfType)
    {
        return activeCountOfType >= 1;
    }
}
