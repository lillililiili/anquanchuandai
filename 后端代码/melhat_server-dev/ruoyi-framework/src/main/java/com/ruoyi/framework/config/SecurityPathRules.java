package com.ruoyi.framework.config;

/**
 * 匿名与回调路径的显式清单，供 SecurityConfig 与单测共用。
 */
public final class SecurityPathRules
{
    private SecurityPathRules()
    {
    }

    public static final String[] PUBLIC = {
            "/login", "/register", "/captchaImage", "/actuator/health"
    };

    /**
     * Spring Security 层 permitAll，由 {@code DeviceCallbackAuthFilter} 校验回调凭据。
     */
    public static final String[] DEVICE_CALLBACK = {
            "/ext/**", "/aip/head/band/location"
    };

    /**
     * 仅非 prod 匿名。prod 必须携带登录 token（请求头或查询参数 token）。
     */
    public static final String[] DEV_WEBSOCKET = {
            "/ws/**", "/wsHat"
    };

    public static boolean isDeviceCallback(String path)
    {
        if (path == null || path.isEmpty())
        {
            return false;
        }
        return path.equals("/ext")
                || path.startsWith("/ext/")
                || path.equals("/aip/head/band/location")
                || path.startsWith("/aip/head/band/location/");
    }
}
