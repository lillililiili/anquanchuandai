package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.utils.spring.SpringUtils;
import com.ruoyi.common.websocket.WebSocketConfig;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.websocket.servlet.WebSocketServletAutoConfiguration;
import org.springframework.boot.autoconfigure.web.servlet.ServletWebServerFactoryAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.boot.web.servlet.context.AnnotationConfigServletWebServerApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.core.env.MapPropertySource;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.DispatcherServlet;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import javax.websocket.ClientEndpointConfig;
import javax.websocket.ContainerProvider;
import javax.websocket.Endpoint;
import javax.websocket.EndpointConfig;
import javax.websocket.Session;
import javax.websocket.WebSocketContainer;
import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Real loopback HTTP/WebSocket handshake; no database, vendor cloud, or physical helmet is contacted. */
class DirectHelmetNetworkTest {
    @Test void springExporterServesFirmwareConfigAndAuthenticatesDeviceWebSocket() throws Exception {
        AnnotationConfigServletWebServerApplicationContext context = new AnnotationConfigServletWebServerApplicationContext();
        Map<String, Object> settings = new HashMap<>();
        settings.put("melhat.direct.enabled", "true");
        settings.put("melhat.direct.public-base-url", "http://127.0.0.1:18084");
        settings.put("server.port", "0");
        settings.put("server.address", "127.0.0.1");
        context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("direct-test", settings));
        context.register(NetworkApp.class);
        WebSocketContainer client = ContainerProvider.getWebSocketContainer();
        try {
            context.refresh();
            int port = context.getWebServer().getPort();
            JSONObject config = JSONObject.parseObject(new RestTemplate().getForObject(
                    "http://127.0.0.1:" + port + "/api/melhat/config/index.php?ctl=config&act=get_config&device_id=integration-helmet",
                    String.class));
            assertTrue(config.getBooleanValue("status"));
            assertTrue(config.getJSONObject("data").get("config") instanceof String);
            BlockingQueue<String> messages = new LinkedBlockingQueue<>();
            Endpoint endpoint = new Endpoint() {
                @Override public void onOpen(Session session, EndpointConfig ignored) {
                    session.addMessageHandler(String.class, messages::add);
                }
            };
            try (Session session = client.connectToServer(endpoint, ClientEndpointConfig.Builder.create().build(),
                    URI.create("ws://127.0.0.1:" + port + "/wsHat"))) {
                session.getBasicRemote().sendText("{\"act\":\"ca_report_location\",\"bat_l\":50}");
                assertFalse(reply(messages).getBooleanValue("status"));
                session.getBasicRemote().sendText("{\"act\":\"ca_login\",\"device_id\":\"integration-helmet\"}");
                JSONObject login = reply(messages);
                assertTrue(login.getBooleanValue("status"));
                assertEquals("integration-helmet", login.getJSONObject("data").getString("device_id"));
                session.getBasicRemote().sendText("{\"act\":\"ca_report_location\",\"x_point\":35.46,\"y_point\":112.57,\"bat_l\":67,\"is_weared\":2}");
                JSONObject report = reply(messages);
                assertTrue(report.getBooleanValue("status"));
                assertEquals("ca_report_location", report.getString("cmd"));
                JSONObject status = context.getBean(DirectHelmetGateway.class).status("integration-helmet");
                assertTrue(status.getBooleanValue("online"));
                assertEquals(67, status.getIntValue("battery"));
                assertEquals("35.46", status.getString("latitude"));
                verify(context.getBean(DirectHelmetTelemetryService.class)).receive(any(SafetyHatInfo.class), any(DirectHelmetMessage.class));
            }
        } finally {
            context.close();
            if (client instanceof org.apache.tomcat.websocket.WsWebSocketContainer)
                ((org.apache.tomcat.websocket.WsWebSocketContainer) client).destroy();
        }
    }

    private static JSONObject reply(BlockingQueue<String> messages) throws InterruptedException {
        String message = messages.poll(5, TimeUnit.SECONDS);
        assertNotNull(message, "No device protocol response within five seconds");
        return JSONObject.parseObject(message);
    }

    @Configuration
    @EnableWebMvc
    @EnableConfigurationProperties(DirectHelmetProperties.class)
    @Import({ServletWebServerFactoryAutoConfiguration.class, WebSocketServletAutoConfiguration.class,
            WebSocketConfig.class, SpringUtils.class,
            DirectHelmetGateway.class, DirectHelmetWebSocket.class, DirectHelmetConfigController.class})
    static class NetworkApp {
        @Bean DispatcherServlet dispatcherServlet() { return new DispatcherServlet(); }
        @Bean ServletRegistrationBean<DispatcherServlet> dispatcherRegistration(DispatcherServlet dispatcherServlet) {
            return new ServletRegistrationBean<>(dispatcherServlet, "/");
        }
        @Bean DirectHelmetTelemetryService telemetry() {
            DirectHelmetTelemetryService service = mock(DirectHelmetTelemetryService.class);
            SafetyHatInfo hat = new SafetyHatInfo(); hat.setId(1L); hat.setHatNumber("integration-helmet");
            hat.setCreateBy("direct-helmet"); hat.setDelFlag("0"); hat.setBindUserId(2L);
            when(service.registered("integration-helmet")).thenReturn(hat);
            return service;
        }
    }
}
