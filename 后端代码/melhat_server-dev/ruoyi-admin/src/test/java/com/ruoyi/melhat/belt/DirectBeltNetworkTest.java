package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.utils.spring.SpringUtils;
import com.ruoyi.common.websocket.WebSocketConfig;
import com.ruoyi.guardian.DirectBeltTelemetryService;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.websocket.servlet.WebSocketServletAutoConfiguration;
import org.springframework.boot.autoconfigure.web.servlet.ServletWebServerFactoryAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.boot.web.servlet.context.AnnotationConfigServletWebServerApplicationContext;
import org.springframework.context.annotation.*;
import org.springframework.core.env.MapPropertySource;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.DispatcherServlet;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import javax.websocket.*;
import java.net.URI;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Exercises actual HTTP routing and a device WebSocket, without contacting a real device. */
class DirectBeltNetworkTest {
    @Test void beltCanBootstrapLoginReportAndSendAnAlarmOverTheWire() throws Exception {
        AnnotationConfigServletWebServerApplicationContext context = new AnnotationConfigServletWebServerApplicationContext();
        Map<String, Object> settings = new HashMap<>();
        settings.put("melhat.belt.enabled", "true");
        settings.put("melhat.belt.public-base-url", "http://127.0.0.1:18084");
        settings.put("server.port", "0"); settings.put("server.address", "127.0.0.1");
        context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("belt-test", settings));
        context.register(NetworkApp.class);
        WebSocketContainer client = ContainerProvider.getWebSocketContainer();
        try {
            context.refresh(); int port = context.getWebServer().getPort();
            JSONObject config = JSONObject.parseObject(new RestTemplate().getForObject("http://127.0.0.1:" + port
                    + "/api/belt/index.php?ctl=config&act=get_config&device_id=belt-test", String.class));
            assertTrue(config.getBooleanValue("status"));
            assertEquals("ws://127.0.0.1:18084/wsBelt", JSONObject.parseObject(config.getJSONObject("data").getString("config")).getString("ws_url"));
            BlockingQueue<String> messages = new LinkedBlockingQueue<>();
            Endpoint endpoint = new Endpoint() {
                @Override public void onOpen(Session session, EndpointConfig ignored) { session.addMessageHandler(String.class, messages::add); }
            };
            try (Session session = client.connectToServer(endpoint, ClientEndpointConfig.Builder.create().build(), URI.create("ws://127.0.0.1:" + port + "/wsBelt"))) {
                session.getBasicRemote().sendText("{\"act\":\"ca_login\",\"device_id\":\"unknown\"}");
                assertFalse(reply(messages).getBooleanValue("status"));
                session.getBasicRemote().sendText("{\"act\":\"ca_login\",\"device_id\":\"belt-test\",\"type\":9}");
                assertTrue(reply(messages).getBooleanValue("status"));
                session.getBasicRemote().sendText("{\"act\":\"ca_report_location\",\"imei\":\"belt-test\",\"user_id\":\"spoofed\",\"bat_l\":86,\"is_weared\":0,\"hanger_a_status\":0,\"hanger_b_status\":0,\"Relative_altitude\":0,\"Altitude\":53.59,\"x_point\":0,\"y_point\":0}");
                JSONObject report = reply(messages); assertTrue(report.getBooleanValue("status")); assertEquals(0, report.getIntValue("report_time"));
                JSONObject state = context.getBean(DirectBeltGateway.class).status("belt-test");
                assertTrue(state.getBooleanValue("online")); assertEquals(86, state.getIntValue("battery"));
                assertNull(state.get("worn")); assertNull(state.get("hookAEngaged")); assertNull(state.get("latitude"));
                session.getBasicRemote().sendText("{\"act\":\"ca_sos\",\"device_id\":\"belt-test\",\"type\":\"6\",\"timestamp\":\"1791511557\"}");
                assertTrue(reply(messages).getBooleanValue("status"));
                verify(context.getBean(DirectBeltTelemetryService.class)).receive(eq("belt-test"), any(), eq("6"), anyString(), eq(false));
            }
        } finally {
            context.close();
            if (client instanceof org.apache.tomcat.websocket.WsWebSocketContainer) ((org.apache.tomcat.websocket.WsWebSocketContainer) client).destroy();
        }
    }
    private static JSONObject reply(BlockingQueue<String> messages) throws InterruptedException {
        String message = messages.poll(5, TimeUnit.SECONDS); assertNotNull(message, "No device response within five seconds");
        return JSONObject.parseObject(message);
    }
    @Configuration @EnableWebMvc @EnableConfigurationProperties(DirectBeltProperties.class)
    @Import({ServletWebServerFactoryAutoConfiguration.class, WebSocketServletAutoConfiguration.class,
            WebSocketConfig.class, SpringUtils.class, DirectBeltGateway.class, DirectBeltWebSocket.class, DirectBeltConfigController.class})
    static class NetworkApp {
        @Bean DispatcherServlet dispatcherServlet() { return new DispatcherServlet(); }
        @Bean ServletRegistrationBean<DispatcherServlet> dispatcherRegistration(DispatcherServlet dispatcher) { return new ServletRegistrationBean<>(dispatcher, "/"); }
        @Bean DirectBeltTelemetryService telemetry() {
            DirectBeltTelemetryService service = mock(DirectBeltTelemetryService.class);
            JSONObject record = new JSONObject(); record.put("deviceId", "belt-test"); record.put("userId", "12"); record.put("userName", "测试人员");
            when(service.registered("belt-test")).thenReturn(record); return service;
        }
    }
}
