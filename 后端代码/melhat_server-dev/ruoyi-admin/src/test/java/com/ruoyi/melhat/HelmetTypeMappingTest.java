package com.ruoyi.melhat;

import com.ruoyi.wear.helmet.HelmetTypeMapping;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class HelmetTypeMappingTest {

    @Test
    void mapsVendorTypesToPlatformEvents() {
        assertEquals("sos", HelmetTypeMapping.eventType("/ext/sosCall", null));
        assertEquals("fall", HelmetTypeMapping.eventType("/ext/helmetAlarm", "fall"));
        assertEquals("realtime", HelmetTypeMapping.eventType("/ext/helmetAlarm", "silent"));
        assertEquals("realtime", HelmetTypeMapping.eventType("/ext/helmetAlarm", "removal"));
        assertEquals("realtime", HelmetTypeMapping.eventType("/ext/helmetAlarm", "proximity"));
        assertNull(HelmetTypeMapping.eventType("/ext/notifyGnss", null));
        assertNull(HelmetTypeMapping.eventType("/ext/helmetAlarm", "unknown"));
    }

    @Test
    void messageKeyIsStableForDedupe() {
        assertEquals("MH-1|sos|2026-09-09 12:00:00",
                HelmetTypeMapping.messageKey("/ext/sosCall", "MH-1", null, null, "2026-09-09 12:00:00"));
        assertEquals("MH-1|fall|2026-09-09 12:00:00",
                HelmetTypeMapping.messageKey("/ext/helmetAlarm", "MH-1", "fall", "2026-09-09 12:00:00", null));
    }
}
