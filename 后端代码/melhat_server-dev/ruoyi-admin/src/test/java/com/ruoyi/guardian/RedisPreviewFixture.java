package com.ruoyi.guardian;
import org.springframework.data.redis.core.*;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import static org.mockito.Mockito.*;
final class RedisPreviewFixture {
    @SuppressWarnings("unchecked") static void attach(AdminAccessService access){
        StringRedisTemplate redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);Map<String,String> entries=new HashMap<>();
        when(redis.opsForValue()).thenReturn(values);
        doAnswer(i->{entries.put(i.getArgument(0),i.getArgument(1));return null;}).when(values).set(anyString(),anyString(),any(java.time.Duration.class));
        when(values.get(anyString())).thenAnswer(i->entries.get(i.getArgument(0)));
        when(redis.execute(any(RedisScript.class),anyList(),any())).thenAnswer(i->{String key=(String)((List<?>)i.getArgument(1)).get(0);Object expected=i.getArgument(2);if(expected instanceof Object[])expected=((Object[])expected)[0];if(!Objects.equals(entries.get(key),expected))return 0L;entries.remove(key);return 1L;});
        ReflectionTestUtils.setField(access,"redis",redis);
    }
}
