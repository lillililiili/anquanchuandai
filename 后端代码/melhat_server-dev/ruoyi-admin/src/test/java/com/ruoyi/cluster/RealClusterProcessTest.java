package com.ruoyi.cluster;
import com.alibaba.fastjson2.*;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.common.database.DatabaseDialect;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import javax.websocket.*;
import java.net.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.io.*;
import static org.junit.jupiter.api.Assertions.*;
@EnabledIfEnvironmentVariable(named="ROUTING_CONNECTION_FILE",matches=".+") class RealClusterProcessTest {
    Path dir;
    JdbcTemplate jdbc;
    DatabaseDialect dialect;
    WebSocketContainer ws;
    List<Process> processes=new ArrayList<>();
    List<Session>sockets=new ArrayList<>();
    @Test void independentJvmsPreserveRoutingAndCrashFences()throws Exception {
        JSONObject config=JSONObject.parseObject(new String(Files.readAllBytes(Paths.get(System.getenv("ROUTING_CONNECTION_FILE"))),StandardCharsets.UTF_8));
        assertTrue(Arrays.asList("WEARABLE_TEST","wearable_test").contains(config.getString("username")),"Only isolated test schemas");
        jdbc=new JdbcTemplate(new DriverManagerDataSource(config.getString("jdbcUrl"),config.getString("username"),config.getString("password")));
        dialect=DatabaseDialect.of(jdbc);
        if(dialect==DatabaseDialect.MYSQL)assertEquals("wearable_test",jdbc.queryForObject("SELECT DATABASE()",String.class));
        if("true".equals(System.getenv("ROUTING_RESET_CLUSTER_SCHEMA"))) {
            for(String table:Arrays.asList("wearable_transport_command","wearable_device_owner","wearable_cluster_node","wearable_cluster_control"))if(DatabaseDialect.tableExists(jdbc,table))jdbc.execute("DROP TABLE "+table);
            jdbc.update("DELETE FROM wearable_schema_step WHERE version_id='20261103_cluster_routing'");
            jdbc.update("DELETE FROM wearable_schema_history WHERE version_id='20261103_cluster_routing'");
        }
        new SchemaLifecycle(jdbc).migrate(SchemaLifecycle.all(dialect));
        for(String table:Arrays.asList("wearable_transport_command","wearable_device_owner","wearable_cluster_node","wearable_device_report"))jdbc.update("DELETE FROM "+table);
        dir=Files.createTempDirectory(Paths.get("D:/DevTools/dm8-tmp"),"cluster-process-");
        ws=ContainerProvider.getWebSocketContainer();
        try {
            Node a=start("route-a"),b=start("route-b");
            assertNotEquals(a.info.getString("generation"),b.info.getString("generation"));
            assertNotEquals(a.process.pid(),b.process.pid());
            Path duplicateDir=Files.createDirectory(dir.resolve("duplicate-node"));
            String classpath=System.getProperty("surefire.test.class.path",System.getProperty("java.class.path"));
            Process duplicate=new ProcessBuilder(Paths.get(System.getProperty("java.home"),"bin","java.exe").toString(),"-Djava.io.tmpdir=D:/DevTools/dm8-tmp","-cp",classpath,ClusterProcessNode.class.getName(),"route-a",duplicateDir.toString()).redirectErrorStream(true).redirectOutput(duplicateDir.resolve("duplicate.log").toFile()).start();
            processes.add(duplicate);assertTrue(duplicate.waitFor(20,TimeUnit.SECONDS));assertNotEquals(0,duplicate.exitValue());assertFalse(Files.exists(duplicateDir.resolve("route-a-ready.json")));assertTrue(new String(Files.readAllBytes(duplicateDir.resolve("duplicate.log")),StandardCharsets.UTF_8).contains("already active"));
            Device helmet=connect(a,"/wsHat");
            assertTrue(helmet.send("{\"act\":\"ca_login\",\"device_id\":\"h\"}").getBooleanValue("status"));
            assertTrue(helmet.send("{\"act\":\"ca_report_location\",\"bat_l\":67,\"is_weared\":2,\"x_point\":35.46,\"y_point\":112.57}").getBooleanValue("status"));
            JSONObject global=b.call(obj("op","status"));
            assertTrue(global.getBooleanValue("online"));
            assertEquals(67,global.getIntValue("battery"));
            assertEquals("CURRENT",global.getString("batteryFreshness"));
            assertTrue(Math.abs(java.time.Instant.parse(global.getString("lastSeenAt")).toEpochMilli()-dialect.dbTimeMillis(jdbc))<2000,"DB time replaces skewed session clocks");
            Map<String,Object> beforeRepeat=jdbc.queryForMap("SELECT connection_token,last_seen FROM wearable_device_owner WHERE device_type='helmet' AND device_id='h'");
            assertTrue(helmet.send("{\"act\":\"ca_login\",\"device_id\":\"h\"}").getBooleanValue("status"));
            assertEquals(beforeRepeat,jdbc.queryForMap("SELECT connection_token,last_seen FROM wearable_device_owner WHERE device_type='helmet' AND device_id='h'"));
            Device belt=connect(a,"/wsBelt");
            assertTrue(belt.send("{\"act\":\"ca_login\",\"device_id\":\"b\"}").getBooleanValue("status"));
            assertTrue(b.call(obj("op","status","type","belt")).getBooleanValue("online"));
            assertTrue(belt.send("{\"act\":\"ca_report_location\",\"bat_l\":77,\"is_weared\":2,\"hanger_a_status\":0,\"hanger_b_status\":0}").getBooleanValue("status"));
            JSONObject beltStatus=b.call(obj("op","status","type","belt"));assertEquals(77,beltStatus.getIntValue("battery"));assertNull(beltStatus.get("worn"));assertNull(beltStatus.get("hookAEngaged"));
            assertTrue(belt.send("{\"act\":\"ca_report_location\",\"bat_l\":78}").getBooleanValue("status"));assertNull(b.call(obj("op","status","type","belt")).get("hangerAStatus"));
            Device nextBelt=connect(b,"/wsBelt");assertTrue(nextBelt.send("{\"act\":\"ca_login\",\"device_id\":\"b\"}").getBooleanValue("status"));
            long beltReceipts=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE protocol='direct-belt'",Long.class);belt.session.getBasicRemote().sendText("{\"act\":\"ca_report_location\",\"bat_l\":99}");long closeDeadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);while(belt.session.isOpen()&&System.nanoTime()<closeDeadline)Thread.sleep(20);assertFalse(belt.session.isOpen());assertEquals(beltReceipts,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE protocol='direct-belt'",Long.class));assertTrue(a.call(obj("op","status","type","belt")).getBooleanValue("online"));
            // A transient connection acquisition failure must not send or publish a false offline snapshot.
            b.call(obj("op","submit","key","db-outage","wire",obj("cmd","after-db-restored")));
            a.call(obj("op","database","available",false));
            assertNotNull(a.call(obj("op","status")).getString("error"));
            assertNotNull(a.call(obj("op","dispatch")).getString("error"));
            assertNull(helmet.messages.poll(150,TimeUnit.MILLISECONDS));
            assertTrue(b.call(obj("op","status")).getBooleanValue("online"));
            a.call(obj("op","database","available",true));
            a.call(obj("op","dispatch"));
            assertEquals("after-db-restored",helmet.next().getString("cmd"));
            JSONObject submit=obj("op","submit","key","one","wire",obj("cmd","photo","talkback_id","test-one"));
            assertEquals("QUEUED",b.call(submit).getString("deliveryStatus"));
            a.call(obj("op","dispatch"));
            assertEquals("photo",helmet.next().getString("cmd"));
            assertEquals("SENT",b.call(obj("op","read","id","test-one")).getString("deliveryStatus"));
            a.call(obj("op","dispatch"));
            assertNull(helmet.messages.poll(200,TimeUnit.MILLISECONDS));
            b.call(obj("op","ack","id","test-one","device","other"));
            assertEquals("SENT",b.call(obj("op","read","id","test-one")).getString("deliveryStatus"));
            b.call(obj("op","ack","id","test-one","device","h"));
            assertEquals("ACKNOWLEDGED",a.call(obj("op","read","id","test-one")).getString("deliveryStatus"));
            ExecutorService workers=Executors.newFixedThreadPool(3);
            try {
                JSONObject same=obj("op","submit","key","same","wire",obj("cmd","photo"));
                CountDownLatch go=new CountDownLatch(1);
                Future<JSONObject> f1=workers.submit(()-> {
                    go.await();
                    return a.call(same);
                }
                ),f2=workers.submit(()-> {
                    go.await();
                    return b.call(same);
                }
                );
                go.countDown();
                assertEquals(f1.get(15,TimeUnit.SECONDS).getString("id"),f2.get(15,TimeUnit.SECONDS).getString("id"));
                assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE command_id='test-same'",Integer.class));
                assertNotNull(b.call(obj("op","submit","key","same","wire",obj("cmd","different"))).getString("error"));
                // Old report pauses AFTER owner validation, INSIDE the admission transaction. Takeover must wait.
                a.call(obj("op","holdReport"));
                Future<JSONObject> report=workers.submit(()->helmet.send("{\"act\":\"ca_report_location\",\"bat_l\":68}"));
                waitFile("route-a-report-locked");
                Device newer=connect(b,"/wsHat");
                Future<JSONObject> login=workers.submit(()->newer.send("{\"act\":\"ca_login\",\"device_id\":\"h\"}"));
                Thread.sleep(200);
                assertFalse(login.isDone(),"takeover must wait for committed receipt");
                Files.write(dir.resolve("route-a-release-report-locked"),new byte[0]);
                assertTrue(report.get(15,TimeUnit.SECONDS).getBooleanValue("status"));
                assertTrue(login.get(15,TimeUnit.SECONDS).getBooleanValue("status"));
                long accepted=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Long.class);
                assertFalse(helmet.send("{\"act\":\"ca_report_location\",\"bat_l\":99}").getBooleanValue("status"));
                assertEquals(accepted,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Long.class));
                helmet.session.close();
                assertTrue(b.call(obj("op","status")).getBooleanValue("online"));
                assertEquals("STALE",b.call(obj("op","status")).getString("batteryFreshness"));
                assertTrue(jdbc.queryForObject(dialect.limit("SELECT body FROM wearable_device_report WHERE protocol='direct-helmet' ORDER BY sequence","1"),String.class).contains("captured-assignment"));
                // A queued command remains readable after submitting process A dies; only B owns new socket.
                a.call(obj("op","submit","key","durable","wire",obj("cmd","durable")));
                a.process.destroyForcibly().waitFor(10,TimeUnit.SECONDS);
                assertEquals("QUEUED",b.call(obj("op","read","id","test-durable")).getString("deliveryStatus"));
                b.call(obj("op","dispatch"));
                assertEquals("durable",newer.next().getString("cmd"));
                // Receipt wins over sender completion CAS.
                b.call(obj("op","submit","key","early","wire",obj("cmd","early")));
                b.call(obj("op","sendMode","mode","after"));
                Future<JSONObject> dispatch=workers.submit(()->b.call(obj("op","dispatch")));
                waitFile("route-b-after-send");
                assertEquals("early",newer.next().getString("cmd"));
                b.call(obj("op","ack","id","test-early","device","h"));
                Files.write(dir.resolve("route-b-release-after-send"),new byte[0]);
                dispatch.get(15,TimeUnit.SECONDS);
                assertEquals("ACKNOWLEDGED",b.call(obj("op","read","id","test-early")).getString("deliveryStatus"));
                // Send succeeds, process killed before SENT write: successor records UNKNOWN and never repeats it.
                Files.delete(dir.resolve("route-b-after-send"));
                Files.delete(dir.resolve("route-b-release-after-send"));
                b.call(obj("op","submit","key","crash","wire",obj("cmd","crash")));
                Future<?> dying=workers.submit(()-> {
                    try {
                        b.call(obj("op","dispatch"));
                    }
                    catch(Exception expected) {
                    }
                }
                );
                waitFile("route-b-after-send");
                assertEquals("crash",newer.next().getString("cmd"));
                b.process.destroyForcibly().waitFor(10,TimeUnit.SECONDS);
                dying.get(15,TimeUnit.SECONDS);
                Thread.sleep(6500);
                Node restart=start("route-b");
                assertNotEquals(b.info.getString("generation"),restart.info.getString("generation"));
                assertFalse(restart.call(obj("op","status")).getBooleanValue("online"));
                restart.call(obj("op","dispatch"));
                assertEquals("UNKNOWN",restart.call(obj("op","read","id","test-crash")).getString("deliveryStatus"));
                Device reconnected=connect(restart,"/wsHat");
                assertTrue(reconnected.send("{\"act\":\"ca_login\",\"device_id\":\"h\"}").getBooleanValue("status"));
                restart.call(obj("op","dispatch"));
                assertNull(reconnected.messages.poll(300,TimeUnit.MILLISECONDS));
                // Kill after durable claim but before physical socket write: also UNKNOWN, never a retry.
                restart.call(obj("op","submit","key","before-crash","wire",obj("cmd","must-not-arrive")));
                restart.call(obj("op","sendMode","mode","before"));
                Future<?> beforeDying=workers.submit(()-> {
                    try {
                        restart.call(obj("op","dispatch"));
                    }
                    catch(Exception expected) {
                    }
                }
                );
                waitFile("route-b-before-send");
                assertNull(reconnected.messages.poll(150,TimeUnit.MILLISECONDS));
                restart.process.destroyForcibly().waitFor(10,TimeUnit.SECONDS);
                beforeDying.get(15,TimeUnit.SECONDS);
                Thread.sleep(6500);
                Node finalNode=start("route-b");
                finalNode.call(obj("op","dispatch"));
                assertEquals("UNKNOWN",finalNode.call(obj("op","read","id","test-before-crash")).getString("deliveryStatus"));
                finalNode.call(obj("op","drain"));
                Device denied=connect(finalNode,"/wsBelt");
                assertFalse(denied.send("{\"act\":\"ca_login\",\"device_id\":\"b\"}").getBooleanValue("status"));
            }
            finally {
                workers.shutdownNow();
            }
            List<Map<String,Object>> states=jdbc.queryForList("SELECT command_id,delivery_status FROM wearable_transport_command ORDER BY command_id");
            Files.write(dir.resolve("evidence.json"),obj("product",dialect.name(),"commands",states,"processes",processes.stream().map(Process::pid).collect(java.util.stream.Collectors.toList()),"checks","remote status, single delivery, duplicate/conflict, transaction takeover barrier, late close, restart durable queued, early ACK, before/after-send kill UNKNOWN, no retry, DB acquisition outage, repeated login token retention, belt takeover/partial safety unknown, simulated session clock skew, TTL, drain").toJSONString().getBytes(StandardCharsets.UTF_8));
            System.out.println("CLUSTER_EVIDENCE="+dir);
        }
        finally {
            for(Session s:sockets)try {
                s.close();
            }
            catch(Exception ignored) {
            }
            for(Process p:processes)if(p.isAlive())p.destroyForcibly().waitFor(10,TimeUnit.SECONDS);
            if(ws instanceof org.apache.tomcat.websocket.WsWebSocketContainer)((org.apache.tomcat.websocket.WsWebSocketContainer)ws).destroy();
        }
    }
    Node start(String name)throws Exception {
        Files.deleteIfExists(dir.resolve(name+"-ready.json"));
        String cp=System.getProperty("surefire.test.class.path",System.getProperty("java.class.path"));
        ProcessBuilder pb=new ProcessBuilder(Paths.get(System.getProperty("java.home"),"bin","java.exe").toString(),"-Djava.io.tmpdir=D:/DevTools/dm8-tmp","-Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp","-cp",cp,ClusterProcessNode.class.getName(),name,dir.toString());
        pb.redirectErrorStream(true);
        pb.redirectOutput(dir.resolve(name+"-"+processes.size()+".log").toFile());
        Process p=pb.start();
        processes.add(p);
        waitFile(name+"-ready.json");
        return new Node(p,JSONObject.parseObject(new String(Files.readAllBytes(dir.resolve(name+"-ready.json")),StandardCharsets.UTF_8)));
    }
    void waitFile(String f)throws Exception {
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(45);
        while(!Files.exists(dir.resolve(f))&&System.nanoTime()<end)Thread.sleep(20);
        assertTrue(Files.exists(dir.resolve(f)),"Missing barrier/ready "+f+" in "+dir);
    }
    Device connect(Node n,String path)throws Exception {
        Device d=new Device();
        d.session=ws.connectToServer(new Endpoint() {
            public void onOpen(Session s,EndpointConfig config) {
                s.addMessageHandler(String.class,d.messages::add);
            }
        }
        ,ClientEndpointConfig.Builder.create().build(),URI.create("ws://127.0.0.1:"+n.info.getIntValue("port")+path));
        sockets.add(d.session);
        return d;
    }
    static JSONObject obj(Object...pairs) {
        JSONObject o=new JSONObject();
        for(int i=0;
        i<pairs.length;
        i+=2)o.put((String)pairs[i],pairs[i+1]);
        return o;
    }
    class Node {
        final Process process;
        final JSONObject info;
        Node(Process p,JSONObject i) {
            process=p;
            info=i;
        }
        JSONObject call(JSONObject body)throws Exception {
            HttpURLConnection c=(HttpURLConnection)new URL("http://127.0.0.1:"+info.getIntValue("port")+"/harness").openConnection();
            c.setRequestMethod("POST");
            c.setDoOutput(true);
            c.setConnectTimeout(5000);
            c.setReadTimeout(20000);
            c.setRequestProperty("Content-Type","application/json");
            try(OutputStream out=c.getOutputStream()) {
                out.write(body.toJSONString().getBytes(StandardCharsets.UTF_8));
            }
            try(InputStream in=c.getInputStream()) {
                return JSONObject.parseObject(new String(in.readAllBytes(),StandardCharsets.UTF_8));
            }
            finally {
                c.disconnect();
            }
        }
    }
    static class Device {
        Session session;
        BlockingQueue<String>messages=new LinkedBlockingQueue<>();
        JSONObject send(String text)throws Exception {
            session.getBasicRemote().sendText(text);
            return next();
        }
        JSONObject next()throws Exception {
            String m=messages.poll(15,TimeUnit.SECONDS);
            assertNotNull(m,"Missing device response");
            return JSONObject.parseObject(m);
        }
    }
}
