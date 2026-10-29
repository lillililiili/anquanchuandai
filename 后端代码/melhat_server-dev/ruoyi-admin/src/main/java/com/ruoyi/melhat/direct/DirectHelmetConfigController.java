package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RequestBody;
import java.net.URI;
import java.time.Instant;

/** Firmware bootstrap endpoint, intentionally independent of the user login API. */
@RestController
public class DirectHelmetConfigController {
    private final DirectHelmetProperties properties;
    private final DirectHelmetGateway gateway;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private DirectHelmetOfflineLocations offline;

    public DirectHelmetConfigController(DirectHelmetProperties properties, DirectHelmetGateway gateway) {
        this.properties = properties; this.gateway = gateway;
    }

    @GetMapping({"/api/index.php", "/api/melhat/config/index.php", "/api/melhat/index.php"})
    public JSONObject configuration(@RequestParam("ctl") String ctl, @RequestParam("act") String act,
            @RequestParam(value = "device_id", required = false) String deviceId) {
        if (!properties.isEnabled()) return failure("一体式安全帽直连接入未启用");
        if (!"config".equals(ctl) || !"get_config".equals(act)) return failure("不支持此配置请求");
        if (deviceId == null || !deviceId.matches("[A-Za-z0-9._-]{1,64}") || !gateway.supports(deviceId))
            return failure("设备未预先登记为一体式安全帽");
        String base = properties.getPublicBaseUrl().replaceAll("/+$", "");
        if (!validUrl(base, "http", "https")) return failure("尚未配置设备可访问的服务地址");
        // Firmware appends index.php to api_url; advertise a directory, not a script URL.
        String api = apiDirectory(properties.getApiUrl().isEmpty() ? base + "/api/" : properties.getApiUrl());
        String ws = properties.getWsUrl().isEmpty()
                ? base.replaceFirst("^http", "ws") + "/wsHat" : properties.getWsUrl();
        if (!validUrl(api, "http", "https") || !validUrl(ws, "ws", "wss"))
            return failure("设备服务地址配置无效");
        JSONObject config = new JSONObject();
        config.put("api_url", api); config.put("ws_url", ws);
        JSONObject data = new JSONObject();
        // This string encoding is required by the firmware protocol.
        data.put("config", config.toJSONString());
        data.put("time", Instant.now().getEpochSecond());
        // Omit extra to preserve the helmet's accessory configuration. M6811 firmware
        // skips absent extra, but an empty watch_mac overwrites its current wristband binding.
        JSONObject result = new JSONObject();
        result.put("status", true); result.put("msg", "获取成功");
        result.put("msg_code", "GetSucc"); result.put("data", data);
        return result;
    }

    /** Files are handled by the dedicated authenticated media gateway; backup points are committed here. */
    @PostMapping({"/api/index.php", "/api/melhat/index.php"})
    public JSONObject deviceRequest(@RequestParam("ctl") String ctl, @RequestParam("act") String act,@RequestBody(required=false) JSONObject body) {
        if(properties.isEnabled()&&"lowcaps".equals(ctl)&&"ca_backup_data".equals(act)&&offline!=null){
            String deviceId=body==null?null:body.getString("device_id");
            if(deviceId==null||!deviceId.matches("[A-Za-z0-9._-]{1,64}")||!gateway.supports(deviceId))return failure("设备未预先登记为一体式安全帽");
            if(!(body.get("data") instanceof String))return failure("离线轨迹格式无效");
            try{int count=offline.receive(deviceId,body.getString("data"));return HelmetMediaService.obj("status",true,"msg","保存成功","msg_code","SaveSucc","data",HelmetMediaService.obj("accepted",count));}
            catch(RuntimeException error){return failure("离线轨迹未保存，请保留原文件后重试");}
        }
        JSONObject result = failure(properties.isEnabled()
                ? "当前仅支持 WebSocket 登录、状态定位和告警；此接口未启用"
                : "一体式安全帽直连接入未启用");
        result.put("msg_code", "Unsupported");
        return result;
    }
    public JSONObject deviceRequest(String ctl,String act){return deviceRequest(ctl,act,null);}

    private static String apiDirectory(String value) {
        String directory = value.replaceAll("/+$", "");
        if (directory.endsWith("/index.php")) directory = directory.substring(0, directory.length() - "index.php".length());
        return directory.endsWith("/") ? directory : directory + "/";
    }

    private static boolean validUrl(String value, String first, String second) {
        try {
            URI uri = URI.create(value);
            return (first.equals(uri.getScheme()) || second.equals(uri.getScheme()))
                    && uri.getHost() != null && uri.getUserInfo() == null
                    && uri.getQuery() == null && uri.getFragment() == null;
        } catch (IllegalArgumentException error) { return false; }
    }

    private static JSONObject failure(String message) {
        JSONObject result = new JSONObject();
        result.put("status", false); result.put("msg", message); result.put("msg_code", "GetError");
        return result;
    }
}
