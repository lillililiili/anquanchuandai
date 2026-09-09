package com.ruoyi.melhat;

import com.ruoyi.wear.work.WorkTaskStateMachine;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WorkTaskStateMachineTest {

    @Test
    void readyNeedsMemberAndWindow() {
        assertEquals("draft", WorkTaskStateMachine.initialStatus(false, true));
        assertEquals("draft", WorkTaskStateMachine.initialStatus(true, false));
        assertEquals("ready", WorkTaskStateMachine.initialStatus(true, true));
    }

    @Test
    void startPauseEndTransitions() {
        assertTrue(WorkTaskStateMachine.canStart("ready"));
        assertTrue(WorkTaskStateMachine.canStart("paused"));
        assertFalse(WorkTaskStateMachine.canStart("in_progress"));
        assertTrue(WorkTaskStateMachine.canPause("in_progress"));
        assertTrue(WorkTaskStateMachine.canEnd("in_progress"));
        assertTrue(WorkTaskStateMachine.canEnd("paused"));
        assertTrue(WorkTaskStateMachine.canEnd("ready"));
        assertFalse(WorkTaskStateMachine.canEnd("ended"));
        assertFalse(WorkTaskStateMachine.canEditMembers("ended"));
        assertTrue(WorkTaskStateMachine.isMatchWindow("paused"));
        assertFalse(WorkTaskStateMachine.isMatchWindow("ready"));
    }

    @Test
    void missingTicketIsUnverifiedNotViolation() {
        assertEquals("none", WorkTaskStateMachine.ticketStatus(false, null));
        assertEquals("unverified", WorkTaskStateMachine.ticketStatus(true, null));
        assertEquals("unverified", WorkTaskStateMachine.ticketStatus(true, "  "));
        assertEquals("provided", WorkTaskStateMachine.ticketStatus(true, "T-1"));
    }
}
