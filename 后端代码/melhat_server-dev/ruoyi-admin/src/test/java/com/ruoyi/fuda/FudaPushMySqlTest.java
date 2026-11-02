package com.ruoyi.fuda;

import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.concurrent.*;
import static com.ruoyi.fuda.FudaMapping.object;
import static org.junit.jupiter.api.Assertions.*;

/** Opt-in against the disposable fuda_push_test schema, never a configured application database. */
@EnabledIfSystemProperty(named="fuda.push.mysqlTestPort",matches="[0-9]+")
class FudaPushMySqlTest {
    JdbcTemplate jdbc; TransactionTemplate tx; FudaPushOutbox box;
    @BeforeEach void database() {
        int port=Integer.parseInt(System.getProperty("fuda.push.mysqlTestPort"));
        if(port<1024||port>65535)throw new IllegalArgumentException("Test port outside allowed range");
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:mysql://127.0.0.1:"+port
                +"/fuda_push_test?allowPublicKeyRetrieval=true&useSSL=false&serverTimezone=UTC","root","fuda_disposable_test_20261102"));
        assertEquals("fuda_push_test",jdbc.queryForObject("SELECT DATABASE()",String.class));
        jdbc.execute("DROP TABLE IF EXISTS fuda_push_outbox");
        box=new FudaPushOutbox(jdbc); tx=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
    }
    void enqueue(String id,String device) {
        tx.execute(s->{box.enqueue("test","ledger-"+device,"HELMET",device,object("eventId",id,"eventType","STATUS","data",object("deviceId",device)),1000);return null;});
    }
    @Test void concurrentWorkersCannotClaimSameDeviceWhileItsEarlierLeaseIsActive() throws Exception {
        enqueue("one","a"); enqueue("two","a");
        ExecutorService workers=Executors.newFixedThreadPool(2); CountDownLatch start=new CountDownLatch(1);
        try {
            Callable<FudaPushOutbox.Delivery> call=()->{start.await();return box.claim("test",1000,30000);};
            Future<FudaPushOutbox.Delivery> a=workers.submit(call),b=workers.submit(call);start.countDown();
            FudaPushOutbox.Delivery first=a.get(10,TimeUnit.SECONDS),second=b.get(10,TimeUnit.SECONDS);
            assertEquals(1,(first==null?0:1)+(second==null?0:1));
            FudaPushOutbox.Delivery owner=first==null?second:first; assertEquals("one",owner.eventId);
            assertTrue(box.finish(owner,"DELIVERED","OK",200,1001,0));
            assertEquals("two",box.claim("test",1002,30000).eventId);
        } finally { workers.shutdownNow(); }
    }
    @Test void rollbackAndLaterCommitCannotBeSkippedByAnAutoIncrementWatermark() throws Exception {
        assertThrows(IllegalStateException.class,()->tx.execute(s->{enqueue("rollback","a");throw new IllegalStateException();}));
        enqueue("after-gap","b");
        assertEquals("after-gap",box.claim("test",1000,30000).eventId);
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox",Integer.class));
    }
    @Test void schemaIsIdempotentAndExpiredClaimRetainsBodyAcrossReconstruction() {
        enqueue("stable","a"); FudaPushOutbox.Delivery first=box.claim("test",1000,30000);
        FudaPushOutbox reconstructed=new FudaPushOutbox(jdbc);
        FudaPushOutbox.Delivery retry=reconstructed.claim("test",31000,30000);
        assertEquals(first.eventId,retry.eventId); assertEquals(first.body,retry.body);
        assertFalse(box.finish(first,"DELIVERED","OK",200,31001,0));
        assertTrue(reconstructed.finish(retry,"DELIVERED","OK",200,31001,0));
    }
}
