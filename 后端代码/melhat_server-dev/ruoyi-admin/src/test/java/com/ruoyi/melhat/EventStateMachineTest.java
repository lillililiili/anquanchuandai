package com.ruoyi.melhat;

import com.ruoyi.wear.event.EventStateMachine;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EventStateMachineTest {

    @Test void onlyKnownProtocolTypesAreAccepted() {
        assertTrue(EventStateMachine.isKnownType("fall"));
        assertTrue(EventStateMachine.isKnownType("sos"));
        assertFalse(EventStateMachine.isKnownType("invented_detection"));
    }

    @Test
    void claimOnlyFromOpen() {
        assertFalse(EventStateMachine.canClaim("open"));
        assertFalse(EventStateMachine.canClaim("claimed"));
        assertFalse(EventStateMachine.canClaim("closed"));
    }

    @Test
    void handleMovesHighRiskToReview() {
        assertEquals("pending_review", EventStateMachine.handleTarget("emergency"));
        assertEquals("verified", EventStateMachine.handleTarget("abnormal"));
        assertTrue(EventStateMachine.canHandle("claimed"));
        assertTrue(EventStateMachine.canHandle("handling"));
        assertTrue(EventStateMachine.canHandle("open"));
        assertFalse(EventStateMachine.canHandle("pending_review"));
    }

    @Test
    void dutyCannotCloseHighRisk() {
        assertFalse(EventStateMachine.canDutyClose("sos", "handling"));
        assertFalse(EventStateMachine.canDutyClose("sos", "pending_review"));
        assertTrue(EventStateMachine.canReviewerClose("emergency", "pending_review"));
        assertFalse(EventStateMachine.canReviewerClose("emergency", "handling"));
        assertFalse(EventStateMachine.canDutyClose("geofence", "handling"));
        assertFalse(EventStateMachine.canDutyClose("geofence", "claimed"));
    }

    @Test
    void reopenOnlyFromClosed() {
        assertTrue(EventStateMachine.canReopen("closed"));
        assertFalse(EventStateMachine.canReopen("open"));
        assertFalse(EventStateMachine.canTransfer("claimed"));
        assertFalse(EventStateMachine.canTransfer("open"));
    }
}
