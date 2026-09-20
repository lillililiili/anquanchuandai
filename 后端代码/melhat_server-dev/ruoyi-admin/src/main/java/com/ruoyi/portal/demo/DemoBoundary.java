package com.ruoyi.portal.demo;

import java.io.IOException;
import javax.servlet.*;
import javax.servlet.http.*;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Additional boundary BEFORE the legacy security chain. No legacy device/utility routes. */
@Component @Profile("portal-demo") @Order(Ordered.HIGHEST_PRECEDENCE)
public class DemoBoundary extends OncePerRequestFilter {
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain) throws ServletException,IOException {
        String p=request.getRequestURI();
        boolean auth=("POST".equals(request.getMethod())&&("/login".equals(p)||"/logout".equals(p)))||("GET".equals(request.getMethod())&&("/captchaImage".equals(p)||"/getInfo".equals(p)));
        if(p.contains(";")||p.contains("%")||p.contains("..")||!(auth||p.startsWith("/api/portal/v1/"))){
            response.setStatus(403);response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write("{\"code\":403,\"errorCode\":\"DEMO_ROUTE_DENIED\",\"msg\":\"演示实例禁止访问此接口\"}");return;
        }
        response.setHeader("X-Portal-Environment","SIMULATED");chain.doFilter(request,response);
    }
}
