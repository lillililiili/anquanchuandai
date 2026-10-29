package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.UUID;
import java.util.*;
import java.util.concurrent.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;

class HelmetBusinessJournalTest {
    JdbcTemplate jdbc;HelmetBusinessJournal journal;
    @BeforeEach void setup() {
        DriverManagerDataSource ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        jdbc=new JdbcTemplate(ds);journal=new HelmetBusinessJournal(jdbc);
        jdbc.execute("CREATE TABLE real_time_alarm (id BIGINT PRIMARY KEY,is_handled INT,handle_time TIMESTAMP,update_by VARCHAR(64),update_time TIMESTAMP,create_by VARCHAR(64),del_flag VARCHAR(1),description VARCHAR(100))");
        jdbc.execute("INSERT INTO real_time_alarm (id,is_handled,create_by,del_flag,description) VALUES (1,0,'direct-helmet','0','raw-device-evidence')");
    }
    JSONObject envelope() {return envelope(1);}
    JSONObject envelope(long id) {return object("eventId",id==1?"HE-test":"HE-"+UUID.randomUUID(),"act","ca_sos","rawType","77",
            "sourceRecordType","real_time_alarm","sourceRecordId",id,"deviceId","helmet-test","personId","person-A","siteId","site-A","areaId","area-A","bindingId","bind-A","receivedMillis",id);}
    void raw(long id) {jdbc.update("INSERT INTO real_time_alarm (id,is_handled,create_by,del_flag,description) VALUES (?,0,'direct-helmet','0','raw-device-evidence')",id);}
    JSONObject verified(String id) {return object("id",id,"status","已核验","version",3,"verification",object("submittedAt","2026-10-23T00:01:00Z","actorId","duty-test"));}
    @Test void pendingDeliverySurvivesRepositoryRestartAndSourceCannotBeDuplicated() {
        journal.event(envelope());
        HelmetBusinessJournal restarted=new HelmetBusinessJournal(jdbc);
        assertEquals(1,restarted.pending().size());
        restarted.event(envelope());assertEquals(1,restarted.pending().size());
        restarted.projected(envelope());assertTrue(journal.pending().isEmpty());
    }
    @Test void journalAndSourceWritesRollBackTogether() {
        TransactionTemplate tx=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        assertThrows(IllegalStateException.class,()->tx.execute(status->{
            jdbc.update("UPDATE real_time_alarm SET description='changed' WHERE id=1");
            journal.event(envelope());throw new IllegalStateException("failure after writes");
        }));
        assertTrue(journal.pending().isEmpty());
        assertTrue(journal.openEventIds().isEmpty());
        assertEquals("raw-device-evidence",jdbc.queryForObject("SELECT description FROM real_time_alarm WHERE id=1",String.class));
    }
    @Test void onlyPersistedFinalVerificationClosesTheExactOriginalAlarmAndPreservesEvidence() {
        journal.event(envelope());
        JSONObject event=object("id","HE-test","status","处理中","version",2);
        journal.close(event);assertEquals(0,jdbc.queryForObject("SELECT is_handled FROM real_time_alarm WHERE id=1",Integer.class));
        event.put("status","已核验");event.put("version",3);
        event.put("verification",object("submittedAt","2026-10-23T00:01:00Z","actorId","duty-test"));
        journal.close(event);journal.close(event);
        assertEquals(1,jdbc.queryForObject("SELECT is_handled FROM real_time_alarm WHERE id=1",Integer.class));
        assertEquals("raw-device-evidence",jdbc.queryForObject("SELECT description FROM real_time_alarm WHERE id=1",String.class));
        assertEquals(3,jdbc.queryForObject("SELECT closure_version FROM helmet_event_link WHERE event_id='HE-test'",Integer.class));
    }

    @Test void repeatedRawReportsShareAnOpenCaseButProjectionAcknowledgesOnlyItsExactSource() {
        JSONObject first=envelope(),second=envelope(2);raw(2);
        journal.event(first);journal.event(second);
        assertEquals(first.getString("eventId"),second.getString("eventId"));
        assertEquals(1,second.getJSONObject("initialReport").getLongValue("sourceRecordId"));
        assertEquals(2,journal.pending().size());
        journal.projected(first);
        assertEquals(2,journal.pending().get(0).getLongValue("sourceRecordId"));
        assertEquals(1,journal.pending().size());
        journal.close(verified(first.getString("eventId")));
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM real_time_alarm WHERE is_handled=1",Integer.class));
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_event_link WHERE closure_version=3",Integer.class));
        JSONObject third=envelope(3);raw(3);journal.event(third);
        assertNotEquals(first.getString("eventId"),third.getString("eventId"));
        assertEquals(0,jdbc.queryForObject("SELECT is_handled FROM real_time_alarm WHERE id=3",Integer.class));
    }

    @Test void changedOwnershipBindingOrAlarmTypeAlwaysStartsAnotherCase() {
        JSONObject first=envelope();journal.event(first);
        String[] dimensions={"deviceId","personId","siteId","areaId","bindingId","bindingStart","bindingEnd","act","rawType"};
        for(int n=0;n<dimensions.length;n++) {
            JSONObject next=envelope(n+2);next.put(dimensions[n],"changed");journal.event(next);
            assertNotEquals(first.getString("eventId"),next.getString("eventId"),dimensions[n]);
        }
    }

    @Test void concurrentTransactionsPreserveEveryRawAndShareExactlyOneCase() throws Exception {
        ExecutorService pool=Executors.newFixedThreadPool(8);CountDownLatch start=new CountDownLatch(1);
        List<Future<String>> futures=new ArrayList<>();
        try {
            for(long id=2;id<=25;id++) {final long rawId=id;futures.add(pool.submit(()->{
                start.await();
                return new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource())).execute(tx->{
                    raw(rawId);JSONObject report=envelope(rawId);journal.event(report);return report.getString("eventId");
                });
            }));}
            start.countDown();Set<String> ids=new HashSet<>();
            for(Future<String> result:futures) ids.add(result.get(10,TimeUnit.SECONDS));
            assertEquals(1,ids.size());assertEquals(24,journal.pending().size());
            assertEquals(25,jdbc.queryForObject("SELECT COUNT(*) FROM real_time_alarm",Integer.class));
            journal.close(verified(ids.iterator().next()));
            assertEquals(24,jdbc.queryForObject("SELECT COUNT(*) FROM real_time_alarm WHERE is_handled=1",Integer.class));
        } finally {pool.shutdownNow();}
    }

    @Test void closureWaitsForInFlightAdmissionAndClosesAllItsSources() throws Exception {
        JSONObject first=envelope();journal.event(first);
        ExecutorService pool=Executors.newFixedThreadPool(2);CountDownLatch admitted=new CountDownLatch(1),commit=new CountDownLatch(1);
        try {
            Future<?> receive=pool.submit(()->new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource())).execute(tx->{
                raw(2);journal.event(envelope(2));admitted.countDown();
                try {assertTrue(commit.await(5,TimeUnit.SECONDS));}catch(InterruptedException e){throw new RuntimeException(e);}return null;
            }));
            assertTrue(admitted.await(5,TimeUnit.SECONDS));
            Future<?> close=pool.submit(()->journal.close(verified(first.getString("eventId"))));
            commit.countDown();receive.get(5,TimeUnit.SECONDS);close.get(5,TimeUnit.SECONDS);
            assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM real_time_alarm WHERE is_handled=1",Integer.class));
            assertTrue(journal.openEventIds().isEmpty());
        } finally {commit.countDown();pool.shutdownNow();}
    }

    @Test void closureFailureRollsBackAllRawUpdatesAndLeavesCaseOpenForRecovery() {
        JSONObject first=envelope();journal.event(first);journal.event(envelope(2));
        assertThrows(IllegalStateException.class,()->journal.close(verified(first.getString("eventId"))));
        assertEquals(0,jdbc.queryForObject("SELECT is_handled FROM real_time_alarm WHERE id=1",Integer.class));
        assertEquals(0,jdbc.queryForObject("SELECT MAX(closure_version) FROM helmet_event_link",Integer.class));
        assertEquals(1,journal.openEventIds().size());
        raw(2);journal.close(verified(first.getString("eventId")));
        assertTrue(journal.openEventIds().isEmpty());
    }

    @Test void sosRepeatedSourcesAlsoCloseTogetherWithoutChangingTheirDescriptions() {
        jdbc.execute("CREATE TABLE sos_alarm_record (id BIGINT PRIMARY KEY,process_status INT,handler VARCHAR(64),handle_time TIMESTAMP,update_by VARCHAR(64),update_time TIMESTAMP,create_by VARCHAR(64),del_flag VARCHAR(1),description VARCHAR(100))");
        for(long id=1;id<=2;id++) {
            jdbc.update("INSERT INTO sos_alarm_record (id,process_status,create_by,del_flag,description) VALUES (?,0,'direct-helmet','0','original-sos')",id);
            JSONObject report=envelope(id);report.put("sourceRecordType","sos_alarm_record");report.put("act","ca_sip_sos");journal.event(report);
        }
        journal.close(verified("HE-test"));
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM sos_alarm_record WHERE process_status=1 AND description='original-sos'",Integer.class));
    }
}
