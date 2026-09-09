package com.ruoyi.melhat;

import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.location.GeofencePolicy;
import org.junit.jupiter.api.Test;

import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class GeofenceDebounceTest {

    @Test
    void staleOrUnknownNeverEligible() {
        Date now = new Date();
        assertFalse(GeofencePolicy.sampleEligible(TelemetryFreshness.UNKNOWN, now, now, 180));
        assertFalse(GeofencePolicy.sampleEligible(TelemetryFreshness.STALE, now, now, 180));
        assertFalse(GeofencePolicy.sampleEligible(TelemetryFreshness.OK, new Date(now.getTime() - 200_000L), now, 180));
        assertTrue(GeofencePolicy.sampleEligible(TelemetryFreshness.OK, now, now, 180));
    }

    @Test
    void debounceAndTransition() {
        Date now = new Date();
        assertTrue(GeofencePolicy.debounceReady(now, now, 0));
        assertFalse(GeofencePolicy.debounceReady(now, now, 60));
        assertTrue(GeofencePolicy.debounceReady(new Date(now.getTime() - 61_000L), now, 60));
        assertEquals("enter", GeofencePolicy.transition(false, true));
        assertEquals("leave", GeofencePolicy.transition(true, false));
        assertNull(GeofencePolicy.transition(true, true));
        assertFalse(GeofencePolicy.isHelmetType("belt"));
        assertTrue(GeofencePolicy.isHelmetType("helmet"));
    }
}
