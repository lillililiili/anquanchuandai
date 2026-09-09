package com.ruoyi.melhat;

import com.ruoyi.wear.helmet.TelemetryFreshness;
import org.junit.jupiter.api.Test;

import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TelemetryFreshnessTest {

    @Test
    void missingReportIsUnknownNotOffline() {
        assertEquals("unknown", TelemetryFreshness.connectionQuality(null, new Date(), 180));
    }

    @Test
    void recentReportIsOkAndOldIsStale() {
        Date now = new Date();
        assertEquals("ok", TelemetryFreshness.connectionQuality(new Date(now.getTime() - 10_000L), now, 180));
        assertEquals("stale", TelemetryFreshness.connectionQuality(new Date(now.getTime() - 181_000L), now, 180));
    }

    @Test
    void olderSampleDoesNotApply() {
        Date newer = new Date(1_700_000_000_000L);
        Date older = new Date(1_699_000_000_000L);
        assertTrue(TelemetryFreshness.shouldApply(newer, null));
        assertTrue(TelemetryFreshness.shouldApply(newer, newer));
        assertFalse(TelemetryFreshness.shouldApply(older, newer));
        assertFalse(TelemetryFreshness.shouldApply(null, newer));
    }
}
