package com.ruoyi.framework.web.service;

import java.util.Set;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import com.ruoyi.common.constant.CacheConstants;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.utils.StringUtils;

/**
 * Immediate session revoke for disable / site grant changes.
 */
@Service
public class UserSessionService
{
    @Autowired
    private RedisCache redisCache;

    @Value("${token.expireTime}")
    private int expireTime;

    public void trackToken(Long userId, String tokenUuid)
    {
        if (userId == null || StringUtils.isEmpty(tokenUuid))
        {
            return;
        }
        String key = CacheConstants.LOGIN_USER_TOKENS_KEY + userId;
        redisCache.addCacheSetValue(key, tokenUuid);
        redisCache.expire(key, expireTime, TimeUnit.MINUTES);
        redisCache.deleteObject(CacheConstants.ACCOUNT_DISABLED_KEY + userId);
    }

    public void untrackToken(Long userId, String tokenUuid)
    {
        if (userId == null || StringUtils.isEmpty(tokenUuid))
        {
            return;
        }
        redisCache.redisTemplate.opsForSet().remove(CacheConstants.LOGIN_USER_TOKENS_KEY + userId, tokenUuid);
        redisCache.deleteObject(CacheConstants.LOGIN_TOKEN_KEY + tokenUuid);
    }

    public void invalidate(Long userId)
    {
        if (userId == null)
        {
            return;
        }
        Set<Object> tokens = redisCache.redisTemplate.opsForSet().members(CacheConstants.LOGIN_USER_TOKENS_KEY + userId);
        if (tokens != null)
        {
            for (Object token : tokens)
            {
                if (token != null)
                {
                    redisCache.deleteObject(CacheConstants.LOGIN_TOKEN_KEY + token.toString());
                }
            }
        }
        redisCache.deleteObject(CacheConstants.LOGIN_USER_TOKENS_KEY + userId);
    }

    public void markDisabled(Long userId)
    {
        if (userId == null)
        {
            return;
        }
        redisCache.setCacheObject(CacheConstants.ACCOUNT_DISABLED_KEY + userId, "1", expireTime, TimeUnit.MINUTES);
        invalidate(userId);
    }

    public void clearDisabled(Long userId)
    {
        if (userId == null)
        {
            return;
        }
        redisCache.deleteObject(CacheConstants.ACCOUNT_DISABLED_KEY + userId);
    }

    public boolean isDisabled(Long userId)
    {
        if (userId == null)
        {
            return false;
        }
        return redisCache.getCacheObject(CacheConstants.ACCOUNT_DISABLED_KEY + userId) != null;
    }
}
