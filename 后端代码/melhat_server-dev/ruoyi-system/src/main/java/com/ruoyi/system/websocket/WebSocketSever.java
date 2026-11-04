package com.ruoyi.system.websocket;

import javax.websocket.CloseReason;
import javax.websocket.OnClose;
import javax.websocket.OnError;
import javax.websocket.OnMessage;
import javax.websocket.OnOpen;
import javax.websocket.Session;
import javax.websocket.server.PathParam;
import java.io.IOException;
import java.util.concurrent.ConcurrentHashMap;

/** Obsolete unscoped human socket. Device /wsHat and /wsBelt are separate endpoints. */
public class WebSocketSever {
    /** Retired ABI shim only. No production handler stores or reads sessions here. */
    @Deprecated public static ConcurrentHashMap<String, Session> sessionPool = new ConcurrentHashMap<>();

    public void onOpen(Session session) throws IOException {
        // Also fail closed if a container dispatches a WebSocket without the servlet filter.
        session.close(new CloseReason(CloseReason.CloseCodes.VIOLATED_POLICY,
                "Legacy endpoint retired; use authenticated Guardian events"));
    }

    /** Preserve the old descriptor for already-compiled callers; never register a client. */
    @Deprecated @OnOpen public void onOpen(Session session, @PathParam("client") String client, @PathParam("type") String type) {
        reject(session);
    }
    @Deprecated @OnMessage public void onMessage(String message, Session session) { reject(session); }
    @Deprecated @OnClose public void onClose(Session session, CloseReason reason) { }
    @Deprecated @OnError public void onError(Session session, Throwable error) { }

    /** Retired broadcast ABI shims. Even an externally populated legacy pool cannot send. */
    @Deprecated public static void sendMessageByUser(String sessionKey, String message) { }
    @Deprecated public static void sendAllMessage(String message) { }
    @Deprecated public static void sendAllPcMessage(String message) { }

    private void reject(Session session) {
        try { onOpen(session); }
        catch (IOException error) { throw new IllegalStateException("Retired WebSocket could not close", error); }
    }
}
