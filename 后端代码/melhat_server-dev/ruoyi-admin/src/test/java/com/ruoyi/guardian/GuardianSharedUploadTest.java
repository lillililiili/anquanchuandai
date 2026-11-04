package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.io.ByteArrayInputStream;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianSharedUploadTest {
    @TempDir Path root;
    private static final String ID="upload-12345678-1234-1234-1234-123456789abc";
    private static final byte[] PNG={(byte)137,80,78,71,13,10,26,10,1};
    private static final byte[] OTHER={(byte)137,80,78,71,13,10,26,10,2};
    private JdbcTemplate database(){return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:upload"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE","sa",""));}
    private GuardianStore store(JdbcTemplate jdbc,GuardianHatArchive hats,String node){
        GuardianStore store=new GuardianStore(hats,new WearableBusinessStore(jdbc));
        ReflectionTestUtils.setField(store,"file",root.resolve(node+"-absent.json"));
        // Independent JVMs do not share the process-local business monitor.
        ReflectionTestUtils.setField(store,"lock",new Object());
        store.snapshot();return store;
    }
    private GuardianEvents service(GuardianStore store,GuardianFiles files){
        JSONObject master=object("sites",JSONArray.of(object("id","site-1","enabled",true)),
                "roles",JSONArray.of(object("id","uploader","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-1"),"operations",JSONArray.of("events:observe"))))));
        master.put("accounts",JSONArray.of(actor("actor-a"),actor("actor-b")));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(master);
        return new GuardianEvents(store,new GuardianAccess(ledger,mock(AdminQueryService.class)),files);
    }
    private JSONObject actor(String id){return object("id",id,"name",id,"enabled",true,"roleIds",JSONArray.of("uploader"));}
    @Test void staleCompetingActorCannotReplaceAcceptedOwnersBytes() throws Exception {
        JdbcTemplate db=database();GuardianStore a=store(db,mock(GuardianHatArchive.class),"a"),b=store(db,mock(GuardianHatArchive.class),"b");
        GuardianEvents one=service(a,new GuardianFiles(root,new GuardianFileCatalog(db))),two=service(b,new GuardianFiles(root,new GuardianFileCatalog(db)));
        CountDownLatch reading=new CountDownLatch(1),accepted=new CountDownLatch(1);
        ByteArrayInputStream delayed=new ByteArrayInputStream(OTHER){
            @Override public synchronized int read(byte[] bytes,int off,int len){reading.countDown();await(accepted);return super.read(bytes,off,len);}
        };
        ExecutorService pool=Executors.newSingleThreadExecutor();
        try {
            Future<?> loser=pool.submit(()->two.upload(actor("actor-b"),ID,"image/png",delayed));
            assertTrue(reading.await(10,TimeUnit.SECONDS));
            one.upload(actor("actor-a"),ID,"image/png",new ByteArrayInputStream(PNG));accepted.countDown();
            assertThrows(ExecutionException.class,()->loser.get(10,TimeUnit.SECONDS));
            assertEquals("actor-a",a.snapshot().getJSONObject("uploads").getJSONObject(ID).getString("ownerId"));
            assertArrayEquals(PNG,one.file(actor("actor-a"),ID).bytes);
            assertThrows(AdminQueryService.QueryFailed.class,()->two.file(actor("actor-b"),ID));
        } finally {accepted.countDown();pool.shutdownNow();}
    }
    @Test void failedMetadataSaveLeavesNoPointerOrOwnerAndSameIdCanBeRetried(){
        JdbcTemplate db=database();GuardianHatArchive hats=mock(GuardianHatArchive.class);
        GuardianStore store=store(db,hats,"a");GuardianFiles files=new GuardianFiles(root,new GuardianFileCatalog(db));GuardianEvents events=service(store,files);
        doThrow(new IllegalStateException("metadata dependent write failed")).when(hats).sync(any());
        assertThrows(RuntimeException.class,()->events.upload(actor("actor-a"),ID,"image/png",new ByteArrayInputStream(PNG)));
        assertNull(files.read(ID));assertNull(store.snapshot().getJSONObject("uploads").getJSONObject(ID));
        doNothing().when(hats).sync(any());
        events.upload(actor("actor-a"),ID,"image/png",new ByteArrayInputStream(PNG));
        assertArrayEquals(PNG,events.file(actor("actor-a"),ID).bytes);
    }
    private static void await(CountDownLatch latch){try{if(!latch.await(10,TimeUnit.SECONDS))throw new IllegalStateException("latch timeout");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new RuntimeException(e);}}
}
