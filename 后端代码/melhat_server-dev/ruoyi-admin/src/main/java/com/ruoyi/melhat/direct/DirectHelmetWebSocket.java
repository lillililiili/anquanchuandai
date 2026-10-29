package com.ruoyi.melhat.direct;

import com.ruoyi.common.utils.spring.SpringUtils;
import org.springframework.stereotype.Component;
import javax.websocket.OnClose;
import javax.websocket.OnError;
import javax.websocket.OnMessage;
import javax.websocket.OnOpen;
import javax.websocket.Session;
import javax.websocket.server.ServerEndpoint;
import java.io.IOException;

/** Manufacturer device endpoint. User-facing WebSockets remain separate. */
@Component
@ServerEndpoint("/wsHat")
public class DirectHelmetWebSocket {
    private DirectHelmetGateway gateway() { return SpringUtils.getBean(DirectHelmetGateway.class); }

    @OnOpen public void open(Session session) {
        session.setMaxTextMessageBufferSize(65536);
        session.setMaxIdleTimeout(gateway().idleTimeoutMillis());
        if (!gateway().isEnabled()) DirectHelmetGateway.close(session, "设备直连接入未启用");
    }

    @OnMessage public void message(Session session, String message) throws IOException {
        String response = gateway().receive(session, message).toJSONString();
        if (session.isOpen()) synchronized (session) { session.getBasicRemote().sendText(response); }
    }

    @OnClose public void close(Session session) { gateway().disconnected(session); }
    @OnError public void error(Session session, Throwable error) {
        if (session != null) {
            gateway().disconnected(session);
            DirectHelmetGateway.close(session, "设备连接异常");
        }
    }
}
