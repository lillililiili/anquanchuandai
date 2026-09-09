package com.ruoyi.melhat;

import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.work.EquipmentCheck;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class EquipmentCheckTest {

    @Test
    void missingUnknownAndHelmetOk() {
        assertEquals(EquipmentCheck.MISSING, EquipmentCheck.result("helmet", false, TelemetryFreshness.OK));
        assertEquals(EquipmentCheck.OK, EquipmentCheck.result("helmet", true, TelemetryFreshness.OK));
        assertEquals(EquipmentCheck.UNKNOWN, EquipmentCheck.result("helmet", true, TelemetryFreshness.UNKNOWN));
        assertEquals(EquipmentCheck.UNKNOWN, EquipmentCheck.result("helmet", true, TelemetryFreshness.STALE));
        assertEquals(EquipmentCheck.UNKNOWN, EquipmentCheck.result("belt", true, TelemetryFreshness.OK));
        assertEquals(EquipmentCheck.MISSING, EquipmentCheck.result("belt", false, TelemetryFreshness.OK));
    }
}
