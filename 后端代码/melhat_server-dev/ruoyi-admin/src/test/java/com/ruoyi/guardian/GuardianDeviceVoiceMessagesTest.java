package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.HelmetMediaService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianDeviceVoiceMessagesTest {
    @TempDir Path directory;
    final String assetId="11111111-2222-4333-8444-555555555555";
    final String reference="https://media.example/helmet-media/files/"+assetId+"?token=private";
    JdbcTemplate jdbc;WearableBusinessStore journal;GuardianStore store;GuardianIngest ingest;
    HelmetMediaService media;GuardianDeviceVoiceMessages service;WearableReportDelivery delivery;
    JSONObject master,actor,grant;GuardianAccess access;WearableMaintenance maintenance;
    @BeforeEach void setup() throws Exception {
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        journal=new WearableBusinessStore(jdbc,java.util.Base64.getEncoder().encodeToString(new byte[32]));store=new GuardianStore(mock(GuardianHatArchive.class),journal);
        ReflectionTestUtils.setField(store,"file",directory.resolve("missing.json"));
        JSONObject seed=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("guardian-seed.json").getInputStream(),StandardCharsets.UTF_8));
        JSONObject device=find(seed,"devices","RL-H001");device.put("source","DIRECT_HELMET");device.put("siteId","site-1");store.replace(seed);
        actor=object("id","duty","enabled",true,"roleIds",JSONArray.of("voice-role"));
        grant=object("operations",JSONArray.of("communications:voice"),"siteIds",JSONArray.of("site-1"));
        master=object("accounts",JSONArray.of(actor),"roles",JSONArray.of(object("id","voice-role","enabled",true,"grants",JSONArray.of(grant))),
                "sites",JSONArray.of(object("id","site-1","enabled",true,"portalStation","S1"),object("id","site-2","enabled",true,"portalStation","S2")),"people",new JSONArray());
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));
        access=new GuardianAccess(ledger,mock(AdminQueryService.class));media=mock(HelmetMediaService.class);
        when(media.audioReference(reference)).thenReturn(assetId);
        when(media.deviceAudioAsset("RL-H001",assetId)).thenReturn(object("assetId",assetId,"deviceId","RL-H001","kind","audio","status","ready","originalMime","audio/3gpp","playbackMime","audio/mpeg","durationSeconds",2.5));
        when(media.deviceAudioPlayback(any())).thenAnswer(i->object("assetId",assetId,"url","https://media.example/helmet-media/files/"+assetId+"?variant=playback&token=short","mime","audio/mpeg","expiresAt",Instant.now().plusSeconds(30).toString()));
        service=new GuardianDeviceVoiceMessages(store,access,media);ingest=new GuardianIngest(store);
        delivery=new WearableReportDelivery(journal,ingest,mock(ObjectProvider.class),mock(ObjectProvider.class));
        ObjectProvider<GuardianDeviceVoiceMessages> provider=mock(ObjectProvider.class);when(provider.getObject()).thenReturn(service);
        ReflectionTestUtils.setField(delivery,"voiceMessages",provider);
        maintenance=mock(WearableMaintenance.class);ReflectionTestUtils.setField(delivery,"maintenance",maintenance);
    }
    JSONObject raw(){return object("act","ca_sending_message","message",reference,"personId","forged","is_read",true);}
    MockHttpServletRequest request(JSONObject who){MockHttpServletRequest r=new MockHttpServletRequest();r.setAttribute("wearable.actor",who);return r;}
    JSONObject list(){return service.list("site-1",null,null,1,20,request(actor));}
    JSONObject saved(){return rows(store.snapshot(),"sharedCommunications").getJSONObject(0);}

    @Test void journalPreservesReceptionAttributionAndRetriesWithoutDuplicateOrTelemetryEffects() {
        JSONObject before=store.snapshot();delivery.helmetVoiceMessage("RL-H001",raw().toJSONString());
        JSONObject pending=journal.pendingReports(0,100).get(0),capture=pending.getJSONObject("payload").getJSONObject("context");
        assertEquals(raw(),pending.getJSONObject("payload").get("raw"));verify(media,never()).deviceAudioAsset(anyString(),anyString());
        store.update(s->{for(Object r:rows(s,"bindings")){JSONObject b=(JSONObject)r;if("RL-H001".equals(b.getString("deviceId")))b.put("end",Instant.now().toString());}return true;});
        when(media.deviceAudioAsset("RL-H001",assetId)).thenThrow(new IllegalStateException("temporary outage"));
        delivery.recover();assertEquals(1,journal.pendingReports(0,100).size());assertEquals(0,list().getIntValue("total"));
        doReturn(object("assetId",assetId,"originalMime","audio/3gpp","playbackMime","audio/mpeg","durationSeconds",2.5)).when(media).deviceAudioAsset("RL-H001",assetId);
        delivery.recover();JSONObject row=saved();assertEquals("READY",row.getString("status"));assertEquals(capture.get("personId"),row.get("personId"));
        assertEquals(capture.get("personName"),row.get("personName"));assertEquals(capture.get("bindingId"),row.get("bindingId"));assertEquals(capture.get("receivedAt"),row.get("receivedAt"));
        assertFalse(row.containsKey("message"));assertFalse(row.containsKey("url"));assertFalse(row.containsKey("connectedAt"));assertFalse(row.containsKey("is_read"));
        delivery.helmetVoiceMessage("RL-H001",raw().toJSONString());delivery.recover();delivery.recover();
        assertTrue(journal.pendingReports(0,100).isEmpty());assertEquals(1,list().getIntValue("total"));assertEquals(row,saved());
        assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE processed_at IS NOT NULL",Integer.class));
        for(String key:new String[]{"devices","events","media","locations","calls"})assertEquals(before.get(key),store.snapshot().get(key));
        assertFalse(list().toJSONString().contains("token="));
    }
    @Test void unverifiedFileIsRecordedAsRejectedWithoutPlaybackAndArbitraryUrlNeverEntersQueue() {
        when(media.deviceAudioAsset("RL-H001",assetId)).thenThrow(new IllegalArgumentException("wrong device or kind"));
        delivery.helmetVoiceMessage("RL-H001",raw().toJSONString());delivery.recover();
        JSONObject row=saved();assertEquals("REJECTED",row.getString("status"));assertFalse(row.getBooleanValue("playable"));assertFalse(row.containsKey("assetId"));
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->service.playback(row.getString("id"),request(actor))).code);
        when(media.audioReference("https://foreign.example/private")).thenThrow(new IllegalArgumentException("invalid reference"));
        assertThrows(IllegalArgumentException.class,()->delivery.helmetVoiceMessage("RL-H001",object("act","ca_sending_message","message","https://foreign.example/private").toJSONString()));
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Integer.class));
    }
    @Test void historyUsesOriginalScopeAndOwnerAndRechecksAuthorityBeforeReturningTicket() {
        delivery.helmetVoiceMessage("RL-H001",raw().toJSONString());delivery.recover();JSONObject row=saved();
        String originalPerson=row.getString("personId");
        store.update(s->{find(s,"devices","RL-H001").put("siteId","site-2");return true;});
        assertEquals(1,list().getIntValue("total"));assertEquals(row.getString("id"),service.playback(row.getString("id"),request(actor)).getString("id"));
        grant.put("siteIds",JSONArray.of("site-2"));assertEquals(0,service.list(null,null,null,1,20,request(actor)).getIntValue("total"));
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->service.playback(row.getString("id"),request(actor))).code);
        JSONObject self=object("id","self","enabled",true,"personId","person-self","roleIds",JSONArray.of("self-role"));
        master.getJSONArray("accounts").add(self);master.getJSONArray("people").add(object("id","person-self","portalId",originalPerson,"enabled",true,"siteId","site-1"));
        master.getJSONArray("roles").add(object("id","self-role","enabled",true,"grants",JSONArray.of(object("operations",JSONArray.of("self:read"),"siteIds",JSONArray.of("site-1")))));
        assertEquals(1,service.list(null,null,null,1,20,request(self)).getIntValue("total"));
        master.getJSONArray("people").getJSONObject(0).put("portalId","new-wearer");assertEquals(0,service.list(null,null,null,1,20,request(self)).getIntValue("total"));
        grant.put("siteIds",JSONArray.of("site-1"));
        when(media.deviceAudioAsset("RL-H001",assetId)).thenAnswer(i->{grant.put("siteIds",JSONArray.of("site-2"));return object("assetId",assetId);});
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->service.playback(row.getString("id"),request(actor))).code);
        assertEquals(row,saved());
    }
    @Test void absentPlayableCopyIsNeverReportedAsACompletedPlayback() {
        when(media.deviceAudioPlayback(any())).thenReturn(null);
        delivery.helmetVoiceMessage("RL-H001",raw().toJSONString());delivery.recover();assertFalse(saved().getBooleanValue("playable"));
        assertEquals(503,assertThrows(AdminQueryService.QueryFailed.class,()->service.playback(saved().getString("id"),request(actor))).code);
        assertEquals(400,assertThrows(AdminQueryService.QueryFailed.class,()->service.list(null,null,null,0,20,request(actor))).code);
        assertEquals(0,service.list("site-1",null,null,2,20,request(actor)).getJSONArray("rows").size());
    }
    @Test void paginationOrdersReceivedInstantsWithinOneSecondDespiteDifferentFractionPrecision() {
        for(String at:new String[]{"2026-11-02T00:00:00Z","2026-11-02T00:00:00.123Z","2026-11-02T00:00:00.001000000Z"}){
            JSONObject capture=ingest.captureDirect("RL-H001");capture.put("receivedAt",at);
            service.accept("RL-H001",UUID.randomUUID().toString(),capture,object("status","READY","playable",false));
        }
        String[] expected={"2026-11-02T00:00:00.123Z","2026-11-02T00:00:00.001Z","2026-11-02T00:00:00Z"};
        for(int index=0;index<expected.length;index++){
            JSONObject page=service.list("site-1",null,null,index+1,1,request(actor));
            assertEquals(3,page.getIntValue("total"));assertEquals(1,page.getJSONArray("rows").size());
            assertEquals(expected[index],page.getJSONArray("rows").getJSONObject(0).getString("receivedAt"));
        }
    }
}
