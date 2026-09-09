package com.ruoyi.framework.security.filter;

import java.io.IOException;
import java.util.Collections;
import java.util.concurrent.TimeUnit;
import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import com.alibaba.fastjson2.JSON;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.AjaxResult;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.framework.config.SecurityPathRules;
import com.ruoyi.wear.helmet.HelmetCallbackAuth;

/**
 * Device callback token, optional HMAC + nonce replay window.
 */
@Component
public class DeviceCallbackAuthFilter extends OncePerRequestFilter
{
    public static final String HEADER = HelmetCallbackAuth.TOKEN_HEADER;

    private static final Logger log = LoggerFactory.getLogger(DeviceCallbackAuthFilter.class);

    @Value("${melhat.callback.token:}")
    private String expectedToken;

    @Value("${melhat.callback.hmac-secret:}")
    private String hmacSecret;

    @Value("${melhat.callback.skew-seconds:300}")
    private int skewSeconds;

    @Autowired(required = false)
    private RedisCache redisCache;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException
    {
        String path = request.getRequestURI();
        if (!SecurityPathRules.isDeviceCallback(path))
        {
            chain.doFilter(request, response);
            return;
        }
        RepeatableBodyRequest wrapped = new RepeatableBodyRequest(request);
        String provided = wrapped.getHeader(HEADER);
        if (!HelmetCallbackAuth.tokenMatches(expectedToken, provided))
        {
            reject(response, path);
            return;
        }
        if (StringUtils.isNotEmpty(hmacSecret))
        {
            String timestamp = wrapped.getHeader(HelmetCallbackAuth.TIMESTAMP_HEADER);
            String nonce = wrapped.getHeader(HelmetCallbackAuth.NONCE_HEADER);
            String signature = wrapped.getHeader(HelmetCallbackAuth.SIGNATURE_HEADER);
            String hmacError = HelmetCallbackAuth.verifyHmac(hmacSecret, timestamp, nonce, wrapped.getBody(),
                    signature, System.currentTimeMillis() / 1000L, skewSeconds);
            if (hmacError != null)
            {
                log.warn("Rejected device callback hmac, path={}, reason={}", path, hmacError);
                reject(response, path);
                return;
            }
            if (!rememberNonce(nonce))
            {
                log.warn("Rejected device callback replayed nonce, path={}", path);
                reject(response, path);
                return;
            }
        }
        UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                "device-callback", null,
                Collections.singletonList(new SimpleGrantedAuthority("ROLE_DEVICE_CALLBACK")));
        SecurityContextHolder.getContext().setAuthentication(authentication);
        try
        {
            chain.doFilter(wrapped, response);
        }
        finally
        {
            SecurityContextHolder.clearContext();
        }
    }

    private boolean rememberNonce(String nonce)
    {
        if (StringUtils.isEmpty(nonce))
        {
            return false;
        }
        if (redisCache == null)
        {
            return true;
        }
        String key = "melhat:cb:nonce:" + nonce;
        Boolean first = redisCache.setIfAbsent(key, "1", skewSeconds, TimeUnit.SECONDS);
        return Boolean.TRUE.equals(first);
    }

    private void reject(HttpServletResponse response, String path) throws IOException
    {
        log.warn("Rejected device callback without valid token, path={}", path);
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        response.setCharacterEncoding("utf-8");
        response.getWriter().print(JSON.toJSONString(AjaxResult.error(HttpStatus.UNAUTHORIZED, "设备回调未认证")));
    }

    boolean tokenMatches(String provided)
    {
        return HelmetCallbackAuth.tokenMatches(expectedToken, provided);
    }

    public void setExpectedToken(String expectedToken)
    {
        this.expectedToken = expectedToken;
    }

    public void setHmacSecret(String hmacSecret)
    {
        this.hmacSecret = hmacSecret;
    }

    public void setSkewSeconds(int skewSeconds)
    {
        this.skewSeconds = skewSeconds;
    }

    public void setRedisCache(RedisCache redisCache)
    {
        this.redisCache = redisCache;
    }
}
