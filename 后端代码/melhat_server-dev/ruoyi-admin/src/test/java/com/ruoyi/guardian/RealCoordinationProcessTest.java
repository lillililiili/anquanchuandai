package com.ruoyi.guardian;
import com.alibaba.fastjson2.*;
import com.ruoyi.cluster.CoordinationProcessNode;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.common.database.DatabaseDialect;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.core.io.ClassPathResource;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.net.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

@EnabledIfEnvironmentVariable(named="COORDINATION_REDIS_FILE",matches=".+")
class RealCoordinationProcessTest {
    Path dir;JdbcTemplate jdbc;List<Process> children=new ArrayList<>();ExecutorService threads=Executors.newCachedThreadPool();
    @Test void realDatabaseRedisTwoProcessFencesAndLedgerTransactions()throws Exception{
        JSONObject c=JSON.parseObject(Files.readString(Paths.get(System.getenv("ROUTING_CONNECTION_FILE"))));assertTrue(Arrays.asList("WEARABLE_TEST","wearable_test").contains(c.getString("username")));
        jdbc=new JdbcTemplate(new DriverManagerDataSource(c.getString("jdbcUrl"),c.getString("username"),c.getString("password")));DatabaseDialect dialect=DatabaseDialect.of(jdbc);
        new SchemaLifecycle(jdbc).migrate(SchemaLifecycle.all(dialect));
        for(String table:Arrays.asList("wearable_cluster_operation","wearable_cluster_work","wearable_media_effect","wearable_cluster_node","wearable_transport_command","wearable_device_owner","wearable_device_report"))jdbc.update("DELETE FROM "+table);
        jdbc.update("DELETE FROM fuda_push_outbox WHERE destination_id='coordination'");
        jdbc.update("UPDATE wearable_runtime_control SET mode='ACTIVE' WHERE control_key='global'");
        dialect.insertIfAbsent(jdbc,"wearable_runtime_control",Arrays.asList("control_key","mode","updated_at"),Arrays.asList("control_key"),"global","ACTIVE",0);
        dialect.upsert(jdbc,"wearable_business_config",Arrays.asList("id","version","body"),Arrays.asList("id"),1,1,WearableBusinessPolicy.defaults().toJSONString());
        jdbc.update("DELETE FROM external_data_record WHERE integration_id IN ('adapter-coord-rollback-site-1','adapter-coord-site-1')");jdbc.update("DELETE FROM external_integration WHERE id IN ('adapter-coord-rollback-site-1','adapter-coord-site-1')");
        if(!DatabaseDialect.tableExists(jdbc,"coordination_probe"))jdbc.execute("CREATE TABLE coordination_probe(id INT PRIMARY KEY,value_no INT NOT NULL)");
        jdbc.update("DELETE FROM coordination_probe");jdbc.update("INSERT INTO coordination_probe VALUES(1,0)");jdbc.update("INSERT INTO coordination_probe VALUES(2,0)");
        JSONObject seed=JSON.parseObject(new String(new ClassPathResource("admin-seed.json").getInputStream().readAllBytes(),StandardCharsets.UTF_8));WearableModel.migrate(seed);WearableCredentials.migrate(seed);seed.put("revision",1);seed.put("idempotency",new JSONObject());
        dialect.upsert(jdbc,"wearable_meta",Arrays.asList("id","revision","next_id"),Arrays.asList("id"),1,1,seed.getLongValue("nextId"));
        AdminLedgerStore initializer=new AdminLedgerStore(jdbc);ReflectionTestUtils.invokeMethod(initializer,"replace",seed);
        dialect.insertIfAbsent(jdbc,"wearable_business_meta",Arrays.asList("namespace","revision","imported_at"),Arrays.asList("namespace"),"media",1,0);
        WearableBusinessStore mediaInitializer=WearableBusinessStore.existing(jdbc,Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII)));
        jdbc.update("DELETE FROM safety_hat_info WHERE hat_number LIKE 'coord-%'");
        dialect.insertIfAbsent(jdbc,"wearable_business_meta",Arrays.asList("namespace","revision","imported_at"),Arrays.asList("namespace"),"guardian",1,0);
        JSONObject guardian=JSON.parseObject(new String(new ClassPathResource("guardian-seed.json").getInputStream().readAllBytes(),StandardCharsets.UTF_8));
        mediaInitializer.save("guardian",jdbc.queryForObject("SELECT revision FROM wearable_business_meta WHERE namespace='guardian'",Long.class),guardian,null);
        long mediaRevision=jdbc.queryForObject("SELECT revision FROM wearable_business_meta WHERE namespace='media'",Long.class);mediaInitializer.save("media",mediaRevision,new JSONObject(),null);
        dir=Paths.get(System.getenv("COORDINATION_OUTPUT"),"coordination-"+dialect.name().toLowerCase()+"-"+System.currentTimeMillis());Files.createDirectories(dir);
        JSONObject evidence=obj("database",dialect.name());HttpServer cloud=null;
        try{
            Node a=start("coord-a"),b=start("coord-b");evidence.put("a",a.ready);evidence.put("b",b.ready);assertNotEquals(a.process.pid(),b.process.pid());
            long revision=a.call(obj("op","read")).getLongValue("revision");
            Future<JSONObject> held=threads.submit(()->a.call(obj("op","mutate","key","a","value","A","hold",true)));await("coord-a-ledger-locked");
            Future<JSONObject> next=threads.submit(()->b.call(obj("op","mutate","key","b","value","B")));Thread.sleep(150);assertFalse(next.isDone());release("coord-a-ledger-locked");assertNotNull(held.get().getString("id"));assertNotNull(next.get().getString("id"));
            JSONObject state=b.call(obj("op","read"));assertEquals(2,state.getJSONArray("coordinationItems").size());assertEquals(revision+2,state.getLongValue("revision"));
            JSONObject replay=a.call(obj("op","mutate","key","a","value","A"));assertEquals(held.get().getString("id"),replay.getString("id"));assertEquals(revision+2,b.call(obj("op","read")).getLongValue("revision"));
            assertEquals("IDEMPOTENCY_CONFLICT",b.call(obj("op","mutate","key","a","value","different")).getString("code"));
            a.call(obj("op","capture","key","old"));b.call(obj("op","mutate","key","c","value","C"));assertEquals("VERSION_CONFLICT",a.call(obj("op","replace","key","old")).getString("code"));assertNotNull(a.call(obj("op","bare")).getString("error"));
            long before=b.call(obj("op","read")).getLongValue("revision");assertNotNull(a.call(obj("op","mutate","key","rollback","value","X","fail",true)).getString("error"));assertEquals(before,b.call(obj("op","read")).getLongValue("revision"));assertNull(b.call(obj("op","read")).getJSONObject("idempotency").get("rollback"));
            assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM external_integration WHERE id='adapter-coord-rollback-site-1'",Integer.class));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM external_data_record WHERE integration_id='adapter-coord-rollback-site-1'",Integer.class));
            // Real policy CAS and first-insert external-record races, with integration and record in one transaction.
            Future<JSONObject> policyA=threads.submit(()->a.call(obj("op","policy","input",obj("simulatedWatchVisible",false,"expectedVersion",1)))),policyB=threads.submit(()->b.call(obj("op","policy","input",obj("simulatedWatchVisible",true,"expectedVersion",1))));
            assertTrue((policyA.get().get("error")==null)!=(policyB.get().get("error")==null));assertEquals(2,jdbc.queryForObject("SELECT version FROM wearable_business_config WHERE id=1",Integer.class));
            Future<JSONObject> extA=threads.submit(()->a.call(obj("op","external","key","same","value","A","localId","bound"))),extB=threads.submit(()->b.call(obj("op","external","key","same","value","B")));assertNull(extA.get().get("error"));assertNull(extB.get().get("error"));
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM external_data_record WHERE integration_id='adapter-coord-site-1'",Integer.class));assertEquals("bound",JSON.parseObject(jdbc.queryForObject("SELECT body FROM external_data_record WHERE integration_id='adapter-coord-site-1'",String.class)).getString("localId"));
            // One scheduler owns a resource while the other sees a bounded skip.
            Future<JSONObject> owner=threads.submit(()->a.call(obj("op","work","resource","scheduler","hold",true)));await("coord-a-work-held");JSONObject skip=b.call(obj("op","work","resource","scheduler"));assertTrue(skip.getBooleanValue("skipped"));release("coord-a-work-held");assertTrue(owner.get().getBooleanValue("ran"));assertEquals(1,jdbc.queryForObject("SELECT value_no FROM coordination_probe WHERE id=1",Integer.class));
            assertTrue(a.call(obj("op","periodic")).getBooleanValue("ran"));assertTrue(b.call(obj("op","periodic")).getBooleanValue("skipped"));assertEquals(1,jdbc.queryForObject("SELECT value_no FROM coordination_probe WHERE id=2",Integer.class));
            // Opposite-node PAUSE reports an active operation and rejects a new ledger mutation.
            Future<JSONObject> permit=threads.submit(()->a.call(obj("op","permit")));await("coord-a-permit-held");JSONObject paused=b.call(obj("op","pause","paused",true));assertFalse(paused.getBooleanValue("quiescent"));assertTrue(paused.getIntValue("activeWrites")>0);assertEquals("MAINTENANCE_PAUSED",b.call(obj("op","mutate","key","paused","value","X")).getString("code"));release("coord-a-permit-held");assertTrue(permit.get().getBooleanValue("finished"));assertTrue(b.call(obj("op","status")).getBooleanValue("quiescent"));b.call(obj("op","pause","paused",false));
            // Shared session issue, cross-node validation and revocation. Do not save tokens in evidence.
            String token=a.call(obj("op","session","actor","demo-system")).getString("token");assertNotNull(token);assertEquals("demo-system",b.call(obj("op","require","token",token)).getString("id"));b.call(obj("op","revoke","token",token));assertEquals("SESSION_EXPIRED",a.call(obj("op","require","token",token)).getString("code"));
            String nonce=UUID.randomUUID().toString();CountDownLatch go=new CountDownLatch(1);Future<JSONObject> n1=threads.submit(()->{go.await();return a.call(obj("op","nonce","nonce",nonce));}),n2=threads.submit(()->{go.await();return b.call(obj("op","nonce","nonce",nonce));});go.countDown();assertNotEquals(n1.get().getBooleanValue("claimed"),n2.get().getBooleanValue("claimed"));
            // Shared Redis preview + protected actual account mutation.
            JSONObject account=state.getJSONArray("accounts").getJSONObject(1);JSONObject input=obj("operationId","coord-access","siteId",account.getString("siteId"),"id",account.getString("id"),"expectedVersion",account.getIntValue("version"),"data",obj("name",account.getString("name"),"loginName",account.getString("loginName"),"personId",account.get("personId"),"bindings",new JSONArray()));
            JSONObject preview=a.call(obj("op","preview","input",obj("siteId",account.getString("siteId"),"type","accounts.update","command",input)));
            assertNotNull(preview.getString("previewId"),preview.toJSONString());input.put("previewId",preview.getString("previewId"));JSONObject edited=b.call(obj("op","execute","type","accounts.update","input",input));assertEquals(200,edited.getIntValue("code"),edited.toJSONString());
            // Redis TTL/revision/consume failure are exercised against the real shared store.
            JSONObject revokedReplayCommand=deviceCreate("AUTH");JSONObject authorizedCreate=a.call(obj("op","business","actor","demo-asset","type","devices.create","input",revokedReplayCommand));assertEquals(200,authorizedCreate.getIntValue("code"),authorizedCreate.toJSONString());
            JSONObject previewTarget=findRow(a.call(obj("op","read")).getJSONArray("accounts"),"demo-asset");
            JSONObject previewChange=obj("operationId","preview-sql-failure","siteId","site-1","id",previewTarget.getString("id"),"expectedVersion",previewTarget.getIntValue("version"),"data",obj("name",previewTarget.getString("name"),"loginName",previewTarget.getString("loginName"),"personId",previewTarget.get("personId"),"bindings",new JSONArray()));
            JSONObject previewRequest=obj("op","preview","input",obj("siteId","site-1","type","accounts.update","command",previewChange));String expiredId=a.call(previewRequest).getString("previewId");a.call(obj("op","expirePreview","id",expiredId));Thread.sleep(25);JSONObject expiredInput=JSON.parseObject(previewChange.toJSONString());expiredInput.put("previewId",expiredId);assertEquals("PREVIEW_EXPIRED",b.call(obj("op","execute","type","accounts.update","input",expiredInput)).getString("code"));
            String oldPreview=a.call(previewRequest).getString("previewId");b.call(obj("op","mutate","key","preview-revision-change","value","new"));JSONObject stalePreview=JSON.parseObject(previewChange.toJSONString());stalePreview.put("previewId",oldPreview);assertEquals("PREVIEW_EXPIRED",a.call(obj("op","execute","type","accounts.update","input",stalePreview)).getString("code"));
            String sqlPreview=a.call(previewRequest).getString("previewId");JSONObject sqlInput=JSON.parseObject(previewChange.toJSONString());sqlInput.put("previewId",sqlPreview);long previewRevision=a.call(obj("op","read")).getLongValue("revision");assertEquals("PREVIEW_CONFIRMATION_UNCERTAIN",b.call(obj("op","execute","type","accounts.update","input",sqlInput,"failSql",true)).getString("code"));assertEquals(previewRevision,a.call(obj("op","read")).getLongValue("revision"));assertEquals("PREVIEW_EXPIRED",a.call(obj("op","execute","type","accounts.update","input",sqlInput)).getString("code"));
            String sharedPreview=a.call(previewRequest).getString("previewId");JSONObject sameInput=JSON.parseObject(previewChange.toJSONString());sameInput.put("previewId",sharedPreview);
            Future<JSONObject> consumeA=threads.submit(()->a.call(obj("op","execute","type","accounts.update","input",sameInput))),consumeB=threads.submit(()->b.call(obj("op","execute","type","accounts.update","input",sameInput)));assertEquals(200,consumeA.get().getIntValue("code"));assertEquals(200,consumeB.get().getIntValue("code"));assertEquals(previewRevision+1,a.call(obj("op","read")).getLongValue("revision"));evidence.put("realRedisPreviewExpiryRevisionConsumeSqlFailure",true);assertEquals("PERMISSION_DENIED",b.call(obj("op","business","actor","demo-asset","type","devices.create","input",revokedReplayCommand)).getString("code"));evidence.put("revokedActorCannotReplayCommittedOperation",true);
            // Actual credential writer: same version yields one commit and immediately revokes shared old session.
            JSONObject resetTarget=findRow(a.call(obj("op","read")).getJSONArray("accounts"),account.getString("id"));String oldCredentialSession=a.call(obj("op","session","actor",account.getString("id"))).getString("token");
            JSONObject resetA=obj("operationId","reset-A","siteId",account.getString("siteId"),"id",account.getString("id"),"expectedVersion",resetTarget.getIntValue("version"),"reason","隔离集群并发凭据重置测试","confirm",true,"password","Fixture2026!9"),resetB=JSON.parseObject(resetA.toJSONString());resetB.put("operationId","reset-B");
            Future<JSONObject> resetOne=threads.submit(()->a.call(obj("op","execute","type","accounts.resetCredential","input",resetA))),resetTwo=threads.submit(()->b.call(obj("op","execute","type","accounts.resetCredential","input",resetB)));assertVersionConflictPair(resetOne.get(),resetTwo.get());assertEquals("SESSION_EXPIRED",b.call(obj("op","require","token",oldCredentialSession)).getString("code"));
            JSONObject customRole=a.call(obj("op","execute","type","roles.create","input",obj("operationId","role-create","siteId","site-1","data",obj("name","集群测试角色","operations",JSONArray.of("events:read"),"siteIds",JSONArray.of("site-1"))))).getJSONObject("data");assertNotNull(customRole);
            JSONObject roleA=obj("operationId","role-edit-A","siteId","site-1","id",customRole.getString("id"),"expectedVersion",customRole.getIntValue("version"),"data",obj("name","并发角色甲","operations",JSONArray.of("events:read"),"siteIds",JSONArray.of("site-1"))),roleB=JSON.parseObject(roleA.toJSONString());roleB.put("operationId","role-edit-B");roleB.getJSONObject("data").put("name","并发角色乙");
            Future<JSONObject> roleOne=threads.submit(()->a.call(obj("op","execute","type","roles.update","input",roleA))),roleTwo=threads.submit(()->b.call(obj("op","execute","type","roles.update","input",roleB)));assertVersionConflictPair(roleOne.get(),roleTwo.get());evidence.put("roleAndCredentialVersionConflicts",true);
            // All associated local SQL participates in the ledger transaction, including real MyBatis hat/sync writers.
            long beforeRollback=a.call(obj("op","read")).getLongValue("revision");assertNotNull(a.call(obj("op","business","type","rollbackAll")).get("error"));
            assertEquals(beforeRollback,b.call(obj("op","read")).getLongValue("revision"));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM safety_hat_info WHERE hat_number IN ('coord-hat-rollback','coord-sync-rollback')",Integer.class));assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM external_data_record WHERE integration_id='adapter-coord-rollback-site-1'",Integer.class));
            Future<JSONObject> deviceA=threads.submit(()->a.call(obj("op","business","type","devices.create","input",deviceCreate("A")))),deviceB=threads.submit(()->b.call(obj("op","business","type","devices.create","input",deviceCreate("B"))));
            JSONObject deviceOne=deviceA.get(),deviceTwo=deviceB.get();assertEquals(200,deviceOne.getIntValue("code"),deviceOne.toJSONString());assertEquals(200,deviceTwo.getIntValue("code"),deviceTwo.toJSONString());
            JSONObject d1=deviceOne.getJSONObject("data"),d2=deviceTwo.getJSONObject("data");assertNotEquals(d1.getString("id"),d2.getString("id"));assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM safety_hat_info WHERE hat_number IN ('coord-hat-A','coord-hat-B')",Integer.class));
            JSONObject editOne=obj("operationId","device-edit-A","siteId","site-1","id",d1.getString("id"),"expectedVersion",d1.getIntValue("version"),"data",obj("name","并发编辑甲")),editTwo=JSON.parseObject(editOne.toJSONString());editTwo.put("operationId","device-edit-B");editTwo.getJSONObject("data").put("name","并发编辑乙");
            Future<JSONObject> editedOne=threads.submit(()->a.call(obj("op","business","type","devices.update","input",editOne))),editedTwo=threads.submit(()->b.call(obj("op","business","type","devices.update","input",editTwo)));assertVersionConflictPair(editedOne.get(),editedTwo.get());
            JSONObject disabled=b.call(obj("op","business","type","devices.disable","input",obj("operationId","disable-fixture","siteId","site-1","deviceId",d2.getString("id"),"deviceVersion",d2.getIntValue("version"),"reason","集群隔离测试停用","acknowledged",true)));assertEquals(200,disabled.getIntValue("code"),disabled.toJSONString());
            JSONObject person=a.call(obj("op","business","type","people.create","input",obj("operationId","person-fixture","siteId","site-1","data",obj("name","集群测试人员","code","COORD-PERSON"))));assertEquals(200,person.getIntValue("code"),person.toJSONString());
            JSONObject assignmentPerson=person.getJSONObject("data"),latestDevice=(editedOne.get().get("error")==null?editedOne:editedTwo).get().getJSONObject("data");
            JSONObject issue=obj("operationId","issue-A","siteId","site-1","personId",assignmentPerson.getString("id"),"personVersion",assignmentPerson.getIntValue("version"),"items",JSONArray.of(obj("deviceId",latestDevice.getString("id"),"deviceVersion",latestDevice.getIntValue("version"))),"acknowledged",true),issueOther=JSON.parseObject(issue.toJSONString());issueOther.put("operationId","issue-B");
            Future<JSONObject> issueA=threads.submit(()->a.call(obj("op","business","type","assignments.issue","input",issue))),issueB=threads.submit(()->b.call(obj("op","business","type","assignments.issue","input",issueOther)));JSONObject issuedA=issueA.get(),issuedB=issueB.get();assertVersionConflictPair(issuedA,issuedB);
            JSONObject platformCreate=deviceCreate("P");JSONObject platformFields=platformCreate.getJSONObject("data");platformFields.remove("source");platformFields.remove("deviceNumber");platformFields.put("code","coord-platform");platformFields.put("sn","coord-platform");
            JSONObject platformDevice=a.call(obj("op","business","type","devices.create","input",platformCreate));assertEquals(200,platformDevice.getIntValue("code"),platformDevice.toJSONString());
            long preSync=a.call(obj("op","read")).getLongValue("revision");assertNotNull(a.call(obj("op","business","type","platform.sync","input",obj("deviceNumber","coord-platform","fail",true))).get("error"));assertEquals(preSync,b.call(obj("op","read")).getLongValue("revision"));assertEquals("0",jdbc.queryForObject("SELECT status FROM safety_hat_info WHERE hat_number='coord-platform'",String.class));
            Future<JSONObject> slow=threads.submit(()->a.call(obj("op","business","type","platform.sync","input",obj("deviceNumber","coord-platform","hold",true))));await("coord-a-platform-preview");
            JSONObject platformRow=platformDevice.getJSONObject("data");JSONObject latestName=b.call(obj("op","business","type","devices.update","input",obj("operationId","during-platform","siteId","site-1","id",platformRow.getString("id"),"expectedVersion",platformRow.getIntValue("version"),"data",obj("name","网络等待期间的新名称"))));assertEquals(200,latestName.getIntValue("code"),latestName.toJSONString());release("coord-a-platform-preview");assertNull(slow.get().get("error"));
            assertEquals("网络等待期间的新名称",findRow(b.call(obj("op","read")).getJSONArray("devices"),platformRow.getString("id")).getString("name"));assertEquals("1",jdbc.queryForObject("SELECT status FROM safety_hat_info WHERE hat_number='coord-platform'",String.class));
            JSONObject projected=b.call(obj("op","business","type","guardianSnapshot"));assertTrue(projected.getLongValue("appliedLedgerRevision")>=a.call(obj("op","read")).getLongValue("revision"));
            a.call(obj("op","business","type","captureProjection"));JSONObject currentHat=findRow(b.call(obj("op","read")).getJSONArray("devices"),d1.getString("id"));
            JSONObject projectionUpdate=b.call(obj("op","business","type","devices.update","input",obj("operationId","projection-newer","siteId","site-1","id",currentHat.getString("id"),"expectedVersion",currentHat.getIntValue("version"),"data",obj("name","投影新版本名称"))));assertEquals(200,projectionUpdate.getIntValue("code"));
            JSONObject newer=b.call(obj("op","business","type","guardianSnapshot")),afterStale=a.call(obj("op","business","type","applyOldProjection"));assertEquals(newer.getLongValue("appliedLedgerRevision"),afterStale.getLongValue("appliedLedgerRevision"));assertEquals("投影新版本名称",findRow(afterStale.getJSONArray("devices"),currentHat.getString("portalDeviceId")).getString("name"));evidence.put("olderProjectionCannotReplaceNewer",true);
            evidence.put("realDeviceMasterMaintenanceWriters",true);evidence.put("assignmentOldVersionOneCommit",true);evidence.put("platformNetworkOutsideTransaction",true);evidence.put("mybatisHatExternalSyncRollback",true);
            // Receipt capture must not wait on media work held by the opposite process.
            a.call(obj("op","mediaLogin","device","coord-hat-A"));
            Future<JSONObject> busyMedia=threads.submit(()->b.call(obj("op","work","resource","media","hold",true)));await("coord-b-work-held");
            long rawBefore=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE protocol='direct-helmet'",Long.class);
            JSONObject rawResult=a.call(obj("op","rawReceive","device","coord-hat-A"));assertTrue(rawResult.getBooleanValue("received"),rawResult.toJSONString());
            assertEquals(rawBefore+1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE protocol='direct-helmet'",Long.class));release("coord-b-work-held");assertNull(busyMedia.get().get("error"));
            jdbc.update("UPDATE coordination_probe SET value_no=value_no-1 WHERE id=1");
            evidence.put("rawReceptionWithoutMediaLease",true);
            // A cloud side effect times out after acceptance: B observes UNKNOWN and does not send again.
            AtomicInteger requests=new AtomicInteger();Map<String,JSONObject> confirmedCloud=new ConcurrentHashMap<>();java.util.concurrent.atomic.AtomicBoolean evidenceAvailable=new java.util.concurrent.atomic.AtomicBoolean();Map<String,AtomicInteger> mediaRequests=new ConcurrentHashMap<>();
            cloud=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);cloud.setExecutor(threads);
            cloud.createContext("/",e->{String path=e.getRequestURI().getPath();mediaRequests.computeIfAbsent(e.getRequestMethod()+" "+path,k->new AtomicInteger()).incrementAndGet();
                try{JSONObject requestBody=JSON.parseObject(new String(e.getRequestBody().readAllBytes(),StandardCharsets.UTF_8));JSONObject reply;
                    if("/".equals(path)){requests.incrementAndGet();reply=new JSONObject();String fp=org.apache.commons.codec.digest.DigestUtils.sha256Hex("POST\n/calls\n"+com.ruoyi.cluster.MediaOperationJournal.canonical(requestBody));confirmedCloud.put(fp,obj("fingerprint",fp,"result",reply));Thread.sleep(1500);}
                    else if("/fuda".equals(path))reply=obj("code",0);
                    else if(path.startsWith("/accounts/"))reply=obj("sipHost","fixture.invalid","wssUrl","wss://fixture.invalid","iceServers",new JSONArray());
                    else if("/calls".equals(path))reply=obj("target","fixture-room");
                    else if("/streams".equals(path)||path.startsWith("/streams/"))reply=obj("streamId","fixture-stream","deviceId","h","pushUrl","rtmp://fixture.invalid/live","hlsUrl","https://fixture.invalid/hls?token=fixture","expiresAt",java.time.Instant.now().plusSeconds(3600).toString(),"publishing",true,"statusVerified",true);
                    else if("POST".equals(e.getRequestMethod())&&"/recordings".equals(path)){reply=obj("recordingId","recording-fixture");String fp=org.apache.commons.codec.digest.DigestUtils.sha256Hex("POST\n/recordings\n"+com.ruoyi.cluster.MediaOperationJournal.canonical(requestBody));confirmedCloud.put(fp,obj("fingerprint",fp,"result",reply));Thread.sleep(1500);}
                    else if(path.startsWith("/operations/")){reply=evidenceAvailable.get()?confirmedCloud.get(path.substring("/operations/".length())):null;if(reply==null){e.sendResponseHeaders(404,-1);return;}}
                    else reply=obj("ready",true,"devices",JSONArray.of(obj("deviceId","h","registered",true)));
                    byte[] bytes=reply.toJSONString().getBytes(StandardCharsets.UTF_8);e.sendResponseHeaders(200,bytes.length);e.getResponseBody().write(bytes);
                }catch(Exception ignored){}finally{e.close();}});cloud.start();String mediaUrl="http://127.0.0.1:"+cloud.getAddress().getPort(),url=mediaUrl+"/";
            // Real dispatch authority must reflect a changed assignment, not its admission snapshot.
            JSONObject assignedState=a.call(obj("op","read")),assignedDevice=findRow(assignedState.getJSONArray("devices"),d1.getString("id")),assignedPerson=findRow(assignedState.getJSONArray("people"),assignmentPerson.getString("id"));
            JSONObject binding=null;for(Object raw:assignedState.getJSONArray("assignments")){JSONObject link=(JSONObject)raw;if(link.getBooleanValue("active")&&assignedDevice.getString("id").equals(link.getString("deviceId")))binding=link;}assertNotNull(binding);
            Future<JSONObject> pushPaused=threads.submit(()->a.call(obj("op","push","url",mediaUrl,"ledgerId",d1.getString("id"),"hold",true)));await("coord-a-push-before-send");
            JSONObject pushDraining=b.call(obj("op","pause","paused",true));assertFalse(pushDraining.getBooleanValue("quiescent"));jdbc.update("UPDATE fuda_push_outbox SET lease_until=0 WHERE event_id='coord-push'");release("coord-a-push-before-send");assertEquals(0,pushPaused.get().getIntValue("completed"));assertEquals("PENDING",jdbc.queryForObject("SELECT status FROM fuda_push_outbox WHERE event_id='coord-push'",String.class));assertNull(mediaRequests.get("POST /fuda"));assertTrue(b.call(obj("op","status")).getBooleanValue("quiescent"));b.call(obj("op","pause","paused",false));
            JSONObject pushed=b.call(obj("op","push","url",mediaUrl,"ledgerId",d1.getString("id")));assertEquals(1,pushed.getIntValue("completed"),pushed.toJSONString());assertEquals(1,mediaRequests.get("POST /fuda").get());evidence.put("pushPauseAfterExpiredClaimReleasesAndResumes",true);
            a.call(obj("op","mediaLogin","device","coord-hat-A"));
            JSONObject guarded=obj("action","list_recordings","idempotencyKey","guard-before","assignmentId",binding.getString("id"),"assignmentVersion",binding.getIntValue("version"),"parameters",obj("startTime","2026-11-01 00:00:00","endTime","2026-11-02 00:00:00"));
            JSONObject admitted=b.call(obj("op","mediaCommand","device","coord-hat-A","url",mediaUrl,"input",guarded));assertNotNull(admitted.getString("id"),admitted.toJSONString());assertEquals(1,a.call(obj("op","dispatch","device","coord-hat-A")).getIntValue("sends"));
            a.call(obj("op","mediaReceipt","device","coord-hat-A","id",admitted.getString("id"),"message",obj("act","push_to_client","res",obj("talkback_id",admitted.getString("id"),"status",true,"data",new JSONArray()))));
            guarded.put("idempotencyKey","guard-after");JSONObject revocable=b.call(obj("op","mediaCommand","device","coord-hat-A","url",mediaUrl,"input",guarded));
            JSONObject returned=b.call(obj("op","business","type","assignments.return","input",obj("operationId","return-before-dispatch","siteId","site-1","personId",assignedPerson.getString("id"),"personVersion",assignedPerson.getIntValue("version"),"acknowledged",true,"items",JSONArray.of(obj("deviceId",assignedDevice.getString("id"),"deviceVersion",assignedDevice.getIntValue("version"),"assignmentId",binding.getString("id"),"assignmentVersion",binding.getIntValue("version"),"condition","GOOD")))));assertEquals(200,returned.getIntValue("code"),returned.toJSONString());
            assertEquals(1,a.call(obj("op","dispatch","device","coord-hat-A")).getIntValue("sends"));assertEquals("CANCELLED",jdbc.queryForObject("SELECT delivery_status FROM wearable_transport_command WHERE command_id=?",String.class,revocable.getString("id")));evidence.put("queuedAssignmentRevocationBeforeSend",true);
            a.call(obj("op","mediaLogin"));
            Future<JSONObject> provisionA=threads.submit(()->a.call(obj("op","provision","url",mediaUrl))),provisionB=threads.submit(()->b.call(obj("op","provision","url",mediaUrl)));
            JSONObject accountA=provisionA.get(),accountB=provisionB.get();assertNull(accountA.get("error"));assertNull(accountB.get("error"));assertTrue(Objects.equals(accountA.getString("password"),accountB.getString("password")));
            assertEquals(1,mediaRequests.get("PUT /accounts/"+accountA.getString("sipId")).get());
            // Exact old-business-row race: B activates list_recordings then pauses before its final save.
            Future<JSONObject> early=threads.submit(()->b.call(obj("op","mediaCommand","url",mediaUrl,"hold",true,"input",obj("action","list_recordings","idempotencyKey","early-business","parameters",obj("startTime","2026-11-01 00:00:00","endTime","2026-11-02 00:00:00")))));
            long earlyDeadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(35);while(!Files.exists(dir.resolve("coord-b-command-before-save"))&&!early.isDone()&&System.nanoTime()<earlyDeadline)Thread.sleep(20);
            assertFalse(early.isDone(),early.isDone()?early.get().toJSONString():"waiting");await("coord-b-command-before-save");String commandId=jdbc.queryForObject("SELECT command_id FROM wearable_transport_command WHERE delivery_status='QUEUED'",String.class);
            // The competing receipt waits for the stopped worker's DB-time lease to expire.
            Thread.sleep(31000);
            JSONArray files=JSONArray.of(obj("fileName","one.mp4","progressId","p1"));
            JSONObject receipt=a.call(obj("op","mediaReceipt","id",commandId,"message",obj("act","push_to_client","res",obj("talkback_id",commandId,"status",true,"data",files))));
            assertEquals(files,receipt.getJSONArray("result"),receipt.toJSONString());assertEquals("acknowledged",receipt.getString("status"));
            release("coord-b-command-before-save");assertEquals("WORK_FENCED",early.get().getString("code"));
            JSONObject preserved=b.call(obj("op","mediaState","id",commandId));assertEquals(files,preserved.getJSONArray("result"));assertEquals("2026-11-03T00:00:00Z",preserved.getString("receiptAt"));
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=? AND processed_at IS NOT NULL",Integer.class,"coord-receipt-"+commandId));
            Future<JSONObject> callA=threads.submit(()->a.call(obj("op","mediaCall","url",mediaUrl))),callB=threads.submit(()->b.call(obj("op","mediaCall","url",mediaUrl)));
            JSONObject offeredA=callA.get(),offeredB=callB.get();assertTrue((offeredA.get("error")==null)!=(offeredB.get("error")==null));assertEquals(1,mediaRequests.get("POST /calls").get());
            String callId=(offeredA.get("error")==null?offeredA:offeredB).getString("callId");
            a.call(obj("op","mediaEvent","url",mediaUrl,"event",obj("sequence",1,"callId",callId,"type","call.connected")));
            Node eventKilled=start("coord-event");evidence.put("eventKilled",eventKilled.ready);
            Future<JSONObject> eventInFlight=threads.submit(()->eventKilled.call(obj("op","mediaEvent","url",mediaUrl,"hold",true,"event",obj("sequence",2,"callId",callId,"type","call.ended"))));await("coord-event-event-before-commit");eventKilled.process.destroyForcibly();assertTrue(eventKilled.process.waitFor(10,TimeUnit.SECONDS));
            JSONObject beforeReplay=b.call(obj("op","mediaSnapshot"));assertEquals(1,beforeReplay.getLongValue("eventCursor"));assertEquals("connected",beforeReplay.getJSONObject("calls").getJSONObject(callId).getString("status"));
            Thread.sleep(4500);JSONObject eventResult=a.call(obj("op","mediaEvent","url",mediaUrl,"event",obj("sequence",2,"callId",callId,"type","call.ended")));assertEquals(2,eventResult.getLongValue("eventCursor"));assertEquals("ended",eventResult.getJSONObject("calls").getJSONObject(callId).getString("status"));
            JSONObject replayEvent=b.call(obj("op","mediaEvent","url",mediaUrl,"event",obj("sequence",1,"callId",callId,"type","call.connected")));assertEquals(2,replayEvent.getLongValue("eventCursor"));assertEquals("ended",replayEvent.getJSONObject("calls").getJSONObject(callId).getString("status"));
            b.call(obj("op","pause","paused",true));JSONObject recovered=b.call(obj("op","recovery","url",mediaUrl,"reason","已核对被杀事件事务回滚及旧节点代次失效"));assertTrue(recovered.getBooleanValue("quiescent"),recovered.toJSONString());assertTrue(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_operation WHERE state='RECOVERED'",Integer.class)>0);b.call(obj("op","pause","paused",false));
            // Human/GB demands share one stream; either node may release only its own demand.
            JSONObject viewing=obj("action","start_video","idempotencyKey","viewer-start","viewerSessionId","fixture-viewer");
            assertNull(a.call(obj("op","mediaCommand","url",mediaUrl,"input",viewing)).get("error"));
            assertNull(b.call(obj("op","gbAcquire","url",mediaUrl,"lease","fixture-gb-lease-0001")).get("error"));
            assertNull(a.call(obj("op","mediaCommand","url",mediaUrl,"input",obj("action","stop_video","idempotencyKey","viewer-stop","viewerSessionId","fixture-viewer"))).get("error"));
            assertTrue(b.call(obj("op","mediaSnapshot")).getJSONObject("streams").getJSONObject("h").getBooleanValue("watchRequested"));
            b.call(obj("op","gbRelease","url",mediaUrl,"lease","fixture-gb-lease-0001"));assertFalse(a.call(obj("op","mediaSnapshot")).getJSONObject("streams").getJSONObject("h").getBooleanValue("watchRequested"));
            Future<JSONObject> recordA=threads.submit(()->a.call(obj("op","mediaCommand","url",mediaUrl,"input",obj("action","start_recording","idempotencyKey","record-A")))),recordB=threads.submit(()->b.call(obj("op","mediaCommand","url",mediaUrl,"input",obj("action","start_recording","idempotencyKey","record-B"))));
            recordA.get();recordB.get();a.call(obj("op","mediaReconcile","url",mediaUrl));b.call(obj("op","mediaReconcile","url",mediaUrl));
            assertEquals(1,mediaRequests.get("POST /recordings").get());assertTrue(a.call(obj("op","mediaSnapshot")).getJSONObject("streams").getJSONObject("h").getBooleanValue("recordStartUnknown"));
            assertNotNull(a.call(obj("op","mediaSnapshot")).getJSONObject("accounts").getJSONObject("coord-hat-A").getString("sipHost"));evidence.put("provisionRecoveredFromDurableLogin",true);
            evidence.put("eventCrashRollbackAndReplay",true);evidence.put("recordingUnknownWrites",1);evidence.put("mixedViewerGbRelease",true);
            evidence.put("earlyReceiptResultPreserved",true);evidence.put("provisionWrites",1);evidence.put("callWrites",1);
            JSONObject unsent=obj("op","effect","url",url,"body",obj("callId","not-sent"),"hold",true);
            Future<JSONObject> heldEffect=threads.submit(()->a.call(unsent));await("coord-a-effect-before-send");assertTrue(b.call(obj("op","mediaReconcile","url",mediaUrl)).getBooleanValue("available"));evidence.put("nonLeaderMediaHealthReady",true);b.call(obj("op","pause","paused",true));release("coord-a-effect-before-send");assertEquals("MAINTENANCE_PAUSED",heldEffect.get().getString("code"));
            assertEquals("NOT_SENT",jdbc.queryForObject("SELECT state FROM wearable_media_effect WHERE operation_id='not-sent'",String.class));assertEquals(0,requests.get());b.call(obj("op","pause","paused",false));evidence.put("pauseBeforeSendKnownNotSent",true);
            JSONObject effect=obj("op","effect","url",url,"body",obj("callId","call-stable"));assertNotNull(a.call(effect).getString("error"));assertNotNull(b.call(effect).getString("error"));assertEquals(1,requests.get());assertEquals("UNKNOWN",jdbc.queryForObject("SELECT state FROM wearable_media_effect WHERE operation_id='call-stable'",String.class));
            evidence.put("cloudRequests",requests.get());
            b.call(obj("op","pause","paused",true));assertEquals("RECOVERY_UNCONFIRMED",b.call(obj("op","recovery","url",mediaUrl,"reason","缺少外部执行证据时必须保持未确认状态")).getString("code"));
            evidenceAvailable.set(true);JSONObject confirmedRecovery=b.call(obj("op","recovery","url",mediaUrl,"reason","已读取假云真实持久执行证据且核对旧节点失效"));assertTrue(confirmedRecovery.getBooleanValue("quiescent"),confirmedRecovery.toJSONString());b.call(obj("op","pause","paused",false));
            assertNull(b.call(effect).get("error"));assertEquals(1,requests.get());assertEquals("CONFIRMED",jdbc.queryForObject("SELECT state FROM wearable_media_effect WHERE operation_id='call-stable'",String.class));
            evidence.put("readEvidenceRecoveryNoResend",true);evidence.put("recoveryAuditRows",jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_recovery",Integer.class));
            // Pause A's work renewal after claim; B takes over. A's later write is fenced.
            Future<JSONObject> stale=threads.submit(()->a.call(obj("op","stale")));await("coord-a-stale-before-write");while(jdbc.queryForObject("SELECT lease_until FROM wearable_cluster_work WHERE resource_key='stale'",Long.class)>dialect.dbTimeMillis(jdbc))Thread.sleep(50);JSONObject taken=b.call(obj("op","work","resource","stale"));assertTrue(taken.getBooleanValue("ran"),taken.toJSONString());release("coord-a-stale-before-write");assertEquals("WORK_FENCED",stale.get().getString("code"));assertEquals(2,jdbc.queryForObject("SELECT value_no FROM coordination_probe WHERE id=1",Integer.class));
            // Automatic/manual triggers share the same per-job owner and durable firing identity.
            Future<JSONObject> quartz=threads.submit(()->b.call(obj("op","quartz","firing","scheduled-1","hold",true)));await("coord-b-quartz-held");
            assertFalse(a.call(obj("op","quartz","firing","manual-1")).getBooleanValue("ran"));release("coord-b-quartz-held");assertTrue(quartz.get().getBooleanValue("ran"));
            assertFalse(a.call(obj("op","quartz","firing","scheduled-1")).getBooleanValue("ran"));assertTrue(a.call(obj("op","quartz","firing","manual-1")).getBooleanValue("ran"));
            assertEquals(4,jdbc.queryForObject("SELECT value_no FROM coordination_probe WHERE id=1",Integer.class));
            // Kill an OS/JVM while a real transaction holds a written row. The other process reads rolled-back SQL.
            Node killed=start("coord-killed");evidence.put("killed",killed.ready);
            Future<JSONObject> dying=threads.submit(()->killed.call(obj("op","killWrite")));await("coord-killed-kill-before-commit");killed.process.destroyForcibly();assertTrue(killed.process.waitFor(10,TimeUnit.SECONDS));
            assertEquals(4,jdbc.queryForObject("SELECT value_no FROM coordination_probe WHERE id=1",Integer.class));assertNull(b.call(obj("op","read")).getJSONObject("idempotency").get("killed"));
            JSONObject heldUnknown=b.call(obj("op","pause","paused",true));assertFalse(heldUnknown.getBooleanValue("quiescent"));assertTrue(heldUnknown.getIntValue("activeWrites")>0);
            b.call(obj("op","pause","paused",false));
            // Node drain is independent from global PAUSE; another node remains admitted.
            assertTrue(a.call(obj("op","drain")).getBooleanValue("draining"));assertNotNull(a.call(obj("op","session","actor","demo-system")).get("error"));assertNotNull(b.call(obj("op","session","actor","demo-system")).getString("token"));
            b.call(obj("op","pause","paused",true));long drainRaw=jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE protocol='direct-helmet'",Long.class);
            JSONObject drainReceipt=a.call(obj("op","rawReceive","device","coord-hat-A"));assertTrue(drainReceipt.getBooleanValue("received"),drainReceipt.toJSONString());assertEquals(drainRaw+1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE protocol='direct-helmet'",Long.class));b.call(obj("op","pause","paused",false));evidence.put("drainedOwnerStillBuffersRawReport",true);
            assertEquals("ACTIVE",jdbc.queryForObject("SELECT mode FROM wearable_runtime_control WHERE control_key='global'",String.class));
            java.util.regex.Matcher address=java.util.regex.Pattern.compile("://([^:/?]+):([0-9]+)").matcher(c.getString("jdbcUrl"));assertTrue(address.find());
            JSONObject redisConfig=JSON.parseObject(Files.readString(Paths.get(System.getenv("COORDINATION_REDIS_FILE"))));
            try(TcpFaultProxy sqlProxy=new TcpFaultProxy(address.group(1),Integer.parseInt(address.group(2)));TcpFaultProxy redisProxy=new TcpFaultProxy(redisConfig.getString("host"),16379)){
                Node io=start("coord-io",sqlProxy,redisProxy);evidence.put("io",io.ready);String shared=b.call(obj("op","session","actor","demo-system")).getString("token");assertEquals("demo-system",io.call(obj("op","require","token",shared)).getString("id"));
                redisProxy.cut();assertNotNull(io.call(obj("op","require","token",shared)).get("error"));assertNotNull(io.call(obj("op","nonce","nonce",UUID.randomUUID().toString())).get("error"));assertEquals("demo-system",b.call(obj("op","require","token",shared)).getString("id"));
                sqlProxy.cut();assertNotNull(io.call(obj("op","dbFence")).get("error"));io.process.destroyForcibly();assertTrue(io.process.waitFor(10,TimeUnit.SECONDS));
            }
            evidence.put("isolatedTcpDbRedisFailureClosed",true);
            evidence.put("killRollback",true);evidence.put("orphanPermitBlocksQuiescence",true);evidence.put("quartzInvocations",2);evidence.put("drainIsNodeLocal",true);
            evidence.put("revision",b.call(obj("op","read")).getLongValue("revision"));evidence.put("checks","ledger-lock,CAS,rollback,idempotency,work-fence,maintenance,session,nonce,preview,cloud-UNKNOWN");
            Files.writeString(dir.resolve("evidence.json"),evidence.toJSONString());System.out.println("COORDINATION_EVIDENCE="+dir);
        }finally{if(cloud!=null)cloud.stop(0);for(Process p:children)if(p.isAlive())p.destroyForcibly();for(Process p:children)p.waitFor(10,TimeUnit.SECONDS);threads.shutdownNow();}
    }
    static void assertVersionConflictPair(JSONObject a,JSONObject b){assertTrue((a.get("error")==null)!=(b.get("error")==null),a.toJSONString()+b.toJSONString());assertEquals("VERSION_CONFLICT",(a.get("error")!=null?a:b).getString("code"));assertEquals(200,(a.get("error")==null?a:b).getIntValue("code"));}
    static JSONObject findRow(JSONArray rows,String id){for(Object raw:rows){JSONObject row=(JSONObject)raw;if(id.equals(row.getString("id")))return row;}throw new IllegalStateException("Missing fixture row");}
    static JSONObject deviceCreate(String key){return obj("operationId","device-create-"+key,"siteId","site-1","data",obj("type","HELMET","source","DIRECT_HELMET","deviceNumber","coord-hat-"+key,"code","COORD-ASSET-"+key,"sn","COORD-SERIAL-"+key,"manufacturer","测试厂商","name","集群测试安全帽"));}
    void await(String name)throws Exception{long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(35);while(!Files.exists(dir.resolve(name))){if(System.nanoTime()>deadline)fail("Barrier unavailable: "+name);Thread.sleep(20);}}
    void release(String name)throws Exception{String node=name.startsWith("coord-a")?"coord-a":"coord-b";Files.write(dir.resolve(node+"-release-"+name.substring(node.length()+1)),new byte[]{1});}
    Node start(String name)throws Exception{return start(name,null,null);}
    Node start(String name,TcpFaultProxy sql,TcpFaultProxy redis)throws Exception{String cp=System.getProperty("surefire.test.class.path",System.getProperty("java.class.path"));ProcessBuilder builder=new ProcessBuilder(Paths.get(System.getProperty("java.home"),"bin","java.exe").toString(),"-Xmx256m","-Djava.io.tmpdir=D:/DevTools/dm8-tmp","-Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp","-cp",cp,CoordinationProcessNode.class.getName(),name,dir.toString()).redirectErrorStream(true).redirectOutput(dir.resolve(name+".log").toFile());if(sql!=null)builder.environment().put("COORDINATION_DB_PORT",String.valueOf(sql.port()));if(redis!=null)builder.environment().put("COORDINATION_REDIS_PORT",String.valueOf(redis.port()));Process p=builder.start();children.add(p);await(name+"-ready.json");return new Node(p,JSON.parseObject(Files.readString(dir.resolve(name+"-ready.json"))));}
    static class Node{final Process process;final JSONObject ready;Node(Process p,JSONObject r){process=p;ready=r;}
        JSONObject call(JSONObject input)throws Exception{HttpURLConnection c=(HttpURLConnection)new URL("http://127.0.0.1:"+ready.getIntValue("port")+"/").openConnection();c.setConnectTimeout(2000);c.setReadTimeout(55000);c.setRequestMethod("POST");c.setDoOutput(true);c.getOutputStream().write(input.toJSONString().getBytes(StandardCharsets.UTF_8));return JSON.parseObject(new String(c.getInputStream().readAllBytes(),StandardCharsets.UTF_8));}}
}
