package com.ruoyi.cluster;
import com.ruoyi.guardian.GuardianFiles;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.RedisCallback;
import java.util.Base64;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class ClusterControlControllerTest {
    final ClusterIdentity identity=mock(ClusterIdentity.class);
    final ClusterWorkCoordinator work=mock(ClusterWorkCoordinator.class);
    final StringRedisTemplate redis=mock(StringRedisTemplate.class);
    final GuardianFiles files=mock(GuardianFiles.class);
    final String token=Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[32]);
    ClusterControlController controller(String key){return new ClusterControlController(identity,null,work,redis,files,key);}
    void healthy(){doReturn(true).when(identity).isActive();doReturn(true).when(redis).execute(org.mockito.ArgumentMatchers.<RedisCallback<Boolean>>any());when(files.storageReady()).thenReturn(true);}
    @Test void livenessNeverTouchesDependencies(){ClusterControlController c=controller(token);try{assertEquals(200,c.live().getStatusCodeValue());verifyNoInteractions(identity,redis,files,work);}finally{c.stop();}}
    @Test void readinessRequiresEachDependencyAndNeverInitializesFiles(){healthy();ClusterControlController c=controller(token);try{assertEquals(200,c.ready().getStatusCodeValue());verify(files).storageReady();verifyNoMoreInteractions(files);}finally{c.stop();}
        when(identity.isActive()).thenReturn(false);c=controller(token);try{assertEquals(503,c.ready().getStatusCodeValue());}finally{c.stop();}
        healthy();when(redis.execute(org.mockito.ArgumentMatchers.<RedisCallback<Boolean>>any())).thenThrow(new org.springframework.data.redis.RedisConnectionFailureException("offline"));c=controller(token);try{assertEquals(503,c.ready().getStatusCodeValue());assertEquals(200,c.live().getStatusCodeValue());}finally{c.stop();}
        healthy();when(files.storageReady()).thenReturn(false);c=controller(token);try{assertEquals(503,c.ready().getStatusCodeValue());}finally{c.stop();}
    }
    @Test void slowDependencyHasBoundedProbeAndDrainBypassesPositiveCache(){healthy();when(identity.isActive()).thenAnswer(i->{Thread.sleep(5000);return true;});ClusterControlController c=controller(token);long started=System.nanoTime();try{assertEquals(503,c.ready().getStatusCodeValue());assertTrue(System.nanoTime()-started<java.util.concurrent.TimeUnit.SECONDS.toNanos(3));}finally{c.stop();}
        healthy();c=controller(token);try{assertEquals(200,c.ready().getStatusCodeValue());when(identity.isDraining()).thenReturn(true);assertEquals(503,c.ready().getStatusCodeValue());}finally{c.stop();}
    }
    @Test void drainRequiresConfiguredStrongTokenAndReportsRealUnknown(){ClusterControlController c=controller("");try{assertEquals(403,c.drain(token).getStatusCodeValue());verify(identity,never()).beginDrain();}finally{c.stop();}
        c=controller(token);try{assertEquals(403,c.drain(null).getStatusCodeValue());assertEquals(403,c.drainStatus("bad").getStatusCodeValue());assertEquals(202,c.drain(token).getStatusCodeValue());assertEquals(202,c.drain(token).getStatusCodeValue());verify(identity,times(2)).beginDrain();JSONObject state=new JSONObject();state.put("unknown",1);state.put("quiescent",false);when(work.status(true)).thenReturn(state);when(identity.isDraining()).thenReturn(true);assertFalse(c.drainStatus(token).getBody().getBooleanValue("quiescent"));}finally{c.stop();}}
}
