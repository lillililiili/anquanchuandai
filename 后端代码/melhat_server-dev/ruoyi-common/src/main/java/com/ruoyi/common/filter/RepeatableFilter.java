package com.ruoyi.common.filter;

import java.io.IOException;
import javax.servlet.Filter;
import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.http.HttpServletRequest;
import org.springframework.http.MediaType;
import com.ruoyi.common.utils.StringUtils;

/**
 * Repeatable 过滤器
 * 
 * @author ruoyi
 */
public class RepeatableFilter implements Filter
{
    @Override
    public void init(FilterConfig filterConfig) throws ServletException
    {

    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException
    {
        // These narrowly scoped machine APIs authenticate the original body bytes. The
        // legacy wrapper reconstructs text line-by-line and must not consume their stream.
        if (request instanceof HttpServletRequest && signedBodyEndpoint((HttpServletRequest) request))
        {
            chain.doFilter(request, response);
            return;
        }
        ServletRequest requestWrapper = null;
        if (request instanceof HttpServletRequest
                && StringUtils.startsWithIgnoreCase(request.getContentType(), MediaType.APPLICATION_JSON_VALUE))
        {
            requestWrapper = new RepeatedlyRequestWrapper((HttpServletRequest) request, response);
        }
        if (null == requestWrapper)
        {
            chain.doFilter(request, response);
        }
        else
        {
            chain.doFilter(requestWrapper, response);
        }
    }

    private static boolean signedBodyEndpoint(HttpServletRequest request)
    {
        String path = request.getRequestURI();
        String method = request.getMethod();
        if ("POST".equals(method) && ("/openapi/wearables/v2/positions/query".equals(path)
                || "/openapi/wearables/v2/statuses/query".equals(path)
                || "/openapi/wearables/v2/alarms/query".equals(path)))
        {
            return true;
        }
        return path != null && (("GET".equals(method)
                && path.matches("/internal/fuda-gb/v1/devices/[A-Za-z0-9._-]{1,64}/status"))
                || (("PUT".equals(method) || "GET".equals(method) || "DELETE".equals(method))
                && path.matches("/internal/fuda-gb/v1/leases/[A-Za-z0-9_-]{16,100}")));
    }

    @Override
    public void destroy()
    {

    }
}
