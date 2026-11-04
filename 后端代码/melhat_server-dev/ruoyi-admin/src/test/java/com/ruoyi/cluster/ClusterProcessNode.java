package com.ruoyi.cluster;
import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.*;
import com.ruoyi.melhat.direct.*;
import com.ruoyi.melhat.belt.*;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.common.utils.spring.SpringUtils;
import com.ruoyi.common.websocket.WebSocketConfig;
import org.springframework.boot.autoconfigure.websocket.servlet.WebSocketServletAutoConfiguration;
import org.springframework.boot.autoconfigure.web.servlet.ServletWebServerFactoryAutoConfiguration;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.boot.web.servlet.context.AnnotationConfigServletWebServerApplicationContext;
import org.springframework.context.annotation.*;
import org.springframework.core.env.MapPropertySource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.web.servlet.DispatcherServlet;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import org.springframework.web.bind.annotation.*;
import org.springframework.beans.factory.ObjectProvider;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import static org.mockito.Mockito.*;
/** Loopback-only process fixture. Real Spring/WS/JDBC/ownership/report/command components;
* synthetic registration and captured issuance only. No vendor or production calls. */
public class ClusterProcessNode {
    static Path dir;
    static String node;
    static volatile String sendMode="normal";
    static volatile boolean holdReport;
    static volatile boolean databaseAvailable=true;
    static void barrier(String name) {
        try {
            Files.write(dir.resolve(node+"-"+name),Collections.singletonList("ready"));
            while(!Files.exists(dir.resolve(node+"-release-"+name)))Thread.sleep(20);
        }
        catch(Exception e) {
            throw new IllegalStateException(e);
        }
    }
    public static void main(String[]args)throws Exception {
        node=args[0];
        dir=Paths.get(args[1]);
        AnnotationConfigServletWebServerApplicationContext c=new AnnotationConfigServletWebServerApplicationContext();
        Map<String,Object> settings=new HashMap<>();
        settings.put("server.address","127.0.0.1");
        settings.put("server.port","0");
        c.getEnvironment().getPropertySources().addFirst(new MapPropertySource("loopback",settings));
        c.register(App.class);
        c.refresh();
        // Simulate opposite local session-clock offsets; production cluster initialization must replace them with DB time.
        long localSkew="route-a".equals(node)?7200000L:-7200000L;
        DirectHelmetGateway skewHelmet=c.getBean(DirectHelmetGateway.class);
        ((DirectHelmetSessions)org.springframework.test.util.ReflectionTestUtils.getField(skewHelmet,"sessions")).useClock(java.time.Clock.offset(java.time.Clock.systemUTC(),java.time.Duration.ofMillis(localSkew)));
        skewHelmet.clusterStart();
        DirectBeltGateway skewBelt=c.getBean(DirectBeltGateway.class);
        ((DirectBeltSessions)org.springframework.test.util.ReflectionTestUtils.getField(skewBelt,"sessions")).useClock(java.time.Clock.offset(java.time.Clock.systemUTC(),java.time.Duration.ofMillis(localSkew)));
        skewBelt.clusterStart();
        DeviceCommandRouter router=c.getBean(DeviceCommandRouter.class);
        DirectHelmetGateway gateway=c.getBean(DirectHelmetGateway.class);
        router.register("helmet",(owner,wire,timeout,fence)-> {
            if("before".equals(sendMode))barrier("before-send");
            org.springframework.test.util.ReflectionTestUtils.invokeMethod(gateway,"sendLocal",owner,wire,timeout,fence);
            if("after".equals(sendMode))barrier("after-send");
        }
        );
        ScheduledExecutorService renew=Executors.newSingleThreadScheduledExecutor();
        renew.scheduleWithFixedDelay(()->c.getBean(ClusterIdentity.class).renew(),100,500,TimeUnit.MILLISECONDS);
        JSONObject ready=new JSONObject();
        ready.put("simulatedLocalClockSkewMillis",localSkew);
        ready.put("pid",ProcessHandle.current().pid());
        ready.put("port",c.getWebServer().getPort());
        ready.put("generation",c.getBean(ClusterIdentity.class).generation());
        Files.write(dir.resolve(node+"-ready.json"),ready.toJSONString().getBytes(StandardCharsets.UTF_8));
        Files.write(dir.resolve(node+"-"+ProcessHandle.current().pid()+"-identity.json"),ready.toJSONString().getBytes(StandardCharsets.UTF_8));
        Runtime.getRuntime().addShutdownHook(new Thread(()-> {
            renew.shutdownNow();
            c.close();
        }
        ));
        new CountDownLatch(1).await();
    }
    @Configuration @EnableWebMvc @Import( {
        ServletWebServerFactoryAutoConfiguration.class,WebSocketServletAutoConfiguration.class,WebSocketConfig.class,SpringUtils.class,DirectHelmetGateway.class,DirectHelmetWebSocket.class,DirectBeltGateway.class,DirectBeltWebSocket.class,ClusterDatabase.class,ClusterIdentity.class,DeviceOwnership.class,DeviceCommandRouter.class,WearableReportDelivery.class,Api.class
    }
    ) static class App {
        @Bean DispatcherServlet dispatcherServlet() {
            return new DispatcherServlet();
        }
        @Bean ServletRegistrationBean<DispatcherServlet> dispatcherRegistration(DispatcherServlet d) {
            return new ServletRegistrationBean<>(d,"/");
        }
        @Bean JdbcTemplate jdbc()throws Exception {
            JSONObject config=JSONObject.parseObject(new String(Files.readAllBytes(Paths.get(System.getenv("ROUTING_CONNECTION_FILE"))),StandardCharsets.UTF_8));
            String user=config.getString("username");
            if(!Arrays.asList("WEARABLE_TEST","wearable_test").contains(user))throw new IllegalStateException("Test schema only");
            DriverManagerDataSource ds=new DriverManagerDataSource(config.getString("jdbcUrl"),user,config.getString("password")) {
                @Override public java.sql.Connection getConnection() throws java.sql.SQLException {
                    if(!databaseAvailable)throw new java.sql.SQLException("Synthetic unavailable database connection");
                    return super.getConnection();
                }
            }
            ;
            return new JdbcTemplate(ds);
        }
        @Bean ClusterProperties clusterProperties() {
            ClusterProperties p=new ClusterProperties();
            p.setEnabled(true);
            p.setNodeId(node);
            p.setLeaseMillis(6000);
            p.setSendTimeoutMillis(2000);
            return p;
        }
        @Bean DirectHelmetProperties helmetProperties() {
            DirectHelmetProperties p=new DirectHelmetProperties();
            p.setEnabled(true);
            p.setHeartbeatTimeoutSeconds(10);
            return p;
        }
        @Bean DirectBeltProperties beltProperties() {
            DirectBeltProperties p=new DirectBeltProperties();
            p.setEnabled(true);
            p.setHeartbeatTimeoutSeconds(10);
            return p;
        }
        @Bean DirectHelmetTelemetryService helmetTelemetry() {
            DirectHelmetTelemetryService s=mock(DirectHelmetTelemetryService.class);
            SafetyHatInfo h=new SafetyHatInfo();
            h.setId(1L);
            h.setHatNumber("h");
            h.setBindUserId(100L);
            when(s.registered("h")).thenReturn(h);
            return s;
        }
        @Bean DirectBeltTelemetryService beltTelemetry() {
            DirectBeltTelemetryService s=mock(DirectBeltTelemetryService.class);
            when(s.registered("b")).thenReturn(JSONObject.parseObject("{\"userId\":100,\"userName\":\"synthetic\"}"));
            return s;
        }
        @Bean GuardianIngest ingest() {
            GuardianIngest s=mock(GuardianIngest.class);
            when(s.captureDirect("h")).thenAnswer(i->JSONObject.parseObject("{\"assignmentId\":\"captured-assignment\",\"personId\":\"synthetic-person\"}"));
            when(s.captureBelt("b")).thenAnswer(i->new JSONObject());
            return s;
        }
        @Bean WearableMaintenance maintenance() {
            WearableMaintenance s=mock(WearableMaintenance.class);
            when(s.paused()).thenReturn(true);
            return s;
        }
        @Bean WearableBusinessStore journal(JdbcTemplate jdbc) {
            return new WearableBusinessStore(jdbc) {
                @Override public long appendDeviceReport(String id,String protocol,String device,JSONObject payload) {
                    if(holdReport) {
                        holdReport=false;
                        barrier("report-locked");
                    }
                    return super.appendDeviceReport(id,protocol,device,payload);
                }
            }
            ;
        }
    }
    @RestController static class Api {
        final DeviceOwnership ownership;
        final DeviceCommandRouter router;
        final ClusterIdentity identity;
        final DirectHelmetGateway helmet;
        final DirectBeltGateway belt;
        Api(DeviceOwnership o,DeviceCommandRouter r,ClusterIdentity i,DirectHelmetGateway h,DirectBeltGateway b) {
            ownership=o;
            router=r;
            identity=i;
            helmet=h;
            belt=b;
        }
        @PostMapping("/harness") public JSONObject action(@RequestBody JSONObject in) {
            try {
                String op=in.getString("op");
                switch(op) {
                    case "database":databaseAvailable=in.getBooleanValue("available");
                    return ok();
                    case "status":return "belt".equals(in.getString("type"))?belt.status("b"):helmet.status("h");
                    case "submit": {
                        JSONObject wire=in.getJSONObject("wire");
                        String key=in.getString("key");
                        String id="test-"+key;
                        return router.submit(id,router.scope("actor","h",key),DeviceCommandRouter.fingerprint(wire),"helmet","h",new JSONObject(),wire);
                    }
                    case "read":return router.read(in.getString("id"));
                    case "dispatch":router.dispatchOwnedBatch();
                    return ok();
                    case "ack":router.acknowledge(in.getString("id"),in.getString("device"),true);
                    return ok();
                    case "holdReport":holdReport=true;
                    return ok();
                    case "sendMode":sendMode=in.getString("mode");
                    return ok();
                    case "drain":identity.beginDrain();
                    return ok();
                    default:throw new IllegalArgumentException("Unknown test operation");
                }
            }
            catch(RuntimeException e) {
                JSONObject r=new JSONObject();
                r.put("error",e.getClass().getSimpleName());
                return r;
            }
        }
        JSONObject ok() {
            JSONObject o=new JSONObject();
            o.put("ok",true);
            return o;
        }
    }
}
