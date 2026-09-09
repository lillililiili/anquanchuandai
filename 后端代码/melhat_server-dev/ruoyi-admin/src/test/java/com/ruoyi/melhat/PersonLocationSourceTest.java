package com.ruoyi.melhat;

import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.location.PersonLocationPolicy;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PersonLocationSourceTest {

    @Test
    void beltNeverContributesPersonLocation() {
        assertTrue(PersonLocationPolicy.canContributeLocation("helmet"));
        assertFalse(PersonLocationPolicy.canContributeLocation("belt"));
        assertFalse(PersonLocationPolicy.canContributeLocation(null));
    }

    @Test
    void noHelmetIsUnknownWithoutInventedFloor() {
        assertEquals(PersonLocationPolicy.SOURCE_NONE, PersonLocationPolicy.source(false));
        assertEquals(PersonLocationPolicy.SOURCE_HELMET, PersonLocationPolicy.source(true));
        assertEquals(TelemetryFreshness.UNKNOWN, PersonLocationPolicy.qualityWithoutFix());
        assertEquals("unknown", PersonLocationPolicy.floorSource());
        assertNull(PersonLocationPolicy.floor());
    }
}
