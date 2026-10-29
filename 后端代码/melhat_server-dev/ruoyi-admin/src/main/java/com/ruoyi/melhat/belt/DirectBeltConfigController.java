package com.ruoyi.melhat.belt;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.*;
import java.net.URI;
import java.time.Instant;

/** Dedicated belt directory avoids routing belt messages into the helmet adapter. */
@RestController
public class DirectBeltConfigController {
    private final DirectBeltProperties properties;
    private final DirectBeltGateway gateway;
    public DirectBeltConfigController(DirectBeltProperties properties, DirectBeltGateway gateway) {
        this.properties = properties; this.gateway = gateway;
    }
    @GetMapping({"/api/belt/index.php", "/api/belt/config/index.php"})
    public JSONObject configuration(@RequestParam("ctl") String ctl, @RequestParam("act") String act,
            @RequestParam(value = "device_id", required = false) String deviceId) {
        if (!properties.isEnabled()) return failure("安全带直连接入未启用");
        if (!"config".equals(ctl) || !"get_config".equals(act)) return failure("不支持此配置请求");
        if (deviceId == null || !deviceId.matches("[A-Za-z0-9._-]{1,64}") || !gateway.supports(deviceId))
            return failure("设备未预先登记为直连安全带");
        String base = properties.getPublicBaseUrl().replaceAll("/+$", "");
        if (!validUrl(base, "http", "https")) return failure("尚未配置设备可访问的服务地址");
        String api = directory(properties.getApiUrl().isEmpty() ? base + "/api/belt/" : properties.getApiUrl());
        String ws = properties.getWsUrl().isEmpty() ? base.replaceFirst("^http", "ws") + "/wsBelt" : properties.getWsUrl();
        if (!validUrl(api, "http", "https") || !validUrl(ws, "ws", "wss")) return failure("设备服务地址配置无效");
        JSONObject config = new JSONObject(); config.put("api_url", api); config.put("ws_url", ws);
        JSONObject data = new JSONObject(); data.put("config", config.toJSONString()); data.put("time", Instant.now().getEpochSecond());
        JSONObject result = new JSONObject();
        result.put("status", true); result.put("msg", "获取成功"); result.put("msg_code", "GetSucc"); result.put("data", data);
        return result;
    }
    @PostMapping("/api/belt/index.php")
    public JSONObject deviceRequest(@RequestParam("ctl") String ctl, @RequestParam("act") String act,
            @RequestParam(value = "device_id", required = false) String deviceId) {
        if ("config".equals(ctl) && "get_config".equals(act)) return configuration(ctl, act, deviceId);
        JSONObject result = failure(properties.isEnabled()
                ? "当前支持 WebSocket 实时数据和告警；离线补传及媒体上传尚未接入" : "安全带直连接入未启用");
        result.put("msg_code", "Unsupported");
        return result;
    }
    private static String directory(String value) {
        String result = value.replaceAll("/+$", "");
        if (result.endsWith("/index.php")) result = result.substring(0, result.length() - "index.php".length());
        return result.endsWith("/") ? result : result + "/";
    }
    private static boolean validUrl(String value, String first, String second) {
        try {
            URI uri = URI.create(value);
            return (first.equals(uri.getScheme()) || second.equals(uri.getScheme())) && uri.getHost() != null
                    && uri.getUserInfo() == null && uri.getQuery() == null && uri.getFragment() == null;
        } catch (IllegalArgumentException error) { return false; }
    }
    private static JSONObject failure(String message) {
        JSONObject result = new JSONObject(); result.put("status", false); result.put("msg", message); result.put("msg_code", "GetError");
        return result;
    }
}
