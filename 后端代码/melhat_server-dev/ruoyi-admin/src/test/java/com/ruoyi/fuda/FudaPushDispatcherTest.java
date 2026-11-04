package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.GuardianStore;
import com.ruoyi.guardian.WearableBusinessStore;
import com.ruoyi.melhat.direct.DirectHelmetProperties;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import static com.ruoyi.fuda.FudaMapping.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class FudaPushDispatcherTest {
    final MutableClock clock=new MutableClock();
    final JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;LOCK_TIMEOUT=5000","sa",""));
    final WearableBusinessStore business=new WearableBusinessStore(jdbc);
    final FudaPushProperties p=new FudaPushProperties();
    final FudaPushOutbox box=new FudaPushOutbox(jdbc);
    final FudaPushCapture capture=new FudaPushCapture(jdbc,box,p,new FudaProperties(),new DirectHelmetProperties(),new DirectBeltProperties(),clock);
    HttpServer receiver; FudaPushDispatcher dispatcher;
    final byte[] key=new byte[32];

    @BeforeEach void setUp() throws Exception {
        jdbc.execute("CREATE TABLE wearable_device (id VARCHAR(128) PRIMARY KEY, body LONGTEXT NOT NULL)");
        jdbc.update("INSERT INTO wearable_device VALUES (?,?)","ledger-h",object("id","ledger-h","type","HELMET","source","DIRECT_HELMET","deviceNumber","h","portalDeviceId","h").toJSONString());
        business.setFudaPushCapture(capture);
        business.load("guardian",null,()->object("version",1,"stations",new JSONArray(),"devices",JSONArray.of(object("id","h","type","H","source","DIRECT_HELMET","online",false)),"events",new JSONArray()));
        p.setEnabled(true); p.setAppId("push-test"); p.setSecretBase64(Base64.getEncoder().encodeToString(key));
        p.setAllowLoopbackHttp(true); p.setAllowedLedgerDeviceIds(new LinkedHashSet<>(Collections.singleton("ledger-h")));
        p.setBatchSize(1); p.setMinSendIntervalMillis(1); p.setConnectTimeoutMillis(100); p.setRequestTimeoutMillis(250);
        receiver=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        p.setEndpoint("http://127.0.0.1:"+receiver.getAddress().getPort()+"/receive");
    }
    void createDispatcher(boolean autoWakeup) {
        dispatcher=new FudaPushDispatcher(box,capture,new FudaPushHttpSender(p,clock),p,clock,mock(ObjectProvider.class));
        if(!autoWakeup)box.onCommit(()->{});
    }
    void report(String receipt) {
        business.appendDeviceReport(receipt,"direct-helmet","h",object("raw",object("act","ca_report_location","device_id","h","bat_l",75),
                "context",object("device",object("id","h","source","DIRECT_HELMET"),"receivedAt",clock.instant().toString())));
        business.processReport(receipt,()->{});
    }
    String queueStatus() { return jdbc.queryForObject("SELECT status FROM fuda_push_outbox ORDER BY sequence LIMIT 1",String.class); }
    byte[] read(InputStream input) throws IOException { ByteArrayOutputStream out=new ByteArrayOutputStream(); byte[] b=new byte[1024]; int n; while((n=input.read(b))!=-1)out.write(b,0,n); return out.toByteArray(); }
    @AfterEach void tearDown() { if(dispatcher!=null)dispatcher.close(); if(receiver!=null)receiver.stop(0); }

    @Test void responseLostAfterSaveRetriesSameEventWithNewNonceAndReceiverDeduplicates() throws Exception {
        Set<String> stored=ConcurrentHashMap.newKeySet(); List<String> nonces=new CopyOnWriteArrayList<>(); AtomicInteger requests=new AtomicInteger();
        receiver.createContext("/receive",exchange->{
            byte[] body=read(exchange.getRequestBody()); JSONObject event=JSONObject.parseObject(new String(body,StandardCharsets.UTF_8));
            String nonce=exchange.getRequestHeaders().getFirst("X-Nonce"); nonces.add(nonce);
            String canonical="POST\n/receive\npush-test\n"+exchange.getRequestHeaders().getFirst("X-Timestamp")+"\n"+nonce+"\n"+FudaAuth.sha256(body);
            if(!FudaAuth.hmac(key,canonical).equals(exchange.getRequestHeaders().getFirst("X-Signature"))) { exchange.sendResponseHeaders(401,-1); exchange.close(); return; }
            stored.add(event.getString("eventId"));
            if(requests.incrementAndGet()==1) { exchange.close(); return; }
            byte[] ack="{\"code\":0}".getBytes(StandardCharsets.UTF_8); exchange.sendResponseHeaders(200,ack.length); exchange.getResponseBody().write(ack); exchange.close();
        }); receiver.start(); createDispatcher(false); report("first");
        assertEquals(0,dispatcher.drain()); assertEquals("PENDING",queueStatus());
        dispatcher.close(); clock.advance(1001); createDispatcher(false);
        assertEquals(1,dispatcher.drain()); assertEquals("DELIVERED",queueStatus());
        assertEquals(1,stored.size()); assertEquals(2,requests.get()); assertNotEquals(nonces.get(0),nonces.get(1));
    }
    @Test void revokedAuthorizationCancelsQueuedRecordWithoutAnyNetworkCall() {
        AtomicInteger calls=new AtomicInteger(); receiver.createContext("/receive",e->{calls.incrementAndGet();e.close();}); receiver.start();
        createDispatcher(false); report("revoked"); p.getAllowedLedgerDeviceIds().clear();
        assertEquals(0,dispatcher.drain()); assertEquals("CANCELLED",queueStatus()); assertEquals(0,calls.get());
    }
    @Test void slowReceiverDoesNotHoldBusinessTransactionOrBlockNextDeviceReceipt() throws Exception {
        CountDownLatch entered=new CountDownLatch(1), release=new CountDownLatch(1);
        receiver.createContext("/receive",e->{read(e.getRequestBody()); entered.countDown();
            try { release.await(5,TimeUnit.SECONDS); } catch(InterruptedException ignored) { Thread.currentThread().interrupt(); } e.close();});
        receiver.start(); createDispatcher(true);
        try {
            report("slow-1"); assertTrue(entered.await(3,TimeUnit.SECONDS));
            assertTimeoutPreemptively(Duration.ofSeconds(1),()->report("slow-2"));
            assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NOT NULL",Integer.class));
            assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox",Integer.class));
        } finally { release.countDown(); }
    }
    @Test void disablePausesPendingWorkAndReenableContinuesIt() {
        receiver.createContext("/receive",e->{read(e.getRequestBody());byte[] b="{\"code\":0}".getBytes(StandardCharsets.UTF_8);e.sendResponseHeaders(200,b.length);e.getResponseBody().write(b);e.close();}); receiver.start();
        createDispatcher(false); report("paused"); p.setEnabled(false); assertEquals(0,dispatcher.drain()); assertEquals("PENDING",queueStatus());
        p.setEnabled(true); assertEquals(1,dispatcher.drain()); assertEquals("DELIVERED",queueStatus());
    }
    @Test void pauseAfterClaimReturnsKnownUnsentRowToPending() {
        AtomicInteger calls=new AtomicInteger();receiver.createContext("/receive",e->{calls.incrementAndGet();e.close();});receiver.start();createDispatcher(false);report("pause-after-claim");
        com.ruoyi.guardian.WearableMaintenance gate=mock(com.ruoyi.guardian.WearableMaintenance.class);when(gate.tryBeginWrite()).thenReturn(true);when(gate.paused()).thenReturn(true);
        org.springframework.test.util.ReflectionTestUtils.setField(dispatcher,"maintenance",gate);
        assertEquals(0,dispatcher.drain());assertEquals("PENDING",queueStatus());assertEquals(0,calls.get());
    }
    @Test void fenceRejectionAfterClaimReturnsKnownUnsentRowToPending() {
        AtomicInteger calls=new AtomicInteger();receiver.createContext("/receive",e->{calls.incrementAndGet();e.close();});receiver.start();createDispatcher(false);report("fence-after-claim");
        com.ruoyi.cluster.ClusterWorkCoordinator work=mock(com.ruoyi.cluster.ClusterWorkCoordinator.class);doThrow(new IllegalStateException("fenced")).when(work).beforeEffect();
        org.springframework.test.util.ReflectionTestUtils.setField(dispatcher,"coordinator",work);
        assertThrows(IllegalStateException.class,()->dispatcher.drain());assertEquals("PENDING",queueStatus());assertEquals(0,calls.get());
    }
    @Test void knownUnsentReleaseAfterExpiryStillFencesChangedToken(){createDispatcher(false);report("expired-not-sent");FudaPushOutbox.Delivery first=box.claim(p.getDestinationId(),clock.millis(),100);clock.advance(101);assertTrue(box.releaseUnsent(first,"NOT_SENT",clock.millis()));FudaPushOutbox.Delivery second=box.claim(p.getDestinationId(),clock.millis(),100);clock.advance(101);FudaPushOutbox.Delivery third=box.claim(p.getDestinationId(),clock.millis(),100);assertFalse(box.releaseUnsent(second,"NOT_SENT",clock.millis()));assertTrue(box.releaseUnsent(third,"NOT_SENT",clock.millis()));assertEquals("PENDING",queueStatus());}
    static final class MutableClock extends Clock {
        final AtomicLong millis=new AtomicLong(Instant.parse("2026-11-02T12:00:00Z").toEpochMilli());
        void advance(long delta) { millis.addAndGet(delta); }
        public ZoneId getZone() { return ZoneOffset.UTC; }
        public Clock withZone(ZoneId zone) { return this; }
        public Instant instant() { return Instant.ofEpochMilli(millis.get()); }
    }
}
