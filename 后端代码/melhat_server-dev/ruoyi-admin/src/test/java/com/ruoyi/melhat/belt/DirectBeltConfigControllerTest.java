package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectBeltConfigControllerTest {
    @Test void advertisesIndependentDirectoryAndWebsocketWithoutOverwritingAccessorySettings() {
        DirectBeltProperties properties = new DirectBeltProperties(); properties.setEnabled(true);
        properties.setPublicBaseUrl("https://devices.example.test/");
        DirectBeltGateway gateway = mock(DirectBeltGateway.class); when(gateway.supports("belt-test")).thenReturn(true);
        DirectBeltConfigController controller = new DirectBeltConfigController(properties, gateway);
        JSONObject result = controller.configuration("config", "get_config", "belt-test");
        assertTrue(result.getBooleanValue("status"));
        JSONObject data = result.getJSONObject("data"); assertTrue(data.get("config") instanceof String);
        JSONObject config = JSONObject.parseObject(data.getString("config"));
        assertEquals("https://devices.example.test/api/belt/", config.getString("api_url"));
        assertEquals("wss://devices.example.test/wsBelt", config.getString("ws_url"));
        assertFalse(data.containsKey("extra")); assertFalse(data.containsKey("upgrade"));
        assertFalse(controller.configuration("config", "get_config", "unregistered").getBooleanValue("status"));
        assertFalse(controller.deviceRequest("lowcaps", "ca_backup_data", "belt-test").getBooleanValue("status"));
        assertTrue(controller.deviceRequest("config", "get_config", "belt-test").getBooleanValue("status"));
        properties.setWsUrl("http://devices.example.test/wsBelt");
        assertFalse(controller.configuration("config", "get_config", "belt-test").getBooleanValue("status"));
        properties.setEnabled(false);
        assertFalse(controller.configuration("config", "get_config", "belt-test").getBooleanValue("status"));
    }
}
