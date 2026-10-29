package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.stereotype.Component;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.HttpURLConnection;
import java.net.URI;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.UUID;

@Component
public class HelmetCloudClient {
    private final HelmetMediaProperties properties;
    public HelmetCloudClient(HelmetMediaProperties properties) { this.properties = properties; }
    public boolean configured() {
        try {
            URI uri = URI.create(properties.getControlUrl());
            return properties.isEnabled() && "https".equals(uri.getScheme()) && uri.getHost() != null
                    && uri.getUserInfo() == null && uri.getQuery() == null && uri.getFragment() == null
                    && properties.getSharedKey().length() >= 32;
        } catch (RuntimeException error) { return false; }
    }
    public JSONObject request(String method, String path, JSONObject body) {
        if (!configured()) throw new IllegalStateException("自有云媒体服务尚未配置");
        if (!path.matches("/[A-Za-z0-9_/?=&.-]*") || path.contains(".."))
            throw new IllegalArgumentException("媒体请求路径无效");
        HttpURLConnection connection = null;
        try {
            URI uri = URI.create(properties.getControlUrl() + path);
            byte[] bytes = body == null ? new byte[0] : body.toJSONString().getBytes(StandardCharsets.UTF_8);
            String time = String.valueOf(Instant.now().getEpochSecond());
            String nonce = UUID.randomUUID().toString();
            String signedPath = uri.getRawPath() + (uri.getRawQuery() == null ? "" : "?" + uri.getRawQuery());
            connection = (HttpURLConnection) uri.toURL().openConnection();
            connection.setRequestMethod(method); connection.setConnectTimeout(5000); connection.setReadTimeout(20000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("X-Media-Time", time);
            connection.setRequestProperty("X-Media-Nonce", nonce);
            connection.setRequestProperty("X-Media-Signature", signature(properties.getSharedKey(), time, nonce, method, signedPath, bytes));
            if (body != null) {
                connection.setDoOutput(true); connection.setRequestProperty("Content-Type", "application/json");
                connection.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream out = connection.getOutputStream()) { out.write(bytes); }
            }
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) throw new IOException("cloud status " + status);
            try (InputStream in = connection.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] block = new byte[8192]; int n;
                while ((n = in.read(block)) != -1) {
                    if (out.size() + n > 4 * 1024 * 1024) throw new IOException("response too large");
                    out.write(block, 0, n);
                }
                JSONObject result = JSON.parseObject(new String(out.toByteArray(), StandardCharsets.UTF_8));
                if (result == null || result.getIntValue("code") != 200 || result.getJSONObject("data") == null)
                    throw new IOException("invalid cloud response");
                return result.getJSONObject("data");
            }
        } catch (Exception error) {
            // Do not surface credentials, signed media URLs, server bodies or exception messages.
            throw new IllegalStateException("云媒体服务请求未确认，请查看操作记录后重试");
        } finally { if (connection != null) connection.disconnect(); }
    }
    public static String signature(String key, String time, String nonce, String method, String path, byte[] body) throws Exception {
        String payload = time + "\n" + nonce + "\n" + method + "\n" + path + "\n" + hex(MessageDigest.getInstance("SHA-256").digest(body));
        Mac mac = Mac.getInstance("HmacSHA256"); mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return hex(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
    }
    private static String hex(byte[] bytes) { StringBuilder out = new StringBuilder(); for (byte b : bytes) out.append(String.format("%02x", b & 255)); return out.toString(); }
}
