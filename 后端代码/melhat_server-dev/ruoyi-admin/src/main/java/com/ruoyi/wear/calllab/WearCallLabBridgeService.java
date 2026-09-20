package com.ruoyi.wear.calllab;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import com.alibaba.fastjson2.JSON;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;

/** Business-authenticated entry to the virtual helmet signalling adapter only.
 * Test video is separately authorized; this does not issue production RTC credentials.
 */
@Service
@Profile("!prod")
@ConditionalOnProperty(prefix = "melhat.call-lab", name = "enabled", havingValue = "true", matchIfMissing = false)
public class WearCallLabBridgeService
{
    private static final Pattern CALL_ACTION = Pattern.compile(
            "/calls/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/(accept|reject|end|video|invite)");
    private static final int MAX_REQUEST = 65536;
    private static final int MAX_RESPONSE = 4 * 1024 * 1024;

    /** Only an existing, connected call's connected device can expose test media.
     * Never accept a URL from the client or trust the adapter's streamUrl field. */
    public void videoStream(HttpServletRequest request, HttpServletResponse response, String callId) throws IOException
    {
        HttpURLConnection connection = null;
        try
        {
            assertEnabled();
            if (!CALL_ACTION.matcher("/calls/" + callId + "/video").matches())
                throw new ServiceException("通话不存在", 404);
            String site = authorizeSite(request);
            LoginUser user = siteAccessService.requireLogin();
            requirePermission(user, WearRoleKeys.PERM_CALL_START);
            requireConsole(user);
            String deviceId = request.getParameter("deviceId");
            if (deviceId == null || !deviceId.matches("[1-9][0-9]{0,18}")
                    || request.getParameterMap().size() != 1)
                throw new ServiceException("请选择当前通话中的安全帽", 400);
            String range = request.getHeader("Range");
            if (range != null && !range.matches("bytes=(?:[0-9]+-[0-9]*|-[0-9]+)"))
                throw new ServiceException("不支持的视频读取范围", 416);
            String bearer = request.getHeader("Authorization");
            if (bearer == null || !bearer.matches("Bearer [^\\s]+"))
                throw new ServiceException("请重新登录", 401);
            URI base = configuredBase();
            ResponseEntity<byte[]> state = exchange(base.resolve("/api/v1/lab/state"), "GET", null, bearer, site);
            if (state.getStatusCodeValue() != 200)
                throw new ServiceException("无法确认当前通话状态", state.getStatusCodeValue());
            com.alibaba.fastjson2.JSONObject envelope = JSON.parseObject(state.getBody());
            com.alibaba.fastjson2.JSONObject data = envelope.getJSONObject("data");
            com.alibaba.fastjson2.JSONArray calls = data == null ? null : data.getJSONArray("calls");
            com.alibaba.fastjson2.JSONObject call = null;
            if (calls != null) for (int i = 0; i < calls.size(); i++)
            {
                com.alibaba.fastjson2.JSONObject candidate = calls.getJSONObject(i);
                if (callId.equals(candidate.getString("id"))) { call = candidate; break; }
            }
            if (call == null || (!admin(user) && !String.valueOf(user.getUser().getUserId()).equals(call.getString("userId"))))
                throw new ServiceException("无权查看该通话画面", 403);
            if (!"connected".equals(call.getString("state")) || !Boolean.TRUE.equals(call.getBoolean("videoEnabled")))
                throw new ServiceException("请在通话接听后开启画面", 409);
            boolean connectedDevice = false;
            com.alibaba.fastjson2.JSONArray people = call.getJSONArray("participants");
            if (people != null) for (int i = 0; i < people.size(); i++)
            {
                com.alibaba.fastjson2.JSONObject person = people.getJSONObject(i);
                if (deviceId.equals(person.getString("deviceId")) && "connected".equals(person.getString("state"))) connectedDevice = true;
            }
            if (!connectedDevice) throw new ServiceException("该设备未接入当前通话", 403);
            connection = (HttpURLConnection) base.resolve("/api/v1/lab/calls/" + callId
                    + "/video/stream?deviceId=" + deviceId).toURL().openConnection();
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(Math.max(100, Math.min(connectTimeoutMs, 30000)));
            connection.setReadTimeout(Math.max(100, Math.min(readTimeoutMs, 30000)));
            connection.setRequestProperty("Authorization", bearer);
            connection.setRequestProperty(SiteAccessService.SITE_HEADER, site);
            if (range != null) connection.setRequestProperty("Range", range);
            int status = connection.getResponseCode();
            if (status != 200 && status != 206 && status != 416)
                throw new ServiceException("联调视频暂不可用", status >= 400 && status < 500 ? status : 502);
            if (status != 416 && (connection.getContentType() == null
                    || !connection.getContentType().toLowerCase(java.util.Locale.ROOT).startsWith("video/")))
                throw new ServiceException("联调视频格式不受支持", 502);
            response.setStatus(status);
            response.setHeader("Cache-Control", "no-store");
            response.setHeader("X-Content-Type-Options", "nosniff");
            for (String header : new String[] {"Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"})
            {
                String value = connection.getHeaderField(header);
                if (value != null) response.setHeader(header, value);
            }
            try (InputStream input = status >= 400 ? connection.getErrorStream() : connection.getInputStream())
            {
                if (input != null)
                {
                    byte[] buffer = new byte[32768];
                    int count;
                    while ((count = input.read(buffer)) != -1) response.getOutputStream().write(buffer, 0, count);
                }
            }
        }
        catch (ServiceException e) { writeVideoFailure(response, e.getCode() == null ? 403 : e.getCode(), e.getMessage()); }
        catch (SocketTimeoutException e) { writeVideoFailure(response, 504, "联调视频读取超时"); }
        catch (IOException e) { if (!response.isCommitted()) writeVideoFailure(response, 502, "联调视频连接中断"); }
        catch (RuntimeException e) { writeVideoFailure(response, 502, "无法确认联调视频状态"); }
        finally { if (connection != null) connection.disconnect(); }
    }

    private static void writeVideoFailure(HttpServletResponse response, int code, String message) throws IOException
    {
        if (response.isCommitted()) return;
        response.reset();
        response.setStatus(code);
        response.setContentType("application/json;charset=UTF-8");
        response.setHeader("Cache-Control", "no-store");
        response.getOutputStream().write(failure(code, message).getBody());
    }

    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private Environment environment;
    @Value("${melhat.call-lab.enabled:false}")
    private boolean enabled;
    @Value("${melhat.call-lab.upstream-base-url:http://call-lab:18766}")
    private String upstreamBaseUrl = "http://call-lab:18766";
    @Value("${melhat.call-lab.connect-timeout-ms:3000}")
    private int connectTimeoutMs = 3000;
    @Value("${melhat.call-lab.read-timeout-ms:15000}")
    private int readTimeoutMs = 15000;

    public ResponseEntity<byte[]> forward(HttpServletRequest request, String method, String path,
            Map<String, Object> suppliedBody)
    {
        try
        {
            assertEnabled();
            if (!("GET".equals(method) && ("/roster".equals(path) || "/state".equals(path)))
                    && !("POST".equals(method) && ("/presence".equals(path) || "/calls".equals(path)
                    || "/tts".equals(path) || "/tts/ack".equals(path) || CALL_ACTION.matcher(path).matches())))
            {
                return failure(404, "联调路径不存在");
            }
            Map<String, Object> body = suppliedBody == null ? Collections.emptyMap() : suppliedBody;
            String site = authorizeSite(request);
            LoginUser user = siteAccessService.requireLogin();
            String client = request.getParameter("client");
            for (String key : request.getParameterMap().keySet())
            {
                if (!"/state".equals(path) || !"client".equals(key)) return failure(400, "不支持的联调查询参数");
            }
            if (client != null && !"console".equals(client)) return failure(400, "不支持的联调客户端类型");
            if ("GET".equals(method))
            {
                requirePermission(user, WearRoleKeys.PERM_CALL_LIST, WearRoleKeys.PERM_CALL_QUERY, WearRoleKeys.PERM_COMMAND_TTS);
                if ("console".equals(client)) requireConsole(user);
            }
            else if ("/presence".equals(path) || "/tts/ack".equals(path))
            {
                requireConsole(user);
            }
            else if ("/tts".equals(path))
            {
                requirePermission(user, WearRoleKeys.PERM_COMMAND_TTS);
            }
            else if (path.endsWith("/invite"))
            {
                requirePermission(user, WearRoleKeys.PERM_CALL_START);
                requireConsole(user);
            }
            else if (CALL_ACTION.matcher(path).matches() && !path.endsWith("/video")
                    && (body.containsKey("deviceId") || Boolean.TRUE.equals(body.get("all"))))
            {
                requireConsole(user);
            }
            else
            {
                requirePermission(user, WearRoleKeys.PERM_CALL_START);
                if ("incoming".equals(body.get("direction")) || path.endsWith("/video") || path.endsWith("/invite")) requireConsole(user);
            }
            String bearer = request.getHeader("Authorization");
            if (bearer == null || !bearer.matches("Bearer [^\\s]+")) return failure(401, "请重新登录后进行联调");
            byte[] payload = "GET".equals(method) ? null : JSON.toJSONBytes(body);
            if (payload != null && payload.length > MAX_REQUEST) return failure(413, "联调请求过大");
            URI base = configuredBase();
            URI upstream = base.resolve("/api/v1/lab" + path + ("console".equals(client) ? "?client=console" : ""));
            return exchange(upstream, method, payload, bearer, site);
        }
        catch (ServiceException e)
        {
            return failure(e.getCode() == null ? 403 : e.getCode(), e.getMessage());
        }
        catch (SocketTimeoutException e)
        {
            // Do not log the URL, request headers, token or exception body.
            return failure(504, "虚拟安全帽联调服务超时，执行状态未确认，请同步状态后重试");
        }
        catch (IOException e)
        {
            return failure(502, "无法连接虚拟安全帽联调服务，执行状态未确认");
        }
        catch (IllegalArgumentException e)
        {
            return failure(503, "联调跳板配置无效，请联系管理员");
        }
    }

    public ResponseEntity<byte[]> info(HttpServletRequest request)
    {
        try
        {
            assertEnabled();
            authorizeSite(request);
            requirePermission(siteAccessService.requireLogin(), WearRoleKeys.PERM_CALL_LIST, WearRoleKeys.PERM_CALL_QUERY, WearRoleKeys.PERM_COMMAND_TTS);
            Map<String, Object> data = new LinkedHashMap<String, Object>();
            data.put("bridge", "java-business-backend");
            data.put("enabled", true);
            data.put("upstreamType", "virtual-helmet");
            data.put("simulation", true);
            data.put("realMedia", false);
            Map<String, Object> result = new LinkedHashMap<String, Object>();
            result.put("code", 200);
            result.put("data", data);
            return json(200, JSON.toJSONBytes(result));
        }
        catch (ServiceException e)
        {
            return failure(e.getCode() == null ? 403 : e.getCode(), e.getMessage());
        }
    }

    private void assertEnabled()
    {
        if (!enabled || environment.acceptsProfiles(org.springframework.core.env.Profiles.of("prod")))
        {
            throw new ServiceException("联调跳板未启用", 404);
        }
    }

    private String authorizeSite(HttpServletRequest request)
    {
        siteAccessService.requireLogin();
        String raw = request.getHeader(SiteAccessService.SITE_HEADER);
        if (raw == null || !raw.matches("[1-9][0-9]{0,18}")) throw new ServiceException("请选择有效厂站", 400);
        Long site;
        try { site = Long.valueOf(raw); }
        catch (NumberFormatException e) { throw new ServiceException("请选择有效厂站", 400); }
        siteAccessService.assertAuthorized(site);
        return raw;
    }

    private boolean admin(LoginUser user)
    {
        return user.getUser() != null && user.getUser().isAdmin();
    }

    private void requirePermission(LoginUser user, String... expected)
    {
        if (admin(user)) return;
        Set<String> permissions = siteAccessService.permissions();
        if (permissions != null)
        {
            for (String permission : expected)
            {
                if (permissions.contains(permission) || permissions.contains("*:*:*")) return;
            }
        }
        throw new ServiceException("没有通讯联调操作权限", 403);
    }

    private void requireConsole(LoginUser user)
    {
        Set<String> roles = siteAccessService.roleKeys(user);
        if (admin(user) || (roles != null && (roles.contains(WearRoleKeys.DUTY)
                || roles.contains(WearRoleKeys.TEAM_LEAD) || roles.contains(WearRoleKeys.PLATFORM_ADMIN)))) return;
        throw new ServiceException("没有虚拟安全帽控制权限", 403);
    }

    private URI configuredBase()
    {
        URI uri = URI.create(upstreamBaseUrl);
        if (!("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) || uri.getHost() == null
                || uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
                || !(uri.getRawPath() == null || uri.getRawPath().isEmpty() || "/".equals(uri.getRawPath())))
        {
            throw new IllegalArgumentException("invalid configured origin");
        }
        return uri;
    }

    private ResponseEntity<byte[]> exchange(URI uri, String method, byte[] payload, String bearer, String site) throws IOException
    {
        HttpURLConnection connection = (HttpURLConnection) uri.toURL().openConnection();
        try
        {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(Math.max(100, Math.min(connectTimeoutMs, 30000)));
            connection.setReadTimeout(Math.max(100, Math.min(readTimeoutMs, 30000)));
            connection.setRequestMethod(method);
            connection.setRequestProperty("Authorization", bearer);
            connection.setRequestProperty(SiteAccessService.SITE_HEADER, site);
            connection.setRequestProperty("Accept", "application/json");
            if (payload != null)
            {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
                connection.setFixedLengthStreamingMode(payload.length);
                try (OutputStream output = connection.getOutputStream()) { output.write(payload); }
            }
            int status = connection.getResponseCode();
            if (status >= 300 && status < 400) return failure(502, "联调服务返回重定向，已阻止转发");
            String type = connection.getContentType();
            if (type == null || !type.toLowerCase(java.util.Locale.ROOT).contains("application/json"))
                return failure(502, "联调服务响应格式异常，执行状态未确认");
            try (InputStream input = status >= 400 ? connection.getErrorStream() : connection.getInputStream())
            {
                if (input == null) return failure(502, "联调服务未返回状态");
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1)
                {
                    if (output.size() + count > MAX_RESPONSE) return failure(502, "联调响应过大，请减少测试数据");
                    output.write(buffer, 0, count);
                }
                return json(status, output.toByteArray());
            }
        }
        finally { connection.disconnect(); }
    }

    private static ResponseEntity<byte[]> failure(int code, String message)
    {
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("code", code);
        result.put("msg", message);
        return json(code, JSON.toJSONString(result).getBytes(StandardCharsets.UTF_8));
    }

    private static ResponseEntity<byte[]> json(int status, byte[] body)
    {
        return ResponseEntity.status(status).contentType(MediaType.APPLICATION_JSON).header("Cache-Control", "no-store").body(body);
    }
}
