package com.ruoyi.cluster;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.common.database.DatabaseDialect;
import com.ruoyi.guardian.ClusterMaintenanceGuard;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
class ClusterRoutingContractTest {
    ClusterDatabase db;
    ClusterProperties pa,pb;
    ClusterIdentity a,b;
    DeviceOwnership oa,ob;
    DeviceCommandRouter ra,rb;
    @BeforeEach void setup() {
        DriverManagerDataSource ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        JdbcTemplate jdbc=new JdbcTemplate(ds);
        new SchemaLifecycle(jdbc).migrate(Collections.singletonList(SchemaLifecycle.resource(DatabaseDialect.H2,"20261103_cluster_routing")));
        db=new ClusterDatabase(jdbc);
        pa=props("a");
        pb=props("b");
        a=new ClusterIdentity(pa,db);
        b=new ClusterIdentity(pb,db);
        a.start();
        b.start();
        oa=new DeviceOwnership(db,a);
        ob=new DeviceOwnership(db,b);
        ra=new DeviceCommandRouter(db,a,pa,oa);
        rb=new DeviceCommandRouter(db,b,pb,ob);
    }
    static ClusterProperties props(String id) {
        ClusterProperties p=new ClusterProperties();
        p.setEnabled(true);
        p.setNodeId(id);
        return p;
    }
    @Test void duplicateNodeIdRejectedAndRestartHasNewGeneration() {
        assertThrows(IllegalStateException.class,()->new ClusterIdentity(pa,db).start());
        a.stop();
        ClusterIdentity newer=new ClusterIdentity(pa,db);
        newer.start();
        assertNotEquals(a.generation(),newer.generation());
        a.renew();
        assertFalse(a.isActive());
        assertTrue(newer.isActive());
    }
    @Test void takeoverFencesOldReportAndLateClose() {
        OwnerToken old=oa.claimLogin("helmet","h","s1",30000,new JSONObject());
        assertTrue(ob.readPresence("helmet","h").getBooleanValue("online"));
        OwnerToken fresh=ob.claimLogin("helmet","h","s2",30000,new JSONObject());
        AtomicInteger append=new AtomicInteger();
        assertThrows(IllegalArgumentException.class,()->oa.receiveUnderOwner(old,new JSONObject(),append::incrementAndGet));
        assertEquals(0,append.get());
        assertFalse(oa.release(old));
        assertTrue(ob.current(fresh));
    }
    @Test void receiptAndStatusRollbackTogether() {
        OwnerToken owner=oa.claimLogin("belt","b","s",30000,new JSONObject());
        db.jdbc.execute("CREATE TABLE test_receipt(id INT PRIMARY KEY)");
        assertThrows(IllegalStateException.class,()->oa.receiveUnderOwner(owner,new JSONObject(),()-> {
            db.jdbc.update("INSERT INTO test_receipt VALUES(1)");
            throw new IllegalStateException("rollback");
        }
        ));
        assertEquals(0,db.jdbc.queryForObject("SELECT COUNT(*) FROM test_receipt",Integer.class));
    }
    @Test void remoteSubmitIsDurableAndOnlyOwnerSendsOnce() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        AtomicInteger count=new AtomicInteger();
        ra.register("helmet",(o,w,t,fence)->count.incrementAndGet());
        JSONObject wire=JSONObject.parseObject("{\"cmd\":\"photo\"}");
        rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),wire);
        rb.dispatchOwnedBatch();
        assertEquals(0,count.get());
        ra.dispatchOwnedBatch();
        ra.dispatchOwnedBatch();
        assertEquals(1,count.get());
        assertEquals("SENT",rb.read("c").getString("deliveryStatus"));
        assertEquals("c",rb.submit("other","scope","fingerprint","helmet","h",new JSONObject(),wire).getString("id"));
        assertThrows(IllegalArgumentException.class,()->rb.submit("other","scope","different","helmet","h",new JSONObject(),wire));
    }
    @Test void earlyReceiptCannotBeOverwrittenAndUnrelatedReceiptDoesNothing() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject());
        ra.register("helmet",(o,w,t,fence)-> {
            rb.acknowledge("c","other",true);
            assertEquals("DISPATCHING",rb.read("c").getString("deliveryStatus"));
            rb.acknowledge("c","h",true);
        }
        );
        ra.dispatchOwnedBatch();
        assertEquals("ACKNOWLEDGED",rb.read("c").getString("deliveryStatus"));
    }
    @Test void interruptedAttemptIsUnknownAndNeverRequeued() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject());
        db.jdbc.update("UPDATE wearable_transport_command SET delivery_status='DISPATCHING',attempt_until=0 WHERE command_id='c'");
        AtomicInteger count=new AtomicInteger();
        ra.register("helmet",(o,w,t,fence)->count.incrementAndGet());
        ra.dispatchOwnedBatch();
        assertEquals("UNKNOWN",rb.read("c").getString("deliveryStatus"));
        assertEquals(0,count.get());
    }
    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void maintenanceAfterDurableClaimFinishesBeforeSend(boolean pauseGlobally) {
        SchemaLifecycle.ensure(db.jdbc,"20261026_wearable_business");
        SchemaLifecycle.ensure(db.jdbc,"20261102_fuda_push_outbox");
        SchemaLifecycle.ensure(db.jdbc,"20261103_cluster_coordination");
        db.jdbc.update("INSERT INTO wearable_runtime_control(control_key,mode,updated_at) VALUES('global','ACTIVE',0)");
        ClusterWorkCoordinator coordinator=new ClusterWorkCoordinator(db,a);
        AtomicInteger guardCalls=new AtomicInteger();
        ClusterMaintenanceGuard guard=new ClusterMaintenanceGuard(a,coordinator,db,null) {
            @Override public void dispatch(String commandId) {
                if(guardCalls.incrementAndGet()==2) {
                    assertEquals("DISPATCHING",rb.read(commandId).getString("deliveryStatus"));
                    if(pauseGlobally) {
                        db.jdbc.update("UPDATE wearable_runtime_control SET mode='PAUSED' WHERE control_key='global'");
                    } else {
                        a.beginDrain();
                    }
                }
                super.dispatch(commandId);
            }
        };
        ReflectionTestUtils.setField(ra,"guard",guard);
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject());
        AtomicInteger sends=new AtomicInteger();
        ra.register("helmet",(o,w,t,fence)->sends.incrementAndGet());

        ra.dispatchOwnedBatch();
        ra.recoverAttempts();

        assertEquals(2,guardCalls.get());
        assertEquals(0,sends.get());
        assertEquals("FAILED_BEFORE_SEND",rb.read("c").getString("deliveryStatus"));
        JSONObject status=coordinator.status(!pauseGlobally);
        assertEquals(0,status.getIntValue("uncertainTransport"));
        assertTrue(status.getBooleanValue("quiescent"));
    }
    @Test void senderFailureRemainsUnknownAndNeverRetries() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject());
        AtomicInteger sends=new AtomicInteger();
        ra.register("helmet",(o,w,t,fence)-> {
            sends.incrementAndGet();
            throw new java.io.IOException("Device send failed");
        });

        ra.dispatchOwnedBatch();
        ra.dispatchOwnedBatch();

        assertEquals(1,sends.get());
        assertEquals("UNKNOWN",rb.read("c").getString("deliveryStatus"));
    }
    @Test void changedOwnerCancelsQueuedEvenWhenOriginalWorkerIsGone() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject());
        ob.claimLogin("helmet","h","replacement",30000,new JSONObject());rb.recoverAttempts();
        assertEquals("CANCELLED",rb.read("c").getString("deliveryStatus"));
    }
    @Test void expiredAttemptCannotWriteEvenIfOwnerStillCurrent() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        rb.submit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject());
        AtomicInteger count=new AtomicInteger();
        ra.register("helmet",(o,w,t,fence)-> {
            db.jdbc.update("UPDATE wearable_transport_command SET attempt_until=0 WHERE command_id='c'");
            fence.run();
            count.incrementAndGet();
        }
        );
        ra.dispatchOwnedBatch();
        ra.recoverAttempts();
        assertEquals(0,count.get());
        assertEquals("UNKNOWN",rb.read("c").getString("deliveryStatus"));
    }
    @Test void configurationAndMissingSchemaFailClearly() {
        ClusterProperties invalid=new ClusterProperties();
        invalid.setEnabled(true);
        assertThrows(IllegalStateException.class,invalid::validate);
        invalid.setNodeId("node");
        invalid.setSendTimeoutMillis(130000);
        assertThrows(IllegalStateException.class,invalid::validate);
        db.jdbc.execute("DROP TABLE wearable_cluster_node");
        assertThrows(IllegalStateException.class,()->new ClusterIdentity(props("missing"),db).start());
    }
    @Test void admissionFailureRollsBackTransport() {
        oa.claimLogin("helmet","h","s",30000,new JSONObject());
        assertThrows(IllegalStateException.class,()->rb.admit("c","scope","fingerprint","helmet","h",new JSONObject(),new JSONObject(),false,()-> {
            throw new IllegalStateException("disk");
        }
        ));
        assertNull(rb.read("c"));
    }
    @Test void drainRejectsNewLoginsButKeepsCurrentReports() {
        OwnerToken old=oa.claimLogin("helmet","h","s",30000,new JSONObject());
        a.beginDrain();
        assertThrows(IllegalStateException.class,()->oa.claimLogin("helmet","n","s",30000,new JSONObject()));
        oa.receiveUnderOwner(old,new JSONObject(),()-> {
        }
        );
    }
}
