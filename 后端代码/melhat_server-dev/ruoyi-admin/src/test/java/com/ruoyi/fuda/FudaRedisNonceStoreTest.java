package com.ruoyi.fuda;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import java.time.Duration;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class FudaRedisNonceStoreTest {
    @Test void replayClaimIsAtomicAndCoversInclusiveClockWindow(){
        StringRedisTemplate redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);when(redis.opsForValue()).thenReturn(values);
        when(values.setIfAbsent("fuda:v2:nonce:test:nonce","1",Duration.ofSeconds(601))).thenReturn(true,false);
        FudaRedisNonceStore store=new FudaRedisNonceStore(redis);assertTrue(store.claim("test","nonce"));assertFalse(store.claim("test","nonce"));
        verify(values,times(2)).setIfAbsent("fuda:v2:nonce:test:nonce","1",Duration.ofSeconds(601));
    }
    @Test void redisFailureDoesNotDisableReplayProtection(){
        StringRedisTemplate redis=mock(StringRedisTemplate.class);when(redis.opsForValue()).thenThrow(new IllegalStateException("private detail"));
        FudaException failure=assertThrows(FudaException.class,()->new FudaRedisNonceStore(redis).claim("test","nonce"));assertEquals(50301,failure.code);assertFalse(failure.getMessage().contains("private"));
    }
}
