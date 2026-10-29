package com.ruoyi.fuda;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import java.time.Duration;
@Component
public class FudaRedisNonceStore implements FudaNonceStore {
    private final StringRedisTemplate redis;
    public FudaRedisNonceStore(StringRedisTemplate redis){this.redis=redis;}
    public boolean claim(String appId,String nonce){
        // One extra second covers the inclusive +/-300-second timestamp window at second boundaries.
        try {return Boolean.TRUE.equals(redis.opsForValue().setIfAbsent("fuda:v2:nonce:"+appId+":"+nonce,"1",Duration.ofSeconds(601)));}
        catch(RuntimeException e){throw new FudaException(503,50301,"Authentication storage unavailable");}
    }
}
