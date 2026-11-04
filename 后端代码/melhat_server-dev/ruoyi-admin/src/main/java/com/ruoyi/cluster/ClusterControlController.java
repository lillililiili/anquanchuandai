package com.ruoyi.cluster;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.GuardianFiles;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;

@RestController
@RequestMapping("/internal/cluster")
public class ClusterControlController {
    private final ClusterIdentity identity;private final ClusterDatabase db;private final ClusterWorkCoordinator work;
    private final java.util.concurrent.ExecutorService probes=java.util.concurrent.Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"cluster-readiness");t.setDaemon(true);return t;});
    private volatile java.util.concurrent.Future<Boolean> probe;private volatile long checkedAt;private volatile boolean lastReady;
    @javax.annotation.PreDestroy public void stop(){probes.shutdownNow();}
    private final StringRedisTemplate redis;private final GuardianFiles files;private final String adminToken;
    public ClusterControlController(ClusterIdentity identity,ClusterDatabase db,ClusterWorkCoordinator work,StringRedisTemplate redis,GuardianFiles files,
            @Value("${melhat.cluster.admin-token:${MELHAT_CLUSTER_ADMIN_TOKEN:}}")String adminToken){this.identity=identity;this.db=db;this.work=work;this.redis=redis;this.files=files;this.adminToken=adminToken;}
    private static JSONObject object(String key,Object value){JSONObject out=new JSONObject();out.put(key,value);return out;}
    @GetMapping("/live") public ResponseEntity<JSONObject> live(){return ResponseEntity.ok(object("live",true));}
    @GetMapping("/ready") public ResponseEntity<JSONObject> ready(){boolean ready=false;
        if(!identity.isDraining())try{
            java.util.concurrent.Future<Boolean> current;
            synchronized(this){
                if(System.nanoTime()-checkedAt<java.util.concurrent.TimeUnit.SECONDS.toNanos(1))return ResponseEntity.status(lastReady?200:503).body(object("ready",lastReady));
                if(probe==null||probe.isDone())probe=probes.submit(()->identity.isActive()
                    &&Boolean.TRUE.equals(redis.execute((org.springframework.data.redis.core.RedisCallback<Boolean>)c->"PONG".equals(c.ping())))&&files.storageReady());
                current=probe;
            }
            ready=current.get(1500,java.util.concurrent.TimeUnit.MILLISECONDS);lastReady=ready;checkedAt=System.nanoTime();
        }catch(Exception unavailable){ready=false;}
        return ResponseEntity.status(ready?200:503).body(object("ready",ready));
    }
    private boolean authorized(String token){try{return adminToken.matches("[A-Za-z0-9_-]{43,}")&&Base64.getUrlDecoder().decode(adminToken).length>=32&&token!=null&&MessageDigest.isEqual(adminToken.getBytes(StandardCharsets.US_ASCII),token.getBytes(StandardCharsets.US_ASCII));}catch(IllegalArgumentException invalid){return false;}}
    @PostMapping("/drain") public ResponseEntity<JSONObject> drain(@RequestHeader(value="X-Cluster-Admin-Token",required=false)String token){
        if(!authorized(token))return ResponseEntity.status(403).body(object("error","CLUSTER_ADMIN_REQUIRED"));
        identity.beginDrain();return ResponseEntity.status(202).body(object("draining",true));}
    @GetMapping("/drain") public ResponseEntity<JSONObject> drainStatus(@RequestHeader(value="X-Cluster-Admin-Token",required=false)String token){
        if(!authorized(token))return ResponseEntity.status(403).body(object("error","CLUSTER_ADMIN_REQUIRED"));
        JSONObject result=work.status(true);result.put("draining",identity.isDraining());return ResponseEntity.ok(result);}
}
