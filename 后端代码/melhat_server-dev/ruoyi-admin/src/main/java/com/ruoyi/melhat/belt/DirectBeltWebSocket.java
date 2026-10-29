package com.ruoyi.melhat.belt;

import com.ruoyi.common.utils.spring.SpringUtils;
import org.springframework.stereotype.Component;
import javax.websocket.*;
import javax.websocket.server.ServerEndpoint;
import java.io.IOException;

@Component
@ServerEndpoint("/wsBelt")
public class DirectBeltWebSocket {
    private DirectBeltGateway gateway() { return SpringUtils.getBean(DirectBeltGateway.class); }
    @OnOpen public void open(Session session) {
        session.setMaxTextMessageBufferSize(65536);
        session.setMaxIdleTimeout(gateway().idleTimeoutMillis());
        if (!gateway().isEnabled()) DirectBeltGateway.close(session, "安全带直连接入未启用");
    }
    @OnMessage public void message(Session session, String message) throws IOException {
        String response = gateway().receive(session, message).toJSONString();
        if (session.isOpen()) synchronized (session) { session.getBasicRemote().sendText(response); }
    }
    @OnClose public void close(Session session) { gateway().disconnected(session); }
    @OnError public void error(Session session, Throwable ignored) {
        if (session != null) { gateway().disconnected(session); DirectBeltGateway.close(session, "设备连接异常"); }
    }
}
