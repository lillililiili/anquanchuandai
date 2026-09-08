package com.ruoyi.system.websocket;

import com.ruoyi.common.exception.ServiceException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import javax.websocket.*;
import javax.websocket.server.PathParam;
import javax.websocket.server.ServerEndpoint;
import java.io.IOException;
import java.util.Enumeration;
import java.util.concurrent.ConcurrentHashMap;

/**
 * @author gyz
 * @date 2023/7/6 15:32
 */
@Slf4j
@Component
@ServerEndpoint("/ws/{client}/{type}")
public class WebSocketSever {

    // 当前会话对应的 key，方便在 onClose 中移除
    private String sessionKey;
    // session集合,存放对应的session
    public static ConcurrentHashMap<String, Session> sessionPool = new ConcurrentHashMap<>();


    static {
        log.info("========== WebSocketSever 类已加载 ==========");
    }
    /**
     * 建立WebSocket连接
     *
     * @param session
     */
    @OnOpen
    public void onOpen(Session session, @PathParam(value = "client") String client, @PathParam(value = "type") String type) {
        log.info("WebSocket建立连接中,连接用户ID：{}", client);
//            session.setMaxIdleTimeout();
        Session historySession = sessionPool.get(client);

        // 建立连接
        this.sessionKey = client + "_" + type;//type=1PC、 2 APP
        sessionPool.put(this.sessionKey, session);
        log.info("{}已连接,当前在线人数为：{}", this.sessionKey, sessionPool.size());

    }


    /**
     * 发生错误
     */
    @OnError
    public void onError(Session session, Throwable error) {
        log.error("WebSocket 发生错误: sessionKey={}, 错误信息={}",
                sessionKey, error.getMessage(), error);
    }

    /**
     * 连接关闭
     */
    @OnClose
    public void onClose(Session session, CloseReason closeReason) {
        if (sessionKey != null) {
            sessionPool.remove(sessionKey);
            log.info("WebSocket 连接关闭: sessionKey={}, 原因={}, 当前在线数={}",
                    sessionKey, closeReason.getReasonPhrase(), sessionPool.size());
        } else {
            log.warn("连接关闭时 sessionKey 为空，无法移除");
        }
    }

    /**
     * 接收客户端消息
     *
     * @param message 接收的消息
     */
    @OnMessage
    public void onMessage(String message, Session session) {
        log.info("收到消息,sessionKey={},：{}", this.sessionKey, message);

        try {
            if("ping".equals(message)){
                session.getBasicRemote().sendText("pong");
            }
        } catch (IOException e) {
            throw new ServiceException("消息发送失败"+ e);
        }
    }

    /**
     * 推送消息到指定用户
     *
     * @param sessionKey 用户client
     * @param message    发送的消息
     */
    public static void sendMessageByUser(String sessionKey, String message) {
        log.info("sessionKey=" + sessionKey + ",推送内容：" + message);
        Session session = sessionPool.get(sessionKey);
        try {
            if (session != null && session.isOpen()) {
                session.getBasicRemote().sendText(message);
            } else {
                log.error("目标客户端不在线或会话已关闭,sessionKey={}", sessionKey);
            }
        } catch (IOException e) {
            log.error("推送消息到指定用户发生错误：" + e.getMessage(), e);
        }
    }

    /**
     * 群发消息
     *
     * @param message 发送的消息
     */
    public static void sendAllMessage(String message) {
        log.info("群发消息：{},{}", sessionPool.keys(), message);
        for (Session session : sessionPool.values()) {
            try {
                if (session != null && session.isOpen()) {
                    session.getBasicRemote().sendText(message);
                } else {
                    log.error("会话已关闭");
                }
            } catch (IOException e) {
                log.error("群发消息发生错误：" + e.getMessage(), e);
            }
        }
    }

    public static void sendAllPcMessage(String message) {
        log.info("群发消息：{},{}", sessionPool.keys(), message);
        Enumeration<String> keys = sessionPool.keys();
        while (keys.hasMoreElements()) {
            String k = keys.nextElement();
            if (k.endsWith("_1")) {
                try {
                    Session session = sessionPool.get(k);
                    if (session != null && session.isOpen()) {
                        session.getBasicRemote().sendText(message);
                    } else {
                        log.error("会话已关闭,sessionKey={}", k);
                    }
                } catch (IOException e) {
                    log.error("群发消息发生错误：" + e.getMessage(), e);
                }
            }
        }
    }


}