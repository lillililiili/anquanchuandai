package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.melhat.direct.DirectHelmetMessage;
import com.ruoyi.melhat.direct.DirectHelmetPersistence;
import com.ruoyi.melhat.direct.DirectHelmetTelemetryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Collections;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectHelmetLocalRecordingTest {
    @TempDir Path directory;
    JdbcTemplate jdbc;
    WearableBusinessStore journal;
    GuardianStore store;
    GuardianIngest ingest;
    WearableReportDelivery delivery;
    WearableMaintenance maintenance;
    DirectHelmetPersistence persistence;
    DirectHelmetTelemetryService telemetry;

    @BeforeEach void setup() throws Exception {
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        journal=new WearableBusinessStore(jdbc);
        store=new GuardianStore(mock(GuardianHatArchive.class),journal);
        ReflectionTestUtils.setField(store,"file",directory.resolve("absent.json"));
        JSONObject seed=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("guardian-seed.json").getInputStream(),StandardCharsets.UTF_8));
        JSONObject device=find(seed,"devices","RL-H001");device.put("source","DIRECT_HELMET");device.put("deviceNumber","RL-H001");
        store.replace(seed);ingest=new GuardianIngest(store);
        SafetyHatInfoMapper hats=mock(SafetyHatInfoMapper.class);SafetyHatInfo hat=new SafetyHatInfo();
        hat.setId(1L);hat.setHatNumber("RL-H001");hat.setDelFlag("0");hat.setCreateBy("direct-helmet");
        when(hats.findIncludingDeleted("RL-H001")).thenReturn(Collections.singletonList(hat));
        persistence=mock(DirectHelmetPersistence.class);telemetry=new DirectHelmetTelemetryService(hats,persistence,ingest);
        ObjectProvider<DirectHelmetTelemetryService> helmets=mock(ObjectProvider.class);when(helmets.getObject()).thenReturn(telemetry);
        delivery=new WearableReportDelivery(journal,ingest,helmets,mock(ObjectProvider.class));
        maintenance=mock(WearableMaintenance.class);ReflectionTestUtils.setField(delivery,"maintenance",maintenance);
    }
    JSONObject device(){return find(store.snapshot(),"devices","RL-H001");}
    JSONObject report(String type){return object("act","toggle_localrecord","device_id","RL-H001","type",type);}
    JSONObject context(String at){JSONObject c=ingest.captureDirect("RL-H001");c.put("receivedAt",at);return c;}

    @Test void absentStateHasNoFalseDefaultAndOnlyProtocolZeroOrOneIsAccepted(){
        assertFalse(device().containsKey("localRecording"));
        for(Object value:new Object[]{"0","1",0,1})assertNotNull(DirectHelmetMessage.parse(object("act","toggle_localrecord","type",value).toJSONString()));
        for(Object value:new Object[]{null,"",true,false,"2","01","0.0","recording",new JSONObject()})
            assertThrows(IllegalArgumentException.class,()->DirectHelmetMessage.parse(object("act","toggle_localrecord","type",value).toJSONString()));
        assertThrows(IllegalArgumentException.class,()->ingest.directLocalRecording("RL-H001","1",new JSONObject()));
    }

    @Test void pausedReceiptReplaysCapturedOwnershipOnceWithoutLocationAlarmOrMediaSideEffects(){
        JSONObject before=store.snapshot();String originalOwner=ingest.captureDirect("RL-H001").getString("personId");
        when(maintenance.paused()).thenReturn(true);
        JSONObject raw=report("0");raw.put("x_point",30);raw.put("y_point",120);raw.put("bat_l",1);raw.put("personId","forged-person");
        assertFalse(delivery.helmet("RL-H001",raw.toJSONString()));
        assertFalse(device().containsKey("localRecording"));
        JSONObject queued=journal.pendingReports(0,100).get(0);
        assertEquals(raw,queued.getJSONObject("payload").getJSONObject("raw"));
        JSONObject captured=queued.getJSONObject("payload").getJSONObject("context");
        store.update(s->{for(Object row:rows(s,"bindings")){JSONObject b=(JSONObject)row;if("RL-H001".equals(b.getString("deviceId")))b.put("end",Instant.now().toString());}return true;});
        when(maintenance.paused()).thenReturn(false);delivery.recover();
        JSONObject observed=device().getJSONObject("localRecording");assertEquals("RECORDING",observed.getString("state"));
        assertEquals(originalOwner,observed.getString("personId"));assertEquals(captured.get("bindingId"),observed.get("bindingId"));
        assertEquals(captured.get("receivedAt"),observed.get("receivedAt"));assertEquals("RECEIVED_AT",observed.get("timeBasis"));
        JSONObject stable=store.snapshot();delivery.recover();delivery.deliver(queued);
        assertEquals(stable,store.snapshot());assertTrue(journal.pendingReports(0,100).isEmpty());
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NOT NULL",Integer.class));
        for(String field:new String[]{"locations","events","media","calls"})assertEquals(before.get(field),stable.get(field));
        for(String field:new String[]{"locationReportedAt","latitude","longitude","battery","batteryReportedAt","isWearedReportedAt"})
            assertEquals(find(before,"devices","RL-H001").get(field),device().get(field));
        verifyNoInteractions(persistence);
    }

    @Test void olderOrDuplicateRecoveryCannotOverwriteNewerReportAndNormalTelemetryCannotForgeIt(){
        JSONObject old=context("2026-11-02T01:00:00Z"),recent=context("2026-11-02T01:00:01Z");
        ingest.directLocalRecording("RL-H001","0",old);ingest.directLocalRecording("RL-H001","1",recent);
        JSONObject expected=device().getJSONObject("localRecording");int seq=store.snapshot().getIntValue("seq");
        ingest.directLocalRecording("RL-H001","0",old);ingest.directLocalRecording("RL-H001","1",recent);
        assertEquals(seq,store.snapshot().getIntValue("seq"));assertEquals(expected,device().getJSONObject("localRecording"));
        ingest.directTelemetry("RL-H001",object("localRecording",object("state","RECORDING")));
        assertEquals(expected,device().getJSONObject("localRecording"));assertEquals("STOPPED",expected.getString("state"));
        GuardianStore restarted=new GuardianStore(mock(GuardianHatArchive.class),new WearableBusinessStore(jdbc));
        ReflectionTestUtils.setField(restarted,"file",directory.resolve("absent.json"));
        JSONObject after=find(restarted.snapshot(),"devices","RL-H001");
        assertEquals(expected,after.getJSONObject("localRecording"));assertFalse(after.getBooleanValue("online"));
    }

    @Test void aNewUnassignedReportDoesNotBorrowAnEndedBinding(){
        store.update(s->{for(Object row:rows(s,"bindings")){JSONObject b=(JSONObject)row;if("RL-H001".equals(b.getString("deviceId")))b.put("end","2026-11-01T00:00:00Z");}return true;});
        JSONObject unassigned=context("2026-11-02T01:00:00Z");
        ingest.directLocalRecording("RL-H001","0",unassigned);
        JSONObject observed=device().getJSONObject("localRecording");
        assertEquals("",observed.getString("personId"));assertNull(observed.get("bindingId"));
        assertEquals("DIRECT_HELMET",observed.getString("source"));assertEquals("toggle_localrecord",observed.getString("reportAct"));
    }

    @Test void legacyScopedSnapshotCannotAddOrReplaceTheDeviceObservation() throws Exception {
        JSONObject master=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(),StandardCharsets.UTF_8));
        migrate(master);
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(master);
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        ReflectionTestUtils.setField(access,"demoMode",true); // This isolated fixture intentionally uses the archived seed.
        GuardianAccess.Context admin=access.context(find(master,"accounts","demo-system"));
        for(boolean existing:new boolean[]{false,true}) {
            if(existing)ingest.directLocalRecording("RL-H001","1",context("2026-11-02T01:00:00Z"));
            JSONObject before=store.snapshot(),supplied=admin.snapshot(before);
            int seq=before.getIntValue("seq");supplied.put("seq",seq+1);
            find(supplied,"devices","RL-H001").put("localRecording",object("state","RECORDING","rawType","0"));
            assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->store.replaceScoped(supplied,seq,admin)).code);
            JSONObject after=store.snapshot();
            assertEquals(seq,after.getIntValue("seq"));
            for(String key:new String[]{"devices","locations","events","media","calls"})assertEquals(before.get(key),after.get(key));
        }
    }
}
