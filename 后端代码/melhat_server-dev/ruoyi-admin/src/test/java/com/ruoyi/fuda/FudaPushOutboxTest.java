package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.*;
import java.util.concurrent.*;
import static com.ruoyi.fuda.FudaMapping.object;
import static org.junit.jupiter.api.Assertions.*;

class FudaPushOutboxTest {
    final JdbcTemplate jdbc = new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID()
            + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;LOCK_TIMEOUT=10000", "sa", ""));
    final TransactionTemplate tx = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
    final FudaPushOutbox box = new FudaPushOutbox(jdbc);
    void enqueue(String id, String device) {
        tx.execute(s -> { box.enqueue("fuda", "ledger-" + device, "HELMET", device,
                object("eventId", id, "eventType", "STATUS", "data", object("deviceId", device)), 1000); return null; });
    }
    @Test void rollbackAndDuplicateIdentityDoNotLeakOrMultiplyWork() {
        assertThrows(IllegalStateException.class, () -> tx.execute(s -> {
            enqueue("rollback", "a"); throw new IllegalStateException("business failed");
        }));
        assertNull(box.claim("fuda", 1000, 30000));
        enqueue("one", "a"); enqueue("one", "a");
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox", Integer.class));
        assertThrows(IllegalStateException.class, () -> box.enqueue("fuda", "ledger-a", "HELMET", "a", object("eventId", "bad", "eventType", "STATUS"), 1000));
    }
    @Test void expiredLeaseSurvivesRestartAndOldWorkerCannotAcknowledgeNewLease() {
        enqueue("one", "a"); FudaPushOutbox.Delivery first = box.claim("fuda", 1000, 30000);
        assertNull(box.claim("fuda", 1001, 30000));
        FudaPushOutbox restarted = new FudaPushOutbox(jdbc);
        FudaPushOutbox.Delivery second = restarted.claim("fuda", 31001, 30000);
        assertEquals(first.eventId, second.eventId); assertEquals(first.body, second.body);
        assertNotEquals(first.leaseToken, second.leaseToken); assertEquals(2, second.attempts);
        assertFalse(box.finish(first, "DELIVERED", "OK", 200, 31002, 0));
        assertTrue(restarted.finish(second, "DELIVERED", "OK", 200, 31002, 0));
        assertNull(box.claim("fuda", 90000, 30000));
    }
    @Test void retryBlocksOnlyItsDeviceAndPreservesPerDeviceOrder() {
        enqueue("a1", "a"); enqueue("a2", "a"); enqueue("b1", "b");
        FudaPushOutbox.Delivery a = box.claim("fuda", 1000, 30000);
        assertEquals("a1", a.eventId); assertTrue(box.finish(a, "PENDING", "TIMEOUT", 0, 1001, 5000));
        assertEquals("b1", box.claim("fuda", 1002, 30000).eventId);
        assertNull(box.claim("fuda", 1003, 30000));
        FudaPushOutbox.Delivery retry = box.claim("fuda", 5000, 30000);
        assertEquals("a1", retry.eventId); box.finish(retry, "DELIVERED", "OK", 200, 5001, 0);
        assertEquals("a2", box.claim("fuda", 5002, 30000).eventId);
    }
    @Test void independentWorkersNeverOwnSameLiveLease() throws Exception {
        enqueue("one", "a"); ExecutorService workers = Executors.newFixedThreadPool(2);
        try {
            CountDownLatch start = new CountDownLatch(1);
            Callable<FudaPushOutbox.Delivery> claim = () -> { start.await(); return box.claim("fuda", 1000, 30000); };
            Future<FudaPushOutbox.Delivery> a = workers.submit(claim), b = workers.submit(claim); start.countDown();
            assertEquals(1, (a.get(10, TimeUnit.SECONDS) == null ? 0 : 1) + (b.get(10, TimeUnit.SECONDS) == null ? 0 : 1));
        } finally { workers.shutdownNow(); }
    }
    @Test void uncommittedWorkIsInvisibleAndWakeupHappensOnlyAfterCommit() throws Exception {
        java.util.concurrent.atomic.AtomicInteger wakeups = new java.util.concurrent.atomic.AtomicInteger(); box.onCommit(wakeups::incrementAndGet);
        ExecutorService reader = Executors.newSingleThreadExecutor();
        try {
            tx.execute(s -> { enqueue("one", "a"); assertEquals(0, wakeups.get());
                try { assertEquals(0, reader.submit(() -> jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox", Integer.class)).get()); }
                catch (Exception e) { throw new RuntimeException(e); } return null; });
            assertEquals(1, wakeups.get());
        } finally { reader.shutdownNow(); }
    }
}
