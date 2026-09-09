package com.ruoyi.melhat;

import com.ruoyi.wear.event.EventStateMachine;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EventStateMachineTest {

    @Test
    void sosFallImpactAreHighRisk() {
        assertTrue(EventStateMachine.isHighRisk("sos"));
        assertTrue(EventStateMachine.isHighRisk("fall"));
        assertTrue(EventStateMachine.isHighRisk("impact"));
        assertEquals("high", EventStateMachine.severityOf("sos"));
        assertFalse(EventStateMachine.isHighRisk("geofence"));
        assertEquals("low", EventStateMachine.severityOf("geofence"));
        assertEquals("low", EventStateMachine.severityOf("realtime"));
    }

    @Test
    void claimOnlyFromOpen() {
        assertTrue(EventStateMachine.canClaim("open"));
        assertFalse(EventStateMachine.canClaim("claimed"));
        assertFalse(EventStateMachine.canClaim("closed"));
    }

    @Test
    void handleMovesHighRiskToReview() {
        assertEquals("pending_review", EventStateMachine.handleTarget("sos"));
        assertEquals("handling", EventStateMachine.handleTarget("geofence"));
        assertTrue(EventStateMachine.canHandle("claimed"));
        assertTrue(EventStateMachine.canHandle("handling"));
        assertFalse(EventStateMachine.canHandle("open"));
        assertFalse(EventStateMachine.canHandle("pending_review"));
    }

    @Test
    void dutyCannotCloseHighRisk() {
        assertFalse(EventStateMachine.canDutyClose("sos", "handling"));
        assertFalse(EventStateMachine.canDutyClose("sos", "pending_review"));
        assertTrue(EventStateMachine.canReviewerClose("sos", "pending_review"));
        assertFalse(EventStateMachine.canReviewerClose("sos", "handling"));
        assertTrue(EventStateMachine.canDutyClose("geofence", "handling"));
        assertFalse(EventStateMachine.canDutyClose("geofence", "claimed"));
    }

    @Test
    void reopenOnlyFromClosed() {
        assertTrue(EventStateMachine.canReopen("closed"));
        assertFalse(EventStateMachine.canReopen("open"));
        assertTrue(EventStateMachine.canTransfer("claimed"));
        assertFalse(EventStateMachine.canTransfer("open"));
    }
}
