package com.ruoyi.wear.web;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;

/** Normal accounts use inspection/report APIs, station contact reads and personal support APIs. */
@Configuration
public class InspectionAccessConfig implements WebMvcConfigurer {
    @Autowired private SiteAccessService sites;

    @Override public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new HandlerInterceptor() {
            @Override public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
                String path = request.getRequestURI().substring(request.getContextPath().length());
                String method = request.getMethod();
                // Public account recovery still works before login; its own validation is unchanged.
                if ("POST".equals(method) && "/api/v1/account-recovery/requests".equals(path)) return true;
                if ("OPTIONS".equals(method)) return true;
                if (sites.isPlatformAdmin(sites.requireLogin())) return true;
                if (!allowsInspector(method, path))
                    throw new ServiceException("普通账号仅可巡检、上报、查看通讯录和确认本人设备提醒", HttpStatus.FORBIDDEN);
                // Prevent list services from falling back to every authorized site.
                // Existing person/device services still enforce each object's station.
                if (isContactRead(path) && sites.resolveRequestSiteId() == null)
                    throw new ServiceException("请选择厂站", HttpStatus.BAD_REQUEST);
                return true;
            }
        }).addPathPatterns("/api/v1/**");
    }

    private static boolean isContactRead(String path) {
        return path.matches("/api/v1/people(/options|/[0-9]+)?")
                || path.matches("/api/v1/devices(/[0-9]+)?");
    }

    public static boolean allowsInspector(String method, String path) {
        if ("GET".equals(method)) {
            return path.matches("/api/v1/(me|me/equipment|sites|duty/summary)")
                    || isContactRead(path)
                    || path.matches("/api/v1/events(/filter-options|/inbox/count|/[0-9]+(/actions|/media(/[^/]+)?|/map-tiles/[0-9]+/[0-9]+/[0-9]+)?)?")
                    || path.matches("/api/v1/work-tasks/(mine|[0-9]+(/equipment-check|/events|/inspection(/media/[^/]+)?)?)");
        }
        if ("PUT".equals(method) && "/api/v1/me/current-site".equals(path)) return true;
        if (("PUT".equals(method) || "DELETE".equals(method)) && path.matches("/api/v1/me/push-installations/[^/]+")) return true;
        return "POST".equals(method) && ("/api/v1/events/manual-sos".equals(path)
                || path.matches("/api/v1/events/[0-9]+/(handle|report|confirm|ack)")
                || path.matches("/api/v1/work-tasks/[0-9]+/inspection/(select|records|reports)"));
    }
}
