package com.ruoyi.cluster;
import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.*;
import com.ruoyi.melhat.direct.*;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.common.core.redis.RedisCache;
import com.sun.net.httpserver.HttpServer;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.mock.web.MockHttpServletRequest;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.net.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

/** Two real OS processes share real SQL/Redis. Only the remote cloud endpoint is synthetic. */
public class CoordinationProcessNode {
    static Path dir;static String node;static JdbcTemplate jdbc;static ClusterDatabase db;static ClusterIdentity identity;
    static ClusterWorkCoordinator work;static WearableMaintenance maintenance;static AdminLedgerStore ledger;
    static MediaOperationJournal journal;static AdminAccessService access;static WearableSessions sessions;static StringRedisTemplate redis;
    static HelmetMediaService media;static HelmetMediaStore mediaStore;static WearableBusinessStore business;static DeviceCommandRouter router;static DeviceOwnership ownership;
    static CoordinationBusinessFixture businessFixture;static ExternalDataStore external;static WearableBusinessPolicy policy;
    static volatile String cloudUrl;static volatile boolean pauseCommandSave,pauseEventCursor,pauseEffect,failPreviewWrite;
    static final Map<String,java.util.concurrent.atomic.AtomicInteger> sends=new ConcurrentHashMap<>();
    static final Map<String,OwnerToken> ownerTokens=new ConcurrentHashMap<>();
    static final Map<String,JSONObject> snapshots=new ConcurrentHashMap<>();
    static final String KEY=Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII));
    public static void barrier(String name){try{Files.write(dir.resolve(node+"-"+name),new byte[]{1});long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(50);while(!Files.exists(dir.resolve(node+"-release-"+name))){if(System.nanoTime()>until)throw new IllegalStateException("Barrier timeout");Thread.sleep(20);}}catch(Exception e){throw new IllegalStateException(e);}}
    public static void main(String[]args)throws Exception{
        node=args[0];dir=Paths.get(args[1]);JSONObject config=JSON.parseObject(Files.readString(Paths.get(System.getenv("ROUTING_CONNECTION_FILE"))));
        if(!Arrays.asList("WEARABLE_TEST","wearable_test").contains(config.getString("username")))throw new IllegalStateException("Isolated schema only");
        com.alibaba.druid.pool.DruidDataSource pooled=new com.alibaba.druid.pool.DruidDataSource();pooled.setUrl(System.getenv("COORDINATION_DB_PORT")==null?config.getString("jdbcUrl"):config.getString("jdbcUrl").replaceFirst("(?<=://)[^/?]+","127.0.0.1:"+System.getenv("COORDINATION_DB_PORT")));pooled.setUsername(config.getString("username"));pooled.setPassword(config.getString("password"));pooled.setMaxActive(6);pooled.setMinIdle(0);pooled.setInitialSize(0);pooled.setMaxWait(2000);pooled.setTestWhileIdle(false);
        jdbc=new JdbcTemplate(pooled);db=new ClusterDatabase(jdbc);
        SchemaLifecycle.configure(jdbc.getDataSource(),db.dialect.name(),"validate");
        ClusterProperties properties=new ClusterProperties();properties.setEnabled(true);properties.setNodeId(node);properties.setLeaseMillis(4000);
        identity=new ClusterIdentity(properties,db);identity.start();work=new ClusterWorkCoordinator(db,identity);work.start();
        maintenance=new WearableMaintenance(jdbc);ReflectionTestUtils.setField(maintenance,"coordinator",work);ReflectionTestUtils.setField(maintenance,"clusterDb",db);
        ledger=new AdminLedgerStore(jdbc){@Override public void write(JSONObject state){super.write(state);if(failPreviewWrite){failPreviewWrite=false;jdbc.update("UPDATE coordination_missing_table SET absent_column=1");}}};ReflectionTestUtils.setField(ledger,"clusterEnabled",true);ReflectionTestUtils.setField(ledger,"maintenance",maintenance);ReflectionTestUtils.setField(ledger,"coordinator",work);
        JSONObject redisConfig=JSON.parseObject(Files.readString(Paths.get(System.getenv("COORDINATION_REDIS_FILE"))));
        if(redisConfig.getIntValue("port")!=16379)throw new IllegalStateException("Isolated Redis only");
        RedisStandaloneConfiguration rc=new RedisStandaloneConfiguration(redisConfig.getString("host"),System.getenv("COORDINATION_REDIS_PORT")==null?16379:Integer.parseInt(System.getenv("COORDINATION_REDIS_PORT")));rc.setDatabase(3);rc.setPassword(redisConfig.getString("password"));
        LettuceConnectionFactory factory=new LettuceConnectionFactory(rc,org.springframework.data.redis.connection.lettuce.LettuceClientConfiguration.builder().commandTimeout(java.time.Duration.ofSeconds(2)).shutdownTimeout(java.time.Duration.ofMillis(100)).build());factory.afterPropertiesSet();redis=new StringRedisTemplate(factory);redis.afterPropertiesSet();
        access=new AdminAccessService(ledger);ReflectionTestUtils.setField(access,"redis",redis);
        RedisCache cache=new RedisCache();ReflectionTestUtils.setField(cache,"redisTemplate",redis);sessions=new WearableSessions(cache,ledger);ReflectionTestUtils.setField(sessions,"identity",identity);
        external=new ExternalDataStore(jdbc);ReflectionTestUtils.setField(external,"coordinator",work);
        policy=new WearableBusinessPolicy(jdbc);ReflectionTestUtils.setField(policy,"coordinator",work);
        journal=new MediaOperationJournal(db,identity,work,KEY){@Override protected void afterClaim(){if(pauseEffect){pauseEffect=false;barrier("effect-before-send");}}};
        ownership=new DeviceOwnership(db,identity);router=new DeviceCommandRouter(db,identity,properties,ownership);
        router.register("helmet",(owner,wire,timeout,fence)->{fence.run();sends.computeIfAbsent(owner.deviceId,key->new java.util.concurrent.atomic.AtomicInteger()).incrementAndGet();});
        business=WearableBusinessStore.existing(jdbc,KEY);ReflectionTestUtils.setField(business,"coordinator",work);
        org.springframework.beans.factory.support.DefaultListableBeanFactory guardBeans=new org.springframework.beans.factory.support.DefaultListableBeanFactory();guardBeans.registerSingleton("access",new GuardianAccess(ledger,null));
        ClusterMaintenanceGuard guard=new ClusterMaintenanceGuard(identity,work,db,guardBeans.getBeanProvider(GuardianAccess.class));ReflectionTestUtils.setField(guard,"business",business);ReflectionTestUtils.setField(router,"guard",guard);
        businessFixture=new CoordinationBusinessFixture(jdbc,ledger,business,work,maintenance,external);
        mediaStore=new HelmetMediaStore(dir.resolve(node+"-private.json").toString(),dir.resolve("public").toString(),business){
            @Override public <T>T update(java.util.function.Function<JSONObject,T> edit){
                if(pauseCommandSave&&jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE delivery_status='QUEUED'",Integer.class)>0){pauseCommandSave=false;work.stop();barrier("command-before-save");}
                return super.update(state->{T result=edit.apply(state);if(pauseEventCursor&&state.getLongValue("eventCursor")==2){pauseEventCursor=false;barrier("event-before-commit");}return result;});
            }
        };ReflectionTestUtils.setField(mediaStore,"coordinator",work);
        HelmetCloudClient fakeCloud=new HelmetCloudClient(new HelmetMediaProperties()){
            @Override public boolean configured(){return true;}
            @Override public JSONObject request(String method,String path,JSONObject body){return journal.execute(method,path,body,()->mediaHttp(method,path,body),hash->mediaHttp("GET","/operations/"+hash,null));}
        };
        ReflectionTestUtils.setField(maintenance,"journal",journal);ReflectionTestUtils.setField(maintenance,"cloud",fakeCloud);
        DirectHelmetGateway fakeDevice=new DirectHelmetGateway(new DirectHelmetProperties(),null){
            @Override public boolean supports(String device){return "h".equals(device)||device.startsWith("coord-hat-");}
            @Override public boolean isOnline(String device){return ownership.readPresence("helmet",device).getBooleanValue("online");}
            @Override public void sendCommand(String device,JSONObject wire,String purpose)throws IOException{router.send(device,wire,purpose);}
        };
        org.springframework.beans.factory.support.DefaultListableBeanFactory beans=new org.springframework.beans.factory.support.DefaultListableBeanFactory();beans.registerSingleton("gateway",fakeDevice);
        media=new HelmetMediaService(fakeCloud,mediaStore,new HelmetMediaProperties(),beans.getBeanProvider(DirectHelmetGateway.class));
        ReflectionTestUtils.setField(media,"coordinator",work);ReflectionTestUtils.setField(media,"journal",journal);ReflectionTestUtils.setField(media,"commandRouter",router);
        ReflectionTestUtils.setField(media,"healthy",true);ReflectionTestUtils.setField(media,"healthCheckedAt",System.nanoTime());ReflectionTestUtils.setField(media,"registeredDevices",Collections.singleton("h"));

        ScheduledExecutorService renew=Executors.newSingleThreadScheduledExecutor();renew.scheduleWithFixedDelay(identity::renew,200,500,TimeUnit.MILLISECONDS);
        HttpServer server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);server.setExecutor(Executors.newCachedThreadPool());
        server.createContext("/",exchange->{JSONObject result;try{JSONObject input=JSON.parseObject(new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8));result=invoke(input);if(result==null)result=obj("skipped",true);}catch(Throwable e){System.err.println("fixture operation failed: "+e.getClass().getName()+" "+e.getMessage());result=obj("error",e.getClass().getSimpleName(),"code",e instanceof AdminQueryService.QueryFailed?((AdminQueryService.QueryFailed)e).errorCode:"FAILED");}
            byte[] bytes=result.toJSONString().getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);try(OutputStream out=exchange.getResponseBody()){out.write(bytes);}});
        server.start();JSONObject ready=obj("pid",ProcessHandle.current().pid(),"port",server.getAddress().getPort(),"generation",identity.generation());Files.writeString(dir.resolve(node+"-ready.json"),ready.toJSONString());
        Runtime.getRuntime().addShutdownHook(new Thread(()->{renew.shutdownNow();work.stop();identity.stop();factory.destroy();pooled.close();server.stop(0);}));
        new CountDownLatch(1).await();
    }
    static JSONObject invoke(JSONObject in){switch(in.getString("op")){
        case "push":return com.ruoyi.fuda.FudaCoordinationFixture.run(jdbc,db,identity,work,maintenance,in);
        case "mediaEvent":cloudUrl=in.getString("url");pauseEventCursor=in.getBooleanValue("hold");return work.run("media",false,()->{ReflectionTestUtils.invokeMethod(media,"applyEvent",in.getJSONObject("event"));return mediaStore.snapshot();});
        case "mediaReconcile":cloudUrl=in.getString("url");media.reconcile();return obj("available",media.available());
        case "gbAcquire":cloudUrl=in.getString("url");ReflectionTestUtils.setField(media,"healthCheckedAt",System.nanoTime());return media.gbAcquire(in.getString("lease"),"h",90);
        case "gbRelease":cloudUrl=in.getString("url");return media.gbRelease(in.getString("lease"));
        case "rawReceive":return businessFixture.receive(ownerTokens.get(target(in)),ownership);
        case "dispatch":router.dispatchOwnedBatch();return obj("sends",sends.getOrDefault(target(in),new java.util.concurrent.atomic.AtomicInteger()).get());
        case "mediaLogin":ownerTokens.put(target(in),ownership.claimLogin("helmet",target(in),node+"-socket-"+target(in),120000,new JSONObject()));return obj("ok",true);
        case "mediaCommand":cloudUrl=in.getString("url");pauseCommandSave=in.getBooleanValue("hold");ReflectionTestUtils.setField(media,"healthCheckedAt",System.nanoTime());return media.command("demo-system",target(in),in.getJSONObject("input"));
        case "mediaState":return media.commandState(in.getString("id"));
        case "mediaSnapshot":return mediaStore.snapshot();
        case "mediaReceipt":return work.runRecovery("media",false,()->{String receipt="coord-receipt-"+in.getString("id");JSONObject message=in.getJSONObject("message");business.appendDeviceReport(receipt,"direct-helmet-media",target(in),obj("raw",message));business.processReport(receipt,()->{if(!media.receipt(target(in),message,"2026-11-03T00:00:00Z"))throw new IllegalStateException("Receipt not matched");});return media.commandState(in.getString("id"));});
        case "provision":cloudUrl=in.getString("url");ReflectionTestUtils.setField(media,"healthCheckedAt",System.nanoTime());return media.provision("h");
        case "mediaCall":cloudUrl=in.getString("url");ReflectionTestUtils.setField(media,"healthCheckedAt",System.nanoTime());return media.call("demo-system",Collections.singletonList("h"),false);
        case "business":return businessFixture.execute(in);
        case "dbFence":return work.fenced(()->obj("ok",true));
        case "recovery":cloudUrl=in.getString("url");return maintenance.reconcile(in.getString("reason"),obj("id","demo-system"));
        case "policy":return policy.configure(in.getJSONObject("input"),new GuardianAccess(ledger,null).context(obj("id","demo-system")));
        case "external":external.record("coord","Fixture","site-1","DEVICE",in.getString("key"),obj("value",in.getString("value")),in.getString("localId"));return obj("ok",true);
        case "quartz":try{return obj("ran",new ClusterQuartzExecution(identity,db,work).execute("fixture-job",in.getString("firing"),()->{if(in.getBooleanValue("hold"))barrier("quartz-held");work.fenced(()->{jdbc.update("UPDATE coordination_probe SET value_no=value_no+1 WHERE id=1");return null;});}));}catch(Exception e){throw new IllegalStateException(e);}
        case "drain":identity.beginDrain();return obj("draining",identity.isDraining());
        case "nodeStatus":return work.status(true);
        case "killWrite":return ledger.mutate(()->{jdbc.update("UPDATE coordination_probe SET value_no=999 WHERE id=1");JSONObject state=ledger.read();state.getJSONObject("idempotency").put("killed",obj("test",true));ledger.write(state);barrier("kill-before-commit");return obj("ok",true);});
        case "read":return ledger.read();
        case "capture":snapshots.put(in.getString("key"),ledger.read());return obj("ok",true);
        case "replace":{JSONObject old=snapshots.get(in.getString("key"));ledger.replaceExpected(old.getLongValue("revision"),old);return obj("ok",true);}
        case "bare":ledger.write(ledger.read());return obj("ok",true);
        case "mutate":return ledger.mutate(()->{JSONObject state=ledger.read();if(in.getBooleanValue("hold"))barrier("ledger-locked");String key=in.getString("key");JSONObject old=state.getJSONObject("idempotency").getJSONObject(key);
            if(old!=null){if(!Objects.equals(old.getString("value"),in.getString("value")))throw AdminQueryService.fail(409,"IDEMPOTENCY_CONFLICT","Conflict");return old;}
            JSONObject row=obj("id","test-"+state.getLongValue("nextId"),"value",in.getString("value"));state.put("nextId",state.getLongValue("nextId")+1);state.getJSONObject("idempotency").put(key,row);
            JSONArray items=state.getJSONArray("coordinationItems");if(items==null){items=new JSONArray();state.put("coordinationItems",items);}items.add(row);ledger.write(state);
            if(in.getBooleanValue("fail")){external.record("coord-rollback","Fixture","site-1","DEVICE","rollback",obj("value",1),"local");throw new IllegalStateException("Injected rollback");}return row;});
        case "periodic":return work.runPeriodic("periodic","fixture-periodic",60000,()->work.fenced(()->{jdbc.update("UPDATE coordination_probe SET value_no=value_no+1 WHERE id=2");return obj("ran",true);}));
        case "work":return work.run(in.getString("resource"),true,()->{if(in.getBooleanValue("hold"))barrier("work-held");return work.fenced(()->{jdbc.update("UPDATE coordination_probe SET value_no=value_no+1 WHERE id=1");return obj("ran",true);});});
        case "stale":{work.stop();ClusterWorkCoordinator.WorkToken t=work.tryAcquire("stale",1200);barrier("stale-before-write");try{return work.withFencedWrite(t,()->{jdbc.update("UPDATE coordination_probe SET value_no=999 WHERE id=1");return obj("ran",true);});}finally{work.release(t);}}
        case "permit":try(ClusterWorkCoordinator.OperationPermit p=work.begin("SQL")){barrier("permit-held");return work.fenced(()->obj("finished",true));}
        case "pause":return maintenance.setPaused(in.getBooleanValue("paused"),obj("id","demo-system"));
        case "status":return maintenance.status();
        case "effect":pauseEffect=in.getBooleanValue("hold");return work.run("media",false,()->journal.execute("POST","/calls",in.getJSONObject("body"),()->cloud(in.getString("url"),in.getJSONObject("body")),hash->{throw new IllegalStateException("No evidence");}));
        case "expirePreview":redis.expire("wearable:authorization-preview:"+in.getString("id"),java.time.Duration.ofMillis(1));return obj("ok",true);
        case "preview":return new JSONObject(access.query("demo-system","authorizationPreview",in.getJSONObject("input")));
        case "execute":failPreviewWrite=in.getBooleanValue("failSql");return access.execute(in.getString("actor")==null?"demo-system":in.getString("actor"),in.getString("type"),in.getJSONObject("input"));
        case "session":return obj("token",sessions.issue(find(ledger.read().getJSONArray("accounts"),in.getString("actor")),"admin"));
        case "require":{MockHttpServletRequest r=new MockHttpServletRequest();r.addHeader(WearableSessions.HEADER,in.getString("token"));return sessions.require(r,"admin");}
        case "revoke":{MockHttpServletRequest r=new MockHttpServletRequest();r.addHeader(WearableSessions.HEADER,in.getString("token"));sessions.revoke(r);return obj("ok",true);}
        case "nonce":{
            String secret="coordination-test-secret-32-bytes-only";com.ruoyi.fuda.gb.FudaGbInternalController gb=new com.ruoyi.fuda.gb.FudaGbInternalController(media,true,secret,"h",maintenance);ReflectionTestUtils.setField(gb,"redis",redis);
            MockHttpServletRequest request=new MockHttpServletRequest("GET","/internal/fuda-gb/v1/devices/h/status");String time=String.valueOf(java.time.Instant.now().getEpochSecond());request.addHeader("X-GB-Time",time);request.addHeader("X-GB-Nonce",in.getString("nonce"));
            try{request.addHeader("X-GB-Signature",HelmetCloudClient.signature(secret,time,in.getString("nonce"),"GET",request.getRequestURI(),new byte[0]));}catch(Exception e){throw new IllegalStateException(e);}
            return obj("claimed",ReflectionTestUtils.invokeMethod(gb,"authenticate",request,""));
        }
        default:throw new IllegalArgumentException("Unknown operation");
    }}
    static String target(JSONObject in){return in.getString("device")==null?"h":in.getString("device");}
    static JSONObject find(JSONArray rows,String id){for(Object raw:rows){JSONObject r=(JSONObject)raw;if(id.equals(r.getString("id")))return r;}throw new IllegalArgumentException("Missing account");}
    static JSONObject mediaHttp(String method,String path,JSONObject body){try{HttpURLConnection c=(HttpURLConnection)new URL(cloudUrl+path).openConnection();c.setRequestMethod(method);c.setConnectTimeout(1000);c.setReadTimeout(1000);if(body!=null){c.setDoOutput(true);c.getOutputStream().write(body.toJSONString().getBytes(StandardCharsets.UTF_8));}return JSON.parseObject(new String(c.getInputStream().readAllBytes(),StandardCharsets.UTF_8));}catch(Exception e){throw new IllegalStateException("Synthetic media outcome unknown");}}
    static JSONObject cloud(String url,JSONObject body){try{HttpURLConnection c=(HttpURLConnection)new URL(url).openConnection();c.setRequestMethod("POST");c.setConnectTimeout(1000);c.setReadTimeout(1000);c.setDoOutput(true);c.getOutputStream().write(body.toJSONString().getBytes(StandardCharsets.UTF_8));return JSON.parseObject(new String(c.getInputStream().readAllBytes(),StandardCharsets.UTF_8));}catch(Exception e){throw new IllegalStateException("Synthetic cloud outcome unknown");}}
}
