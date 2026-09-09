package com.ruoyi.melhat;

import com.ruoyi.wear.call.CallStateMachine;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CallStateMachineTest {

    @Test
    void onlyConnectedIsDisplayConnected() {
        assertTrue(CallStateMachine.isConnectedDisplay("connected"));
        assertFalse(CallStateMachine.isConnectedDisplay("offered"));
        assertFalse(CallStateMachine.isConnectedDisplay("requesting"));
        assertFalse(CallStateMachine.isConnectedDisplay("ended"));
    }

    @Test
    void joinOnlyFromOfferedAndTtsNeverHeard() {
        assertTrue(CallStateMachine.canJoin("offered"));
        assertFalse(CallStateMachine.canJoin("connected"));
        assertFalse(CallStateMachine.canJoin("ended"));
        assertTrue(CallStateMachine.isTerminal("ended"));
        assertTrue(CallStateMachine.isTerminal("failed"));
        assertFalse(CallStateMachine.ttsHeard("sent"));
        assertFalse(CallStateMachine.ttsHeard("accepted"));
    }
}
