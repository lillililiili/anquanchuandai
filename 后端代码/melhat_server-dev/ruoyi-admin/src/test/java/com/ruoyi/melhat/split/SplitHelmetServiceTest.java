package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.AdminQueryService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.melhat.split.SplitTelemetry.obj;

class SplitHelmetServiceTest {
    SplitHelmetProperties p;SplitHelmetClient client;SplitHelmetStore store;SplitHelmetBridge bridge;ObjectProvider<SplitHelmetBridge> provider;SplitHelmetService service;JdbcTemplate jdbc;
    @BeforeEach @SuppressWarnings("unchecked") void setup(){
        p=new SplitHelmetProperties();p.setEnabled(true);p.setAllowedDevices("SN1,SN2,SN3,SN4,SN5,SN6,SN7,SN8,SN9");
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));store=new SplitHelmetStore(jdbc,p);
        client=mock(SplitHelmetClient.class);when(client.configured()).thenReturn(true);bridge=mock(SplitHelmetBridge.class);provider=mock(ObjectProvider.class);when(provider.getIfAvailable()).thenReturn(bridge);
        when(bridge.isRegistered(anyString())).thenReturn(true);when(bridge.registered()).thenReturn(Arrays.asList("SN1","SN2"));when(bridge.capture(anyString(),anyString())).thenReturn(obj("siteId","old-site"));
        service=new SplitHelmetService(p,client,store,provider);
        for(String sn:p.allowed())store.state(sn,s->{s.put("vendorOnline",true);s.put("onlineReportedAt",Instant.now().toString());return s;});
        when(client.post(eq("/api/webrtc/session"),any())).thenAnswer(i->{JSONArray remote=new JSONArray();for(Object sn:((JSONObject)i.getArgument(1)).getJSONArray("helmetSnList"))remote.add(obj("helmetSn",sn,"playUrl","play-"+sn,"talkUrl","talk-"+sn));return obj("code",200,"data",obj("mediaType","webrtc","sessions",remote));});
        when(client.post(eq("/api/webrtc/hangup"),any())).thenReturn(obj("code",200));
    }
    JSONObject recipient(String sn){return obj("deviceId",sn,"personId","P1","assignmentId","A1","assignmentVersion",1,"siteId","old-site");}
    JSONObject create(String...sns){JSONArray recipients=new JSONArray();for(String sn:sns)recipients.add(recipient(sn));return service.create("actor",recipients,false,"call",UUID.randomUUID().toString());}
    JSONObject command(String action){JSONObject c=recipient("SN1");c.put("action",action);c.put("idempotencyKey",UUID.randomUUID().toString());return c;}

    @Test void uncertainCreateIsNotRetriedAndLeaseSurvivesRestart(){
        when(client.post(eq("/api/webrtc/session"),any())).thenThrow(new RuntimeException("delivery unknown"));JSONArray rs=JSONArray.of(recipient("SN1"));
        JSONObject first=service.create("actor",rs,false,"call","stable-request");assertEquals("unknown",first.getString("status"));
        SplitHelmetService restarted=new SplitHelmetService(p,client,new SplitHelmetStore(jdbc,p),provider);assertEquals(first.getString("sessionId"),restarted.create("actor",rs,false,"call","stable-request").getString("sessionId"));
        assertThrows(AdminQueryService.QueryFailed.class,()->restarted.create("other",rs,false,"call","other-request"));verify(client,times(1)).post(eq("/api/webrtc/session"),any());
        restarted.end(first.getString("sessionId"));assertFalse(store.owns(first.getString("sessionId"),"SN1"));
    }
    @Test void monitorIntercomUsesTheExistingDeviceLeaseAndVendorSession() {
        JSONObject context = recipient("SN1");
        context.put("viewerSessionId", "monitor-test-01");
        JSONObject live = service.live("actor", "SN1", context);
        String id = live.getString("sessionId");
        assertEquals("/api/guardian/v1/split/sessions/" + id + "/devices/SN1/talk", live.getString("talkUrl"));
        assertThrows(AdminQueryService.QueryFailed.class, () -> service.signal("actor",id,"SN1","talk","v=0"));
        assertThrows(AdminQueryService.QueryFailed.class, () -> service.enableMonitorTalk("actor",id,"SN2"));
        assertThrows(AdminQueryService.QueryFailed.class, () -> service.enableMonitorTalk("other",id,"SN1"));
        service.enableMonitorTalk("actor",id,"SN1");
        service.signal("actor",id,"SN1","talk","v=0");
        assertTrue(service.owned("actor",id).getBooleanValue("monitorTalk"));
        assertEquals(id, service.live("actor","SN1",context).getString("sessionId"));
        verify(client,times(1)).post(eq("/api/webrtc/session"),any());
        verify(client,never()).post(eq("/api/webrtc/hangup"),any());
        service.end(id);
        assertThrows(AdminQueryService.QueryFailed.class, () -> service.enableMonitorTalk("actor",id,"SN1"));
    }
    @Test void failedHangupKeepsLeaseAndOldEndedSessionCannotStopReplacement(){
        JSONObject first=create("SN1");String id=first.getString("sessionId");when(client.post(eq("/api/webrtc/hangup"),any())).thenThrow(new RuntimeException("unknown"));
        assertThrows(RuntimeException.class,()->service.end(id));assertTrue(store.owns(id,"SN1"));assertThrows(AdminQueryService.QueryFailed.class,()->create("SN1"));
        when(client.post(eq("/api/webrtc/hangup"),any())).thenReturn(obj("code",200));service.end(id);JSONObject second=create("SN1");clearInvocations(client);service.end(id);verifyNoInteractions(client);assertTrue(store.owns(second.getString("sessionId"),"SN1"));
    }
    @Test void partialSessionsAreExplicitAndForeignSessionsNeverReleaseUnknownLease(){
        when(client.post(eq("/api/webrtc/session"),any())).thenReturn(obj("data",obj("mediaType","webrtc","sessions",JSONArray.of(obj("helmetSn","SN1","playUrl","p","talkUrl","t")))));
        JSONObject partial=create("SN1","SN2");assertEquals(1,partial.getJSONArray("sessions").size());assertEquals("SN2",partial.getJSONArray("skipped").getJSONObject(0).getString("deviceId"));assertFalse(store.owns(partial.getString("sessionId"),"SN2"));
        when(client.post(eq("/api/webrtc/session"),any())).thenReturn(obj("data",obj("mediaType","webrtc","sessions",JSONArray.of(obj("helmetSn","FOREIGN","playUrl","p","talkUrl","t")))));
        JSONObject unknown=create("SN2");assertEquals("unknown",unknown.getString("status"));assertTrue(store.owns(unknown.getString("sessionId"),"SN2"));
    }
    @Test void limitAndDuplicateTargetsFailBeforeVendor(){
        assertThrows(AdminQueryService.QueryFailed.class,()->create("SN1","SN1"));assertThrows(AdminQueryService.QueryFailed.class,()->create("SN1","SN2","SN3","SN4","SN5","SN6","SN7","SN8","SN9"));verify(client,never()).post(anyString(),any());
    }
    @Test void minuteHeartbeatIsRateLimitedAndConnectionEvidenceIsExplicit(){
        JSONObject created=create("SN1");String id=created.getString("sessionId");service.heartbeat("actor",id);verify(client,never()).post(eq("/api/webrtc/heartbeat"),any());
        JSONObject row=store.session(id);row.put("lastHeartbeatMillis",System.currentTimeMillis()-61000);store.saveSession(row);when(client.post(eq("/api/webrtc/heartbeat"),any())).thenReturn(obj("code",200));service.heartbeat("actor",id);service.heartbeat("actor",id);verify(client,times(1)).post(eq("/api/webrtc/heartbeat"),any());
        assertThrows(AdminQueryService.QueryFailed.class,()->service.joined("actor",id,true,JSONArray.of("SN2")));service.joined("actor",id,true,JSONArray.of("SN1"));assertEquals(JSONArray.of("SN1"),service.callState(id).getJSONArray("connectedDeviceIds"));assertFalse(service.callState(id).getBooleanValue("statusVerified"));
    }
    @Test void durableInvalidPacketDoesNotBlockLaterProjectionAndDuplicateDoesNotRecapture(){
        String at=Instant.now().toString();JSONObject bad=obj("helmetSn","SN1","latitude",30);assertEquals("REJECTED",service.receive("gnss",bad,"bad-packet-1",at).getString("processingState"));assertTrue(store.pending().isEmpty());verify(bridge,never()).ingest(any());
        JSONObject good=obj("helmetSn","SN1","latitude",30,"longitude",120);service.receive("gnss",good,"good-packet-1",at);service.receive("gnss",good,"good-packet-1",at);verify(bridge,times(2)).capture(eq("SN1"),eq(at));verify(bridge,times(1)).ingest(any());assertEquals(120,service.status("SN1").getDoubleValue("longitude"));
        assertThrows(AdminQueryService.QueryFailed.class,()->service.receive("gnss",obj("helmetSn","SN1","latitude",31,"longitude",120),"good-packet-1",at));
    }
    @Test void projectionFailureRemainsDurableAndStatusDoesNotReenterLedger(){
        doThrow(new RuntimeException("projection")).doNothing().when(bridge).ingest(any());service.receive("deviceStatus",obj("helmetSn","SN1","power",0),"status-packet-1",Instant.now().toString());assertEquals(1,store.pending().size());service.recover();assertTrue(store.pending().isEmpty());clearInvocations(bridge);assertEquals(0,service.status("SN1").getDoubleValue("battery"));verifyNoInteractions(bridge);
    }
    @Test void failedOrMissingPollIsUnknownAndBooleanOnlineIsAccepted(){
        when(client.online(any())).thenReturn(JSONArray.of(obj("helmetSn","SN1","online",true)));service.poll();assertTrue(service.status("SN1").getBoolean("online"));assertNull(service.status("SN2").getBoolean("online"));
        when(client.online(any())).thenThrow(new RuntimeException("read failure"));service.poll();assertNull(service.status("SN1").getBoolean("online"));assertNotNull(service.status("SN1").getString("onlineReportedAt"));
    }
    @Test void recordingUsesSavedSidRejectsWrongContextAndNeverRepeatsUnknownStop(){
        when(client.post(eq("/api/monitor/record"),any())).thenReturn(obj("data",obj("sent",JSONArray.of(obj("helmetSn","SN1","sid","record-1")))));
        JSONObject start=command("start_recording"),record=service.command("actor","SN1",start);assertNull(record.get("sid"));JSONObject stop=command("stop_recording");stop.put("parameters",obj("commandId",record.getString("id")));JSONObject wrong=JSONObject.parseObject(stop.toJSONString());wrong.put("assignmentVersion",2);assertThrows(AdminQueryService.QueryFailed.class,()->service.command("actor","SN1",wrong));
        when(client.post(eq("/api/monitor/record/stop"),any())).thenThrow(new RuntimeException("unknown"));assertEquals("unknown",service.command("actor","SN1",stop).getString("status"));stop.put("idempotencyKey",UUID.randomUUID().toString());service.command("actor","SN1",stop);verify(client,times(1)).post(eq("/api/monitor/record/stop"),eq(obj("sid","record-1")));
    }
    @Test void fractionalDurationIsRejectedBeforeControl(){JSONObject c=command("start_recording");for(Object n:new Object[]{0,-1,86401,1.5,"30"}){c.put("parameters",obj("durationSeconds",n));assertThrows(AdminQueryService.QueryFailed.class,()->service.command("actor","SN1",c));}verify(client,never()).post(anyString(),any());}
    @Test void activeRecordingAndFileCorrelationOutliveRollingCommandDisplay(){
        store.commandIntent(obj("id","old-record","actorId","actor","deviceId","SN1","requestKey","old-record","fingerprint","record","createdMillis",1L,"action","start_recording","status","recording","sid","record-sid"));
        for(int i=0;i<310;i++)store.commandIntent(obj("id","new-query-"+i,"actorId","actor","deviceId","SN1","requestKey","new-query-"+i,"fingerprint","query","createdMillis",2L+i,"action","list_recordings","status","completed"));
        assertEquals(100,store.commands("SN1").size());assertEquals("old-record",store.unfinishedCommands().get(0).getString("id"));assertEquals("old-record",store.mediaCommands("SN1").get(0).getString("id"));
    }
    @Test void filesUseHistoricalAttributionExactPathsAndDurableIndexBeyondCommandWindow(){
        String at="2026-11-15T00:00:00Z",url="https://files.test/media/SN1/a.jpg";
        when(bridge.captureFile("SN1",at)).thenReturn(obj("siteId","historical-site","personId","historical-person","assignmentId","old-assignment"));when(client.safeFileUrl(anyString(),eq("SN1"))).thenAnswer(i->i.getArgument(0));
        when(client.post(eq("/api/monitor/capture"),any())).thenReturn(obj("data",obj("sent",JSONArray.of(obj("helmetSn","SN1","task_id","task-123")))));
        JSONObject capture=service.command("actor","SN1",command("take_photo"));
        when(client.files("SN1",1)).thenReturn(obj("file_list",JSONArray.of(obj("key","SN1/a.jpg","name","a.jpg","type","image","size",12,"lastModified",at,"url",url,"task_id","task-123"),obj("key","SN1/b.jpg","name","b.jpg","type","image","size",13,"lastModified",at,"url",url),obj("key","SN1/c.jpg","name","c.jpg","type","image","size",14,"lastModified","bad-time","url","https://files.test/media/SN1/c.jpg"))));
        JSONObject result=service.command("actor","SN1",command("list_recordings"));JSONArray files=result.getJSONArray("result");assertEquals(3,files.size());JSONObject file=files.getJSONObject(0);assertEquals("historical-site",file.getString("siteId"));assertEquals("historical-person",file.getString("personId"));assertTrue(file.getBooleanValue("available"));assertFalse(files.getJSONObject(1).getBooleanValue("available"));assertFalse(files.getJSONObject(2).getBooleanValue("available"));assertNull(files.getJSONObject(2).get("siteId"));
        assertEquals("completed",store.command(capture.getString("id")).getString("status"));assertTrue(store.command(capture.getString("id")).getJSONArray("assetIds").contains(file.getString("id")));
        for(int i=0;i<110;i++)store.commandIntent(obj("id","later-"+i,"actorId","actor","deviceId","SN1","requestKey","later-"+i,"fingerprint","later","createdMillis",System.currentTimeMillis()+i,"status","sent"));
        assertEquals("historical-site",service.fileContext("SN1",file.getString("id")).getString("siteId"));assertEquals(url,service.fileSnapshot("SN1",file.getString("id")).getString("privateSourceUrl"));assertEquals(3,service.media("SN1").getJSONArray("items").size());assertFalse(service.media("SN1").toJSONString().contains("privateSourceUrl"));
        when(client.files("SN1",1)).thenReturn(obj("file_list",JSONArray.of(obj("key","SN1/a.jpg","type","image","size",99,"lastModified",at,"url",url))));assertThrows(AdminQueryService.QueryFailed.class,()->service.fileSnapshot("SN1",file.getString("id")));
    }
    @Test void concurrentSdpNegotiationsDoNotSerializeOrPermitHangupToOvertakeThem()throws Exception {
        String id=create("SN1").getString("sessionId");CountDownLatch entered=new CountDownLatch(2),finish=new CountDownLatch(1);when(client.signal(anyString(),anyString(),anyString(),anyString())).thenAnswer(i->{entered.countDown();if(!finish.await(3,TimeUnit.SECONDS))throw new IllegalStateException();return "v=0\r\n";});
        ExecutorService executor=Executors.newFixedThreadPool(3);try{Future<String> play=executor.submit(()->service.signal("actor",id,"SN1","play","v=0")),talk=executor.submit(()->service.signal("actor",id,"SN1","talk","v=0"));assertTrue(entered.await(2,TimeUnit.SECONDS));Future<?> end=executor.submit(()->service.end(id));assertFalse(end.isDone());verify(client,never()).post(eq("/api/webrtc/hangup"),any());finish.countDown();play.get(3,TimeUnit.SECONDS);talk.get(3,TimeUnit.SECONDS);end.get(3,TimeUnit.SECONDS);assertEquals("ended",service.callState(id).getString("status"));}finally{finish.countDown();executor.shutdownNow();}
    }
}
