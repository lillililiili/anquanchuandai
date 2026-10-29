package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.alibaba.fastjson2.JSONArray;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

class HelmetMediaServiceTest {
    @TempDir Path directory;
    @SuppressWarnings("unchecked")
    private Fixture fixture() {
        HelmetCloudClient cloud=mock(HelmetCloudClient.class);when(cloud.configured()).thenReturn(true);
        DirectHelmetGateway gateway=mock(DirectHelmetGateway.class);when(gateway.isOnline("helmet-a")).thenReturn(true);
        ObjectProvider<DirectHelmetGateway> provider=mock(ObjectProvider.class);when(provider.getObject()).thenReturn(gateway);
        HelmetMediaStore store=new HelmetMediaStore(directory.resolve("journal.json").toString());
        HelmetMediaService service=new HelmetMediaService(cloud,store,new HelmetMediaProperties(),provider);
        ReflectionTestUtils.setField(service,"healthy",true);
        return new Fixture(service,cloud,gateway,store);
    }
    @Test void commandRetriesDoNotResendAndAnotherDeviceCannotAcknowledge() throws Exception {
        Fixture f=fixture();JSONObject input=obj("action","take_photo","idempotencyKey","test-request-001");
        JSONObject first=f.service.command("operator","helmet-a",input);
        assertEquals("sent",first.getString("status"));
        assertEquals(first.getString("id"),f.service.command("operator","helmet-a",input).getString("id"));
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),any());
        f.service.receipt("helmet-b",obj("act","ca_upload_photo","talkback_id",first.get("id"),"status",true));
        assertEquals("sent",f.store.snapshot().getJSONObject("commands").getJSONObject(first.getString("id")).getString("status"));
        f.service.receipt("helmet-a",obj("act","ca_upload_photo","talkback_id",first.get("id"),"status",true));
        assertEquals("acknowledged",f.store.snapshot().getJSONObject("commands").getJSONObject(first.getString("id")).getString("status"));
        assertThrows(IllegalArgumentException.class,()->f.service.command("operator","helmet-a",obj("action","start_video","idempotencyKey","test-request-001")));
    }
    @Test void offlineNeverCreatesACommandAndAmbiguousWriteIsNotRetried() throws Exception {
        Fixture f=fixture();when(f.gateway.isOnline("helmet-a")).thenReturn(false);
        JSONObject input=obj("action","take_photo","idempotencyKey","test-request-001");
        assertThrows(IllegalStateException.class,()->f.service.command("operator","helmet-a",input));
        verify(f.gateway,never()).sendCommand(anyString(),any());
        when(f.gateway.isOnline("helmet-a")).thenReturn(true);doThrow(new java.io.IOException("disconnected")).when(f.gateway).sendCommand(eq("helmet-a"),any());
        assertEquals("unknown",f.service.command("operator","helmet-a",input).getString("status"));
        assertEquals("unknown",f.service.command("operator","helmet-a",input).getString("status"));
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),any());
    }
    @Test void journalSurvivesRestartAndSIPPasswordsAreNeverInPublicCallState() {
        Fixture f=fixture();f.store.update(s->{s.put("calls",obj("SIP-test",obj("id","SIP-test","actorId","owner","status","offered","credentials",obj("authorizationPassword","secret","expiresAt",java.time.Instant.now().plusSeconds(60).toString()))));return null;});
        assertFalse(f.service.callState("SIP-test").containsKey("credentials"));
        assertThrows(IllegalArgumentException.class,()->f.service.credentials("SIP-test","other"));
        assertEquals("secret",f.service.credentials("SIP-test","owner").getString("authorizationPassword"));
        HelmetMediaStore reloaded=new HelmetMediaStore(directory.resolve("journal.json").toString());
        assertTrue(reloaded.snapshot().getJSONObject("calls").containsKey("SIP-test"));
    }
    @Test void incompleteSettingsAreRejectedWithoutInventingDeviceDefaults() {
        assertThrows(IllegalArgumentException.class,()->HelmetMediaService.wire("set_config",obj("sos_height","2")));
        JSONObject command=HelmetMediaService.wire("set_config",obj("sos_height","2.5","local_record","1","electrostatic","0","record_video_name","巡检","privacy_switch","1"));
        assertEquals("server_push_set_sos_height",command.getString("cmd"));
        assertEquals("1",command.getString("local_record"));
    }
    @Test void credentialsJournalCannotBeConfiguredUnderPublicUploads(){
        Path uploads=directory.resolve("public");
        assertThrows(IllegalArgumentException.class,()->new HelmetMediaStore(uploads.resolve("credentials.json").toString(),uploads.toString()));
        assertDoesNotThrow(()->new HelmetMediaStore(directory.resolve("private.json").toString(),uploads.toString()));
    }
    @Test void recordingWaitsForActualPublishingAndDoesNotReportAFilePrematurely() throws Exception {
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject result=f.service.command("operator","helmet-a",obj("action","start_recording","idempotencyKey","record-request-001"));
        assertEquals("waiting_media",result.getString("status"));
        verify(f.cloud,never()).request(eq("POST"),eq("/recordings"),any());
        verify(f.gateway).sendCommand(eq("helmet-a"),argThat(c->"server_push_open_rtsp".equals(c.getString("cmd"))));
    }
    @Test void stoppingBeforeVideoArrivesPreventsLaterRecording() throws Exception {
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject start=f.service.command("operator","helmet-a",obj("action","start_recording","idempotencyKey","record-request-001"));
        when(f.gateway.isOnline("helmet-a")).thenReturn(false);
        JSONObject stop=f.service.command("operator","helmet-a",obj("action","stop_recording","idempotencyKey","record-request-002","sourceCommandId",start.get("id")));
        assertEquals("completed",stop.getString("status"));
        assertFalse(f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getBooleanValue("recordRequested"));
        assertEquals("cancelled",f.store.snapshot().getJSONObject("commands").getJSONObject(start.getString("id")).getString("status"));
        ReflectionTestUtils.invokeMethod(f.service,"startPendingRecordings");
        verify(f.cloud,never()).request(eq("POST"),eq("/recordings"),any());
    }
    @Test void signedStreamRenewalPreservesActiveRecorderAndDemand() {
        Fixture f=fixture();f.store.update(s->{s.put("streams",obj("helmet-a",obj("streamId","old-stream","pushUrl","old","expiresAt",java.time.Instant.now().minusSeconds(1).toString(),"recordingId","recording-1","recordRequested",true)));return null;});
        when(f.cloud.request("GET","/streams/old-stream",null)).thenReturn(obj("streamId","old-stream","pushUrl","renewed","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        f.service.command("operator","helmet-a",obj("action","start_video","idempotencyKey","stream-renewal-001","viewerSessionId","viewer-renewal-001"));
        JSONObject stream=f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a");
        assertEquals("recording-1",stream.getString("recordingId"));assertTrue(stream.getBooleanValue("recordRequested"));assertTrue(stream.getBooleanValue("watchRequested"));assertEquals("renewed",stream.getString("pushUrl"));
        verify(f.cloud,never()).request(eq("POST"),eq("/streams"),any());
    }
    @Test void firmwareRecordingDatesAreCompactAndInvalidDatesAreRejected(){
        JSONObject wire=HelmetMediaService.wire("list_recordings",obj("startTime","2026-10-23 08:01:02","endTime","2026-10-23 10:00:00"));
        assertEquals("20261023080102",wire.getString("start_time"));
        assertThrows(IllegalArgumentException.class,()->HelmetMediaService.wire("list_recordings",obj("startTime","2026-02-30 00:00:00","endTime","2026-03-03 00:00:00")));
    }
    @Test void arbitraryLocalFilesCannotBeRequestedFromDevice() throws Exception {
        Fixture f=fixture();assertThrows(IllegalArgumentException.class,()->f.service.command("operator","helmet-a",obj("action","upload_recording","idempotencyKey","upload-request-001","parameters",obj("files",JSONArray.of("/private.txt")))));
        verify(f.gateway,never()).sendCommand(anyString(),any());
    }
    @Test void missedEndEventIsRecoveredByCloudCallState(){
        Fixture f=fixture();f.store.update(s->{s.put("calls",obj("SIP-old",obj("id","SIP-old","status","unknown","deviceIds",JSONArray.of("helmet-a"),"credentials",obj("authorizationPassword","private"))));return null;});
        when(f.cloud.request("GET","/calls/SIP-old",null)).thenReturn(obj("status","ended","connectedDeviceIds",new JSONArray()));
        ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");
        assertEquals("ended",f.service.callState("SIP-old").getString("status"));
        assertFalse(f.store.snapshot().getJSONObject("calls").getJSONObject("SIP-old").containsKey("credentials"));
    }
    @Test void uploadedHistoricalVideoCanMatchCommandWithoutClaimingCurrentWearer(){
        Fixture f=fixture();String now=java.time.Instant.now().toString();
        f.store.update(s->{s.put("commands",obj("HC-upload",obj("id","HC-upload","deviceId","helmet-a","action","upload_recording","createdAt",java.time.Instant.now().minusSeconds(30).toString(),"personId","new-wearer","siteId","new-site","requestedFiles",JSONArray.of(obj("fileName","old.mp4","progressId","abc123")))));return null;});
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("assets",JSONArray.of(obj("assetId","asset-old","kind","video","deviceId","helmet-a","originalName","old.mp4","progressId","abc123","createdAt",now))));
        JSONObject asset=f.service.assets("helmet-a").getJSONObject(0);
        assertEquals("HC-upload",asset.getString("requestId"));assertTrue(asset.getBooleanValue("unassigned"));assertNull(asset.get("personId"));assertNull(asset.get("siteId"));
    }
    @Test void batchUploadIsCompleteOnlyAfterAllRequestedFilesArrive(){
        Fixture f=fixture();JSONObject command=obj("id","HC-batch","deviceId","helmet-a","action","upload_recording","requestedFiles",JSONArray.of(obj("fileName","one.mp4"),obj("fileName","two.mp4")));
        ReflectionTestUtils.invokeMethod(f.service,"recordAsset",command,obj("id","asset-1","originalName","one.mp4"));assertEquals("receiving_files",command.getString("status"));
        ReflectionTestUtils.invokeMethod(f.service,"recordAsset",command,obj("id","asset-2","originalName","two.mp4"));assertEquals("completed",command.getString("status"));
    }
    @Test void oneViewerStoppingDoesNotCancelAnotherViewersDemand() throws Exception {
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        f.service.command("first","helmet-a",obj("action","start_video","idempotencyKey","viewer-first-start","viewerSessionId","viewer-first-001"));
        f.service.command("second","helmet-a",obj("action","start_video","idempotencyKey","viewer-second-start","viewerSessionId","viewer-second-001"));
        f.service.command("first","helmet-a",obj("action","stop_video","idempotencyKey","viewer-first-stop","viewerSessionId","viewer-first-001"));
        verify(f.gateway,never()).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
        assertTrue(f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getBooleanValue("watchRequested"));
        f.service.command("second","helmet-a",obj("action","stop_video","idempotencyKey","viewer-second-stop","viewerSessionId","viewer-second-001"));
        verify(f.gateway).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void mediaHistoryNeverFetchesLiveTickets(){
        Fixture f=fixture();f.store.update(s->{s.put("streams",obj("helmet-a",obj("streamId","live-stream")));return null;});
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("assets",new JSONArray()));
        assertFalse(f.service.media("helmet-a").containsKey("live"));verify(f.cloud,never()).request(eq("GET"),eq("/streams/live-stream"),any());
    }
    private JSONObject viewing(String action,String key,String session){return obj("action",action,"idempotencyKey",key,"viewerSessionId",session,"personId","P1","assignmentId","assignment-original","assignmentVersion",2,"siteId","site-1");}
    @Test void sameAccountTabsShareOneStreamButOwnIndependentLeases() throws Exception {
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject one=viewing("start_video","tab-start-001","viewer-tab-001"),two=viewing("start_video","tab-start-002","viewer-tab-002");
        f.service.command("same-owner","helmet-a",one);f.service.command("same-owner","helmet-a",two);
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),argThat(c->"server_push_open_rtsp".equals(c.getString("cmd"))));
        JSONObject stop=viewing("stop_video","tab-stop-001","viewer-tab-001");
        assertThrows(IllegalArgumentException.class,()->f.service.command("intruder","helmet-a",stop));
        when(f.gateway.isOnline("helmet-a")).thenReturn(false);f.service.command("same-owner","helmet-a",stop);
        assertTrue(f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getBooleanValue("watchRequested"));
        assertEquals(1,f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").size());
        verify(f.gateway,never()).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void liveRequiresOriginalContextAndActiveLeaseAndReturnsHls() {
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject input=viewing("start_video","live-start-001","viewer-live-001");f.service.command("owner","helmet-a",input);
        when(f.cloud.request("GET","/streams/stream-a",null)).thenReturn(obj("publishing",true,"whepUrl","https://test/whep","hlsUrl","https://test/hls","expiresAt",java.time.Instant.now().plusSeconds(30).toString()));
        assertEquals("https://test/hls",f.service.live("owner","helmet-a",input).getJSONObject("live").getString("url"));
        assertThrows(IllegalArgumentException.class,()->f.service.live("other","helmet-a",input));
        JSONObject changed=new JSONObject(input);changed.put("assignmentVersion",3);assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.live("owner","helmet-a",changed));
        f.store.update(s->{s.getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").getJSONObject("viewer-live-001").put("expiresAt",java.time.Instant.now().minusSeconds(1).toString());return null;});
        assertThrows(IllegalArgumentException.class,()->f.service.live("owner","helmet-a",input));
    }
    @Test void expiredViewersNeverCancelActiveRecording() throws Exception {
        Fixture f=fixture();f.store.update(s->{s.put("streams",obj("helmet-a",obj("streamId","stream-a","watchRequested",true,"recordRequested",true,"recordingId","record-1","viewers",obj("expired-viewer",obj("actorId","owner","expiresAt",java.time.Instant.now().minusSeconds(1).toString())))));return null;});
        ReflectionTestUtils.invokeMethod(f.service,"expireViewers");JSONObject stream=f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a");assertFalse(stream.getBooleanValue("watchRequested"));assertTrue(stream.getBooleanValue("recordRequested"));verify(f.gateway,never()).sendCommand(anyString(),any());
    }
    @Test void recordingCleanupRequiresOriginalActorContextAndCommand(){
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject start=f.service.command("owner","helmet-a",viewing("start_recording","record-owner-001","viewer-unused-001"));
        JSONObject stop=viewing("stop_recording","record-owner-002","viewer-unused-001");stop.put("sourceCommandId",start.get("id"));
        assertThrows(IllegalArgumentException.class,()->f.service.command("other","helmet-a",stop));JSONObject stale=new JSONObject(stop);stale.put("sourceCommandId","another-record");assertThrows(IllegalArgumentException.class,()->f.service.command("owner","helmet-a",stale));
        JSONObject changed=new JSONObject(stop);changed.put("assignmentId","replacement");assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.command("owner","helmet-a",changed));
        when(f.gateway.isOnline("helmet-a")).thenReturn(false);assertEquals("completed",f.service.command("owner","helmet-a",stop).getString("status"));
    }
    @Test void lostRecordingResponseCanRecoverRequestFromHistoryAndCleanOriginalSessionOffline(){
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        f.service.command("owner","helmet-a",viewing("start_recording","lost-record-response-001","viewer-recovery-001"));
        when(f.gateway.isOnline("helmet-a")).thenReturn(false);
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("assets",new JSONArray()));
        JSONObject history=f.service.media("helmet-a"),recovered=history.getJSONArray("commands").getJSONObject(0);
        assertEquals("lost-record-response-001",recovered.getString("requestId"));assertFalse(recovered.containsKey("fingerprint"));assertFalse(recovered.containsKey("wire"));assertFalse(history.containsKey("live"));
        JSONObject stop=viewing("stop_recording","lost-record-response-stop","viewer-recovery-001");stop.put("sourceCommandId",recovered.getString("id"));
        assertEquals("completed",f.service.command("owner","helmet-a",stop).getString("status"));
        verify(f.cloud,times(1)).request(eq("POST"),eq("/streams"),any());verify(f.cloud,never()).request(eq("GET"),eq("/streams/stream-a"),any());
    }
    @Test void oldCloudLongLivedTicketsAreRejectedWithoutRenewingLease(){
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject input=viewing("start_video","old-cloud-start","viewer-old-cloud");f.service.command("owner","helmet-a",input);
        String lease=f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").getJSONObject("viewer-old-cloud").getString("expiresAt");
        when(f.cloud.request("GET","/streams/stream-a",null)).thenReturn(obj("publishing",true,"hlsUrl","https://test/long-lived","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        assertEquals("MEDIA_SERVICE_UPGRADE_REQUIRED",assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.live("owner","helmet-a",input)).errorCode);
        assertEquals(lease,f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").getJSONObject("viewer-old-cloud").getString("expiresAt"));
    }
    private void revoke(Fixture f){ReflectionTestUtils.invokeMethod(f.service,"invalidateSessions",(java.util.function.BiPredicate<String,JSONObject>)(actor,row)->false);}
    @Test void returnedAssignmentCancelsWaitingRecordingWithoutBrowserAndNeverStartsIt() throws Exception {
        Fixture f=fixture();when(f.cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream-a","pushUrl","rtmp://test/a","expiresAt",java.time.Instant.now().plusSeconds(3600).toString()));
        JSONObject command=f.service.command("owner","helmet-a",viewing("start_recording","returned-recording","viewer-returned"));
        revoke(f);ReflectionTestUtils.invokeMethod(f.service,"startPendingRecordings");
        assertFalse(f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getBooleanValue("recordRequested"));
        assertEquals("cancelled",f.store.snapshot().getJSONObject("commands").getJSONObject(command.getString("id")).getString("status"));
        verify(f.cloud,never()).request(eq("POST"),eq("/recordings"),any());verify(f.gateway).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void revokedRecorderKeepsUnknownOnStopFailureAndPreservesHistoricalAsset(){
        Fixture f=fixture();f.store.update(s->{s.put("streams",obj("helmet-a",obj("streamId","stream-a","recordRequestId","HC-active","recordRequested",true,"recordingId","record-active")));s.put("commands",obj("HC-active",obj("id","HC-active","actorId","owner","deviceId","helmet-a","action","start_recording","status","recording")));return null;});
        when(f.cloud.request("DELETE","/recordings/record-active",null)).thenThrow(new IllegalStateException("test unavailable"));revoke(f);
        assertEquals("unknown",f.store.snapshot().getJSONObject("commands").getJSONObject("HC-active").getString("status"));assertEquals("record-active",f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getString("recordingId"));
        when(f.cloud.request("GET","/recordings/record-active",null)).thenReturn(obj("status","recording"));ReflectionTestUtils.invokeMethod(f.service,"reconcileRecordings");assertEquals("unknown",f.store.snapshot().getJSONObject("commands").getJSONObject("HC-active").getString("status"));
        when(f.cloud.request("GET","/recordings/record-active",null)).thenReturn(obj("status","ready","assetId","preserved-asset"));ReflectionTestUtils.invokeMethod(f.service,"reconcileRecordings");
        assertEquals("preserved-asset",f.store.snapshot().getJSONObject("commands").getJSONObject("HC-active").getString("assetId"));assertEquals("completed",f.store.snapshot().getJSONObject("commands").getJSONObject("HC-active").getString("status"));
    }
    @Test void revokedCallDropsCredentialsAndCannotBeRevivedByLateConnectedReceipt(){
        Fixture f=fixture();f.store.update(s->{s.put("calls",obj("SIP-active",obj("id","SIP-active","actorId","owner","deviceIds",JSONArray.of("helmet-a"),"status","connected","recipients",JSONArray.of(obj("deviceId","helmet-a")),"credentials",obj("authorizationPassword","test-only"))));return null;});
        when(f.cloud.request("DELETE","/calls/SIP-active",null)).thenThrow(new IllegalStateException("test unavailable"));revoke(f);
        assertEquals("unknown",f.service.callState("SIP-active").getString("status"));assertFalse(f.store.snapshot().getJSONObject("calls").getJSONObject("SIP-active").containsKey("credentials"));
        ReflectionTestUtils.invokeMethod(f.service,"applyEvent",obj("callId","SIP-active","type","call.connected","sequence",1));assertEquals("unknown",f.service.callState("SIP-active").getString("status"));
        when(f.cloud.request("GET","/calls/SIP-active",null)).thenReturn(obj("status","ended"));ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");assertEquals("ended",f.service.callState("SIP-active").getString("status"));assertTrue(f.store.snapshot().getJSONObject("calls").containsKey("SIP-active"));
    }
    static class Fixture {
        final HelmetMediaService service;final HelmetCloudClient cloud;final DirectHelmetGateway gateway;final HelmetMediaStore store;
        Fixture(HelmetMediaService a,HelmetCloudClient b,DirectHelmetGateway c,HelmetMediaStore d){service=a;cloud=b;gateway=c;store=d;}
    }
}
