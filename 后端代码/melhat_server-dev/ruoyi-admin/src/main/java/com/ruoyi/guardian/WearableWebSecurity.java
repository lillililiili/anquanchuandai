package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@Configuration
public class WearableWebSecurity implements WebMvcConfigurer {
    private final WearableSessions sessions;
    public WearableWebSecurity(WearableSessions sessions) { this.sessions = sessions; }
    @Override public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new HandlerInterceptor() {
            @Override public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
                String path = request.getRequestURI();
                if ("POST".equals(request.getMethod()) && (path.equals("/api/admin/v1/login") || path.equals("/api/guardian/v1/login"))) return true;
                try {
                    request.setAttribute("wearable.actor", sessions.require(request, path.startsWith("/api/admin/") ? "admin" : "guardian"));
                    response.setHeader("Cache-Control", "no-store");
                    return true;
                } catch (AdminQueryService.QueryFailed error) {
                    response.setStatus(error.code); response.setContentType("application/json;charset=UTF-8");
                    JSONObject body = new JSONObject(); body.put("code", error.code); body.put("message", error.getMessage()); body.put("errorCode", error.errorCode);
                    response.getWriter().write(body.toJSONString()); return false;
                }
            }
        }).addPathPatterns("/api/admin/**", "/api/guardian/**");
    }
}
