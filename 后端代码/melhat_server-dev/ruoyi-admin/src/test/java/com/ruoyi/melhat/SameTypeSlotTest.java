package com.ruoyi.melhat;

import com.ruoyi.wear.assignment.SameTypeSlot;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SameTypeSlotTest {

    @Test
    void oneHelmetOrBeltBlocksAnotherOfSameType() {
        assertFalse(SameTypeSlot.occupied(0));
        assertTrue(SameTypeSlot.occupied(1));
        assertTrue(SameTypeSlot.occupied(2));
    }
}
