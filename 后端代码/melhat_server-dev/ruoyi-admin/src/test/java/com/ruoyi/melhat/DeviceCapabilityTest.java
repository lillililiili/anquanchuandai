package com.ruoyi.melhat;

import com.ruoyi.wear.device.DeviceCapability;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DeviceCapabilityTest {

    private static final String CAM =
            "{\"protocolVersion\":\"demo-hat-v1\",\"attributes\":[\"battery\",\"online\",\"gnss\"],\"events\":[\"sos\",\"fall\"],\"actions\":[\"tts\",\"intercom\",\"video\"]}";
    private static final String NOV =
            "{\"protocolVersion\":\"demo-hat-v1\",\"attributes\":[\"battery\",\"online\",\"gnss\"],\"events\":[\"sos\"],\"actions\":[\"tts\"]}";
    private static final String BELT =
            "{\"protocolVersion\":\"demo-belt-v1\",\"attributes\":[\"online\"],\"events\":[\"unbuckled\",\"impact\"],\"actions\":[]}";

    @Test
    void helmetTypeDoesNotImplyVideo() {
        assertTrue(DeviceCapability.supports(CAM, "video"));
        assertFalse(DeviceCapability.supports(NOV, "video"));
        assertFalse(DeviceCapability.supports(BELT, "video"));
        assertFalse(DeviceCapability.supports(NOV, "intercom"));
    }

    @Test
    void emptyOrUnknownIsNotSupported() {
        assertFalse(DeviceCapability.supports(null, "video"));
        assertFalse(DeviceCapability.supports("", "sos"));
        assertFalse(DeviceCapability.supports(CAM, "unknown-feature"));
        assertFalse(DeviceCapability.supports(CAM, null));
    }

    @Test
    void beltHasImpactNotCall() {
        assertTrue(DeviceCapability.supports(BELT, "impact"));
        assertFalse(DeviceCapability.supports(BELT, "tts"));
    }
}
