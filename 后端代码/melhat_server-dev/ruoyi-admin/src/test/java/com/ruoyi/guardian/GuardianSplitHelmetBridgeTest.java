package com.ruoyi.guardian;

import com.alibaba.fastjson2.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianSplitHelmetBridgeTest {
    @TempDir Path dir;GuardianStore store;GuardianIngest ingest;HelmetBusinessJournal journal;JdbcTemplate jdbc;GuardianSplitHelmetBridge bridge;JSONObject master;
    @BeforeEach void setup()throws Exception{
        store=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(store,"file",dir.resolve("guardian.json"));
        JSONObject seed=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("guardian-seed.json").getInputStream(),StandardCharsets.UTF_8));
        JSONObject helmet=find(seed,"devices","RL-H001");helmet.put("source","SPLIT_HELMET");helmet.put("deviceNumber","RL-H001");store.replace(seed);
        ingest=new GuardianIngest(store);jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        journal=new HelmetBusinessJournal(jdbc);new ResourceDatabasePopulator(new ClassPathResource("db/20261116_split_helmet.sql")).execute(jdbc.getDataSource());
        master=object("devices",JSONArray.of(object("id","ledger-h","deviceNumber","RL-H001","source","SPLIT_HELMET","type","HELMET","siteId","s1","lifecycle","IN_USE")),"sites",JSONArray.of(object("id","s1","enabled",true)),"assignments",new JSONArray(),"history",new JSONArray());
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));bridge=new GuardianSplitHelmetBridge(ledger,ingest,store,journal,mock(HelmetEventDelivery.class),jdbc);
    }
    JSONObject envelope(String id,String kind,JSONObject payload){
        JSONObject captured=ingest.captureSplit("RL-H001");captured.put("siteId","s1");captured.put("personId","");captured.put("person",null);captured.put("bindingStart",null);captured.put("bindingEnd",null);
        return object("ingressId",id,"deviceId","RL-H001","kind",kind,"payload",payload,"captured",captured,"receivedAt","2026-11-15T12:02:00Z","receivedMillis",Instant.parse("2026-11-15T12:02:00Z").toEpochMilli(),"observedAt","2026-11-15T12:00:00Z");
    }
    @Test void onlyExplicitSplitAssetsAtEnabledSitesAreRegistered(){
        assertTrue(bridge.isRegistered("RL-H001"));assertFalse(bridge.isRegistered("OTHER"));
        rows(master,"devices").getJSONObject(0).put("source","DIRECT_HELMET");assertFalse(bridge.isRegistered("RL-H001"));
        rows(master,"devices").getJSONObject(0).put("source","SPLIT_HELMET");rows(master,"sites").getJSONObject(0).put("enabled",false);assertTrue(bridge.registered().isEmpty());assertTrue(bridge.ownsIdentity("RL-H001"));
    }
    @Test void durableAlarmDuplicatesAggregateWithoutLosingFallEvidenceAndCloseRawSources(){
        JSONObject first=envelope("ingress-one","sos",object("helmetSn","RL-H001","type","fall","timestamp",1794744000L,"peak",4.8,"ax",1.2,"ay",3.4,"az",4.5));
        bridge.ingest(first);bridge.ingest(first);JSONObject second=copy(first);second.put("ingressId","ingress-two");bridge.ingest(second);
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM split_helmet_event",Integer.class));
        JSONObject event=null;for(Object raw:rows(store.snapshot(),"events")){JSONObject e=(JSONObject)raw;if("split-helmet".equals(e.getString("protocol")))event=e;}
        assertNotNull(event);assertEquals(2,event.getIntValue("reportCount"));assertEquals("fall",event.getString("rawAlarmType"));assertEquals("2026-11-15T12:00:00Z",event.getString("observedAt"));assertEquals(4.8,event.getJSONObject("rawPayload").getDoubleValue("peak"));assertTrue(journal.pending().isEmpty());
        event.put("status","已核验");event.put("version",event.getIntValue("version")+1);event.put("verification",object("submittedAt","2026-11-15T13:00:00Z","actorId","reviewer"));journal.close(event);
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM split_helmet_event WHERE handled=1",Integer.class));assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM split_helmet_event WHERE body LIKE '%peak%'",Integer.class));
    }
    @Test void deviceCallEndDoesNotResolveBusinessAlarm(){
        bridge.ingest(envelope("ingress-sos","sosCall",object("helmetSn","RL-H001")));
        bridge.ingest(envelope("ingress-end","sosCallEnd",object("helmetSn","RL-H001")));
        for(Object raw:rows(store.snapshot(),"events")){JSONObject e=(JSONObject)raw;if(!"split-helmet".equals(e.getString("protocol")))continue;assertNotEquals("已核验",e.getString("status"));assertNotNull(e.get("deviceCallEndedAt"));}
        assertEquals(0,jdbc.queryForObject("SELECT handled FROM split_helmet_event",Integer.class));
    }
    @Test void gnssUsesDocumentedCoordinatesAndObservedTimeWithIdempotentHistory(){
        JSONObject envelope=envelope("ingress-gnss","gnss",object("helmetSn","RL-H001","longitude",116.4,"latitude",39.9));
        bridge.ingest(envelope);bridge.ingest(envelope);
        JSONObject fix=JSONObject.parseObject(jdbc.queryForObject("SELECT body FROM helmet_location_fix",String.class));
        assertEquals("WGS84",fix.getString("coordinateSystem"));assertEquals("2026-11-15T12:00:00Z",fix.getString("locationReportedAt"));assertEquals("2026-11-15T12:02:00Z",fix.getString("receivedAt"));assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_location_fix",Integer.class));
    }
    @Test void fileScopeUsesFrozenIssueHistoryAndNeverTodaysWearer(){
        rows(master,"assignments").add(object("id","a-old","deviceId","ledger-h","personId","old-ledger","startedAt","2026-11-01T00:00:00Z","endedAt","2026-11-10T00:00:00Z","active",false,"version",2));
        rows(master,"assignments").add(object("id","a-new","deviceId","ledger-h","personId","new-ledger","startedAt","2026-11-10T00:00:00Z","active",true,"version",1));
        rows(master,"history").add(object("assignmentId","a-old","action","ISSUE","siteId","old-site","personAreaId","old-area","personPortalId","OLD","personName","原领用人","assignmentVersion",1));
        rows(master,"history").add(object("assignmentId","a-new","action","ISSUE","siteId","new-site","personPortalId","NEW","personName","新领用人","assignmentVersion",1));
        JSONObject old=bridge.captureFile("RL-H001","2026-11-09T00:00:00Z");assertEquals("OLD",old.getString("personId"));assertEquals("old-site",old.getString("siteId"));assertEquals("old-area",old.getString("areaId"));
        assertEquals("NEW",bridge.captureFile("RL-H001","2026-11-10T00:00:00Z").getString("personId"));assertNull(bridge.captureFile("RL-H001","2026-10-01T00:00:00Z"));assertNull(bridge.captureFile("RL-H001","unknown"));
    }
}
