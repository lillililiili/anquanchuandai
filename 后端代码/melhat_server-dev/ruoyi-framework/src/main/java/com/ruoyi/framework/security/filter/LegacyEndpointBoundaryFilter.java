package com.ruoyi.framework.security.filter;

import org.springframework.web.filter.OncePerRequestFilter;
import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** Retired human APIs must never bypass the authoritative Wearable station grants. */
public final class LegacyEndpointBoundaryFilter extends OncePerRequestFilter {
    public static final String CALLBACK_AUTHENTICATED = "legacy.callback.authenticated";
    public static final String CALLBACK_HEADER = "X-Melhat-Callback-Key";
    private static final Set<String> DEVICE_BOOTSTRAP = new HashSet<>(Arrays.asList(
            "/api/melhat/index.php", "/api/melhat/config/index.php"));
    private static final Set<String> CALLBACKS = new HashSet<>(Arrays.asList(
            "/ext/helmetAlarm", "/ext/notifyGnss", "/ext/sosCall"));
    private final boolean callbacksEnabled;
    private final String callbackKey;

    public LegacyEndpointBoundaryFilter(boolean callbacksEnabled, String callbackKey) {
        this.callbacksEnabled = callbacksEnabled;
        this.callbackKey = callbackKey == null ? "" : callbackKey;
    }

    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        String raw = request.getRequestURI().substring(request.getContextPath().length());
        String path;
        try {
            // Match what a servlet container may decode, including encoded names and path parameters.
            path = URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8");
        } catch (IllegalArgumentException ex) { reject(response, 400, "INVALID_PATH"); return; }
        if (path.indexOf('%') >= 0 || path.indexOf('\\') >= 0 || path.contains("//")
                || path.contains("/../") || path.contains("/./") || path.endsWith("/..") || path.endsWith("/.")) {
            reject(response, 400, "INVALID_PATH"); return;
        }
        path = path.replaceAll(";[^/]*", "");
        while (path.length() > 1 && path.endsWith("/")) path = path.substring(0, path.length() - 1);
        if (retired(path)) { reject(response, 410, "LEGACY_ENDPOINT_RETIRED"); return; }
        if (under(path, "/ext")) {
            if (!callbacksEnabled || callbackKey.length() < 32 || !CALLBACKS.contains(path)) {
                reject(response, 410, "LEGACY_CALLBACK_DISABLED"); return;
            }
            if (!"POST".equals(request.getMethod())) { reject(response, 405, "METHOD_NOT_ALLOWED"); return; }
            String supplied = request.getHeader(CALLBACK_HEADER);
            if (supplied == null || !MessageDigest.isEqual(callbackKey.getBytes(StandardCharsets.UTF_8),
                    supplied.getBytes(StandardCharsets.UTF_8))) {
                reject(response, 401, "CALLBACK_AUTHENTICATION_REQUIRED"); return;
            }
            request.setAttribute(CALLBACK_AUTHENTICATED, Boolean.TRUE);
        }
        chain.doFilter(request, response);
    }

    private static boolean retired(String path) {
        for (String prefix : Arrays.asList("/hat", "/ws", "/test", "/test2", "/system", "/monitor",
                "/common", "/profile", "/aip", "/modeler", "/activiti", "/todo", "/tool", "/druid"))
            if (under(path, prefix)) return true;
        if (under(path, "/api/melhat") && !DEVICE_BOOTSTRAP.contains(path)) return true;
        return Arrays.asList("/login", "/logout", "/register", "/captchaImage", "/getInfo", "/getRouters").contains(path);
    }
    private static boolean under(String path, String prefix) { return path.equals(prefix) || path.startsWith(prefix + "/"); }
    private static void reject(HttpServletResponse response, int code, String error) throws IOException {
        response.setStatus(code);
        response.setHeader("Cache-Control", "no-store");
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write("{\"code\":" + code + ",\"errorCode\":\"" + error
                + "\",\"message\":\"此入口不可用，请使用已授权的智能穿戴业务接口\"}");
    }
}
