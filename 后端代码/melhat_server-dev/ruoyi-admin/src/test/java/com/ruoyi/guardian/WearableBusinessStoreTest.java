package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.melhat.direct.HelmetMediaStore;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WearableBusinessStoreTest {
    @TempDir Path directory;
    private static final String KEY=Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.UTF_8));
    private JdbcTemplate database(){return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE","sa",""));}
    private JSONObject empty(){return object("version",1,"seq",0,"stations",new JSONArray(),"people",new JSONArray(),"devices",new JSONArray(),"events",new JSONArray(),"locations",new JSONArray());}

    @Test void importsLegacyRowsOnceAndNeverRewritesOrResurrectsTheJson() throws Exception {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc);
        Path file=directory.resolve("guardian-state.json");JSONObject old=empty();
        rows(old,"events").add(object("id","real-event","deviceId","real-belt","siteId","site-1","timeline",JSONArray.parseArray("[{\"text\":\"received\"}]")));
        Files.write(file,old.toJSONString().getBytes(StandardCharsets.UTF_8));
        WearableBusinessStore.Snapshot first=store.load("guardian",file,this::empty);
        assertEquals(old,first.state);assertTrue(Files.exists(directory.resolve("guardian-state.json.pre-sql.bak")));
        first.state.getJSONArray("events").getJSONObject(0).put("status","已核验");
        store.save("guardian",first.revision,first.state,null);
        Files.write(file,"not valid JSON".getBytes(StandardCharsets.UTF_8));
        WearableBusinessStore.Snapshot again=new WearableBusinessStore(jdbc).load("guardian",file,this::empty);
        assertEquals("已核验",again.state.getJSONArray("events").getJSONObject(0).getString("status"));
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event",Integer.class));
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event_action",Integer.class));
        assertEquals("not valid JSON",new String(Files.readAllBytes(file),StandardCharsets.UTF_8));
    }

    @Test void emptyProductionDatabaseAndRestartHaveNoDemoData() {
        JdbcTemplate jdbc=database();GuardianStore first=new GuardianStore(mock(GuardianHatArchive.class),new WearableBusinessStore(jdbc));
        ReflectionTestUtils.setField(first,"file",directory.resolve("absent.json"));
        JSONObject one=first.snapshot();assertTrue(rows(one,"devices").isEmpty());assertTrue(rows(one,"events").isEmpty());assertTrue(rows(one,"stations").isEmpty());
        GuardianStore restarted=new GuardianStore(mock(GuardianHatArchive.class),new WearableBusinessStore(jdbc));
        ReflectionTestUtils.setField(restarted,"file",directory.resolve("absent.json"));
        assertEquals(one,restarted.snapshot());assertFalse(Files.exists(directory.resolve("absent.json")));
    }

    @Test void corruptLegacySourceDoesNotCreateAnImportMarkerOrSeed() throws Exception {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc);Path file=directory.resolve("corrupt.json");Files.write(file,"{broken".getBytes(StandardCharsets.UTF_8));
        assertThrows(IllegalStateException.class,()->store.load("guardian",file,this::empty));
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_meta",Integer.class));
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event",Integer.class));
    }

    @Test void sqlWriteAndDependentArchiveRollbackTogetherAndRejectStaleWriters() {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc);
        WearableBusinessStore.Snapshot first=store.load("guardian",null,this::empty);
        first.state.getJSONArray("events").add(object("id","failed-event"));
        assertThrows(IllegalStateException.class,()->store.save("guardian",first.revision,first.state,()->{throw new IllegalStateException("archive failure");}));
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event",Integer.class));
        assertEquals(first.revision,store.read("guardian").revision);
        store.save("guardian",first.revision,first.state,null);
        assertThrows(IllegalStateException.class,()->store.save("guardian",first.revision,empty(),null));
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_event",Integer.class));
    }

    @Test void beltHistorySurvivesWorkingSetTrimmingAndPreservesObservedTime() {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc);
        WearableBusinessStore.Snapshot first=store.load("guardian",null,this::empty);
        rows(first.state,"locations").add(object("id","LOC42","deviceId","belt","personId","P1","siteId","site-1","time","2026-10-26 09:00:00","lng","110","lat","30","source","direct-belt"));
        long revision=store.save("guardian",first.revision,first.state,null);
        rows(first.state,"locations").clear();store.save("guardian",revision,first.state,null);
        long at=Instant.parse("2026-10-26T01:00:00Z").toEpochMilli();
        List<JSONObject> rows=store.locations(null,"belt",at,at+1,at-1,"",10);
        assertEquals(1,rows.size());assertEquals("LOC42",rows.get(0).getString("id"));assertEquals(at,rows.get(0).getLongValue("queryMillis"));
        assertEquals("P1",rows.get(0).getString("personId"));
    }

    @Test void prependingALocationDoesNotRewriteExistingHistoryRows() {
        JdbcTemplate jdbc=spy(database());WearableBusinessStore store=new WearableBusinessStore(jdbc);
        WearableBusinessStore.Snapshot initial=store.load("guardian",null,this::empty);
        rows(initial.state,"locations").add(object("id","LOC1","deviceId","belt","receivedMillis",1000));
        rows(initial.state,"locations").add(object("id","LOC2","deviceId","belt","receivedMillis",2000));
        long revision=store.save("guardian",initial.revision,initial.state,null);clearInvocations(jdbc);
        rows(initial.state,"locations").add(0,object("id","LOC3","deviceId","belt","receivedMillis",3000));
        store.save("guardian",revision,initial.state,null);
        long historyWrites=mockingDetails(jdbc).getInvocations().stream().filter(call->"update".equals(call.getMethod().getName())&&call.getMethod().isVarArgs()&&call.getArguments().length>0&&String.valueOf(call.getArguments()[0]).startsWith("INSERT INTO wearable_location ")).count();
        assertEquals(1,historyWrites);
        assertEquals("LOC3",store.read("guardian").state.getJSONArray("locations").getJSONObject(0).getString("id"));
    }

    @Test void privateMediaMigratesEncryptedAndSurvivesRestartWithoutJsonWrites() throws Exception {
        JdbcTemplate jdbc=database();Path file=directory.resolve("private.json");JSONObject media=object("accounts",object("helmet",object("password","private-password","sipId","sip-helmet")),"commands",new JSONObject(),"eventCursor",12);
        Files.write(file,media.toJSONString().getBytes(StandardCharsets.UTF_8));
        HelmetMediaStore store=new HelmetMediaStore(file.toString(),directory.resolve("public").toString(),new WearableBusinessStore(jdbc,KEY));
        assertEquals(media,store.snapshot());
        String encrypted=jdbc.queryForObject("SELECT body FROM wearable_media_account",String.class);assertFalse(encrypted.contains("private-password"));assertTrue(encrypted.startsWith("enc:v1:"));
        store.update(state->{state.put("eventCursor",20);return null;});
        assertEquals(media,JSONObject.parseObject(new String(Files.readAllBytes(file),StandardCharsets.UTF_8)));
        HelmetMediaStore again=new HelmetMediaStore(file.toString(),directory.resolve("public").toString(),new WearableBusinessStore(jdbc,KEY));
        assertEquals(20,again.snapshot().getIntValue("eventCursor"));
        String wrong=Base64.getEncoder().encodeToString(new byte[32]);
        assertThrows(IllegalStateException.class,()->new WearableBusinessStore(jdbc,wrong).read("media"));
    }

    @Test void missingMediaKeyFailsBeforeCommittingImport() throws Exception {
        JdbcTemplate jdbc=database();Path file=directory.resolve("private.json");Files.write(file,object("accounts",object("helmet",object("password","secret"))).toJSONString().getBytes(StandardCharsets.UTF_8));
        assertThrows(IllegalStateException.class,()->new WearableBusinessStore(jdbc).load("media",file,JSONObject::new));
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_business_meta",Integer.class));
        assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_media_account",Integer.class));
    }

    @Test void receiptJournalIsIdempotentButDoesNotDropEqualIndependentReports() {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc);JSONObject payload=object("act","ca_report_location","battery",80);
        long first=store.appendDeviceReport("receipt-1","direct-belt","belt",payload);
        assertEquals(first,store.appendDeviceReport("receipt-1","direct-belt","belt",payload));
        long second=store.appendDeviceReport("receipt-2","direct-belt","belt",payload);assertTrue(second>first);
        assertThrows(IllegalStateException.class,()->store.appendDeviceReport("receipt-1","direct-belt","belt",object("battery",12)));
        assertEquals(2,store.pendingReports(0,10).size());store.markReportProcessed("receipt-1");
        assertEquals("receipt-2",store.pendingReports(0,10).get(0).getString("receiptId"));
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Integer.class));
    }

    @Test void receiptRollbackReloadsGuardianAndMediaCachesBeforeRetry() {
        JdbcTemplate jdbc=database();WearableBusinessStore sql=new WearableBusinessStore(jdbc,KEY);
        GuardianStore guardian=new GuardianStore(mock(GuardianHatArchive.class),sql);ReflectionTestUtils.setField(guardian,"file",directory.resolve("absent.json"));
        HelmetMediaStore media=new HelmetMediaStore(directory.resolve("absent-media.json").toString(),directory.resolve("public").toString(),sql);
        guardian.snapshot();media.snapshot();
        sql.appendDeviceReport("rollback-1","direct-belt","belt",object("battery",70));
        assertThrows(IllegalStateException.class,()->sql.processReport("rollback-1",()->{
            guardian.update(state->{state.put("clock",123);return true;});
            media.update(state->{state.put("eventCursor",33);return null;});
            throw new IllegalStateException("late failure");
        }));
        assertEquals(0,guardian.snapshot().getIntValue("clock"));assertFalse(media.snapshot().containsKey("eventCursor"));
        assertEquals(1,sql.pendingReports(0,10).size());
        assertTrue(sql.processReport("rollback-1",()->guardian.update(state->{state.put("clock",124);return true;})));
        assertFalse(sql.processReport("rollback-1",()->fail("processed receipt was replayed")));
        assertEquals(124,guardian.snapshot().getIntValue("clock"));assertTrue(sql.pendingReports(0,10).isEmpty());
    }

    @Test void currentSqlExportIncludesNewBusinessAndPendingReportsNotOldFiles() throws Exception {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc,KEY);
        WearableBusinessStore.Snapshot guardian=store.load("guardian",null,this::empty);rows(guardian.state,"events").add(object("id","after-cutover"));store.save("guardian",guardian.revision,guardian.state,null);
        store.load("media",null,()->object("accounts",object("helmet",object("password","rollback-secret"))));
        store.appendDeviceReport("pending-1","direct-belt","belt",object("battery",70));
        Path out=directory.resolve("export");WearableBusinessExport.export(jdbc,KEY,out);
        JSONObject manifest=JSONObject.parseObject(new String(Files.readAllBytes(out.resolve("manifest.json")),StandardCharsets.UTF_8));
        assertEquals(1,manifest.getIntValue("pendingReports"));assertTrue(new String(Files.readAllBytes(out.resolve("guardian-state.json")),StandardCharsets.UTF_8).contains("after-cutover"));
        assertTrue(new String(Files.readAllBytes(out.resolve("helmet-media-private.json")),StandardCharsets.UTF_8).contains("rollback-secret"));
        assertEquals(1,Files.readAllLines(out.resolve("device-reports.jsonl")).size());
    }

    @Test void controlledImportUsesExactRevisionAndDoesNotTouchMediaUnlessExplicit() throws Exception {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc,KEY);store.load("guardian",null,this::empty);
        WearableBusinessStore.Snapshot media=store.load("media",null,()->object("accounts",object("helmet",object("password","original-secret"))));
        new WearableMaintenance(jdbc);
        Path out=directory.resolve("import");WearableBusinessExport.export(jdbc,KEY,out);
        JSONObject guardian=empty();guardian.put("clock",321);Files.write(out.resolve("guardian-state.json"),guardian.toJSONString().getBytes(StandardCharsets.UTF_8));
        WearableBusinessImport.importCurrent(jdbc,KEY,out);
        assertEquals(321,store.read("guardian").state.getIntValue("clock"));assertEquals(media.revision,store.read("media").revision);
        assertThrows(IllegalStateException.class,()->WearableBusinessImport.importCurrent(jdbc,KEY,out));
        Path resumed=directory.resolve("re-upgrade");WearableBusinessExport.export(jdbc,KEY,resumed);
        JSONObject manifest=JSONObject.parseObject(new String(Files.readAllBytes(resumed.resolve("manifest.json")),StandardCharsets.UTF_8));manifest.put("importMedia",true);
        Files.write(resumed.resolve("manifest.json"),manifest.toJSONString().getBytes(StandardCharsets.UTF_8));
        Files.write(resumed.resolve("helmet-media-private.json"),object("accounts",object("helmet",object("password","updated-while-legacy"))).toJSONString().getBytes(StandardCharsets.UTF_8));
        WearableBusinessImport.importCurrent(jdbc,KEY,resumed);
        assertEquals("updated-while-legacy",store.read("media").state.getJSONObject("accounts").getJSONObject("helmet").getString("password"));
    }

    @Test void cleanupImportRejectsAReportReceivedAfterTheExport() throws Exception {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc,KEY);WearableBusinessStore.Snapshot initial=store.load("guardian",null,this::empty);
        Path out=directory.resolve("unsafe-import");WearableBusinessExport.export(jdbc,KEY,out);
        store.appendDeviceReport("new-report","direct-belt","belt",object("battery",60));
        assertThrows(IllegalStateException.class,()->WearableBusinessImport.importCurrent(jdbc,KEY,out));
        store.markReportProcessed("new-report");
        assertThrows(IllegalStateException.class,()->WearableBusinessImport.importCurrent(jdbc,KEY,out));
        assertEquals(initial.revision,store.read("guardian").revision);assertFalse(Files.exists(out.resolve("import-result.json")));
    }

    @Test void pausedImportPreservesNewlyQueuedReportsForResume() throws Exception {
        JdbcTemplate jdbc=database();WearableBusinessStore store=new WearableBusinessStore(jdbc,KEY);store.load("guardian",null,this::empty);
        new WearableMaintenance(jdbc).setPaused(true,object("id","demo-system"));
        Path out=directory.resolve("paused-import");WearableBusinessExport.export(jdbc,KEY,out);
        long received=store.appendDeviceReport("during-pause","direct-belt","belt",object("battery",71));
        JSONObject result=WearableBusinessImport.importCurrent(jdbc,KEY,out);
        assertTrue(result.getBooleanValue("maintenancePaused"));assertEquals(received,result.getLongValue("reportWatermark"));
        assertEquals("during-pause",store.pendingReports(0,10).get(0).getString("receiptId"));
    }
}
