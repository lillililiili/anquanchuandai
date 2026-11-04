package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.alibaba.fastjson2.JSONArray;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import java.util.Arrays;
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
    @Test void temporaryMediaFailureIsNotAnAuthoritativeEmptyMaterialList(){
        Fixture f=fixture();ReflectionTestUtils.setField(f.service,"healthy",false);
        assertEquals(503,assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.assets("helmet-a")).code);
        assertFalse(f.service.media("helmet-a").getBooleanValue("itemsAvailable"));
        ReflectionTestUtils.setField(f.service,"healthy",true);when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenThrow(new IllegalStateException("temporary cloud failure"));
        assertEquals(503,assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.assets("helmet-a")).code);
        assertFalse(f.service.media("helmet-a").getBooleanValue("itemsAvailable"));
        doReturn(obj("items",new JSONArray())).when(f.cloud).request("GET","/assets?deviceId=helmet-a",null);
        assertTrue(f.service.media("helmet-a").getBooleanValue("itemsAvailable"));
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
    @Test void mediaOriginAndHistoricalNameComeOnlyFromTheOriginalCommand() {
        Fixture f=fixture();JSONObject input=obj("action","take_photo","idempotencyKey","captured-photo-001",
                "personId","person-original","name","记录时姓名","siteId","site-original","assignmentId","issue-original","assignmentVersion",4);
        JSONObject command=f.service.command("operator","helmet-a",input);
        input.put("name","后来姓名");
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(
                obj("assetId","photo-1","deviceId","helmet-a","kind","photo","status","ready","createdAt",java.time.Instant.now().toString(),"requestId",command.get("id")),
                obj("assetId","video-unlinked","deviceId","helmet-a","kind","video"))));
        JSONArray files=f.service.assets("helmet-a");JSONObject photo=files.getJSONObject(0);
        assertEquals("DEVICE_PHOTO",photo.getString("mediaOrigin"));assertEquals("take_photo",photo.getString("commandAction"));
        assertEquals("记录时姓名",photo.getString("personName"));assertEquals("issue-original",photo.getString("assignmentId"));
        assertEquals(4,photo.getIntValue("assignmentVersion"));assertEquals("UNKNOWN",files.getJSONObject(1).getString("mediaOrigin"));
        assertNull(files.getJSONObject(1).get("personId"));assertNull(files.getJSONObject(1).get("duration"));
    }
    @Test void platformAndDeviceRecordingsHaveExplicitOriginsWithoutInventingOldNames() {
        Fixture f=fixture();f.store.update(s->{s.put("commands",obj(
                "HC-platform",obj("id","HC-platform","deviceId","helmet-a","action","start_recording","personId","original","siteId","site-original","createdAt","2026-11-02T01:00:00Z"),
                "HC-device",obj("id","HC-device","deviceId","helmet-a","action","upload_recording","personId","current-uploader","personName","当前上传者","siteId","site-current","createdAt","2026-11-02T01:00:00Z")));
            return null;});
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(
                obj("assetId","platform-1","deviceId","helmet-a","kind","video","status","ready","createdAt","2026-11-02T01:01:00Z","requestId","HC-platform"),
                obj("assetId","device-1","deviceId","helmet-a","kind","video","status","ready","createdAt","2026-11-02T01:01:00Z","requestId","HC-device"))));
        JSONArray files=f.service.assets("helmet-a");
        assertEquals("PLATFORM_RECORDING",files.getJSONObject(0).getString("mediaOrigin"));
        assertEquals("original",files.getJSONObject(0).getString("personId"));assertNull(files.getJSONObject(0).get("personName"));
        assertEquals("DEVICE_RECORDING",files.getJSONObject(1).getString("mediaOrigin"));
        assertNull(files.getJSONObject(1).get("personName"));assertNull(files.getJSONObject(1).get("personId"));
    }
    @Test void photoBindingEventCompletesOnlyTheExactOriginalRequestAndPreservesCapturedAuthority() {
        Fixture f=fixture();JSONObject command=f.service.command("owner","helmet-a",obj("action","take_photo","idempotencyKey","photo-bound-001",
                "personId","original-person","name","原姓名","siteId","original-site","assignmentId","original-issue","assignmentVersion",1));
        String id=command.getString("id");JSONObject asset=obj("assetId","photo-bound","deviceId","helmet-a","kind","photo","status","ready",
                "createdAt",java.time.Instant.now().toString(),"requestId",id,"requestIdSource","report/add_image.talkback_id");
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(asset)));
        f.store.update(s->{s.getJSONObject("commands").getJSONObject(id).put("status","timeout");return null;});
        JSONObject event=obj("type","asset.bound","assetId","photo-bound","deviceId","helmet-a","requestId",id,"sequence",1);
        ReflectionTestUtils.invokeMethod(f.service,"applyEvent",event);
        assertEquals("completed",f.store.snapshot().getJSONObject("commands").getJSONObject(id).getString("status"));
        JSONObject file=f.service.assets("helmet-a").getJSONObject(0);
        assertEquals("original-person",file.getString("personId"));assertEquals("原姓名",file.getString("personName"));
        ReflectionTestUtils.invokeMethod(f.service,"applyEvent",event);
        assertEquals("photo-bound",f.store.snapshot().getJSONObject("commands").getJSONObject(id).getString("assetId"));
        asset.put("assetId","another-file");event.put("assetId","another-file");event.put("sequence",2);
        ReflectionTestUtils.invokeMethod(f.service,"applyEvent",event);
        assertEquals("photo-bound",f.store.snapshot().getJSONObject("commands").getJSONObject(id).getString("assetId"));
        assertNull(f.service.assets("helmet-a").getJSONObject(0).get("personId"));
    }
    @Test void photoBindingCannotMatchByTimingOrUseAnotherDeviceOldFileWrongActionOrUnreadyFile() {
        Fixture f=fixture();JSONObject command=f.service.command("owner","helmet-a",obj("action","take_photo","idempotencyKey","photo-invalid-001","personId","person-a","siteId","site-a"));
        String id=command.getString("id");
        JSONObject original=obj("assetId","untrusted-file","deviceId","helmet-a","kind","photo","status","ready","createdAt",java.time.Instant.now().toString(),"requestId",id);
        for(JSONObject changes:Arrays.asList(obj("requestId",null),obj("deviceId","helmet-b"),obj("createdAt","2020-01-01T00:00:00Z"),obj("createdAt",null),obj("kind","video"),obj("status","uploading"))) {
            JSONObject asset=new JSONObject(original);asset.putAll(changes);
            when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(asset)));
            ReflectionTestUtils.invokeMethod(f.service,"applyEvent",obj("type","asset.bound","assetId","untrusted-file","deviceId","helmet-a","requestId",id,"sequence",1));
            assertEquals("sent",f.store.snapshot().getJSONObject("commands").getJSONObject(id).getString("status"));
            assertNull(f.service.assets("helmet-a").getJSONObject(0).get("personId"));
        }
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
    @Test void firmwareRecordingQuerySelectsHighDefinitionWithCompactDatesAndRejectsInvalidDates(){
        JSONObject wire=HelmetMediaService.wire("list_recordings",obj("startTime","2026-10-23 08:01:02","endTime","2026-10-23 10:00:00"));
        assertEquals("server_push_get_local_video_list",wire.getString("cmd"));
        assertEquals("20261023080102",wire.getString("start_time"));
        assertEquals("20261023100000",wire.getString("end_time"));
        assertEquals("1",wire.get("video_type"));
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
    private Fixture offeredCall(){
        Fixture f=fixture();f.store.update(s->{s.put("calls",obj("SIP-stages",obj("id","SIP-stages","actorId","owner","status","offered","deviceIds",JSONArray.of("helmet-a"),"credentials",obj("authorizationPassword","test-only","expiresAt",java.time.Instant.now().plusSeconds(60).toString()))));return null;});return f;
    }
    private void callEvent(Fixture f,String type,long sequence,String time,String... devices){
        ReflectionTestUtils.invokeMethod(f.service,"applyEvent",obj("callId","SIP-stages","type",type,"sequence",sequence,"createdAt",time,"connectedDeviceIds",new JSONArray(Arrays.asList(devices))));
    }
    @Test void actualAnsweredEventKeepsDeviceEvidenceWithoutClaimingBothSidesConnected(){
        Fixture f=offeredCall();callEvent(f,"call.answered",31,"2026-10-29T09:08:41Z","helmet-a","unrelated-device","helmet-a");
        JSONObject state=f.service.callState("SIP-stages");assertEquals("answered",state.getString("status"));assertEquals(JSONArray.of("helmet-a"),state.getJSONArray("connectedDeviceIds"));
        assertFalse(state.containsKey("statusVerified"));assertFalse(state.containsKey("credentials"));assertEquals("test-only",f.service.credentials("SIP-stages","owner").getString("authorizationPassword"));
        callEvent(f,"call.answered",31,"2026-10-29T09:09:00Z");assertEquals(state,f.service.callState("SIP-stages"));
        callEvent(f,"call.connected",32,"2026-10-29T09:09:01Z","helmet-a");assertEquals("connected",f.service.callState("SIP-stages").getString("status"));
        callEvent(f,"call.answered",33,"2026-10-29T09:09:02Z");assertEquals("connected",f.service.callState("SIP-stages").getString("status"));
        callEvent(f,"call.ended",34,"2026-10-29T09:09:03Z","helmet-a");assertEquals("ended",f.service.callState("SIP-stages").getString("status"));assertTrue(f.service.callState("SIP-stages").getJSONArray("connectedDeviceIds").isEmpty());
        assertThrows(IllegalArgumentException.class,()->f.service.credentials("SIP-stages","owner"));
        JSONObject terminal=f.service.callState("SIP-stages");callEvent(f,"call.connected",35,"2026-10-29T09:09:04Z","helmet-a");callEvent(f,"call.answered",36,"2026-10-29T09:09:05Z","helmet-a");callEvent(f,"call.ended",37,"2026-10-29T09:09:06Z");assertEquals(terminal,f.service.callState("SIP-stages"));
    }
    @Test void cloudPollRecoversAnsweredAndOnlyCopiesActualVerificationEvidence(){
        Fixture f=offeredCall();when(f.cloud.request("GET","/calls/SIP-stages",null)).thenReturn(obj("status","answered","connectedDeviceIds",JSONArray.of("helmet-a"),"statusVerified",true));
        ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");assertEquals("answered",f.service.callState("SIP-stages").getString("status"));assertTrue(f.service.callState("SIP-stages").getBooleanValue("statusVerified"));
        when(f.cloud.request("GET","/calls/SIP-stages",null)).thenReturn(obj("status","offered","connectedDeviceIds",new JSONArray()));ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");assertEquals("answered",f.service.callState("SIP-stages").getString("status"));
        when(f.cloud.request("GET","/calls/SIP-stages",null)).thenReturn(obj("status","connected","connectedDeviceIds",JSONArray.of("helmet-a")));ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");assertEquals("connected",f.service.callState("SIP-stages").getString("status"));assertFalse(f.service.callState("SIP-stages").containsKey("statusVerified"));
        f.service.endCall("SIP-stages");assertThrows(IllegalArgumentException.class,()->f.service.credentials("SIP-stages","owner"));
        ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");assertEquals("ending",f.service.callState("SIP-stages").getString("status"));
        when(f.cloud.request("GET","/calls/SIP-stages",null)).thenReturn(obj("status","ended","statusVerified",true));ReflectionTestUtils.invokeMethod(f.service,"reconcileCalls");assertEquals("ended",f.service.callState("SIP-stages").getString("status"));assertTrue(f.service.callState("SIP-stages").getJSONArray("connectedDeviceIds").isEmpty());
    }
    @Test void operatorAnswerWithoutADeviceLegNeverInventsDeviceParticipation(){
        Fixture f=offeredCall();callEvent(f,"call.answered",1,"2026-10-29T09:08:41Z");assertEquals("answered",f.service.callState("SIP-stages").getString("status"));assertTrue(f.service.callState("SIP-stages").getJSONArray("connectedDeviceIds").isEmpty());
        f.store.update(s->{s.getJSONObject("calls").getJSONObject("SIP-stages").put("sessionInvalidatedAt","2026-10-29T09:08:42Z");s.getJSONObject("calls").getJSONObject("SIP-stages").put("status","unknown");return null;});
        callEvent(f,"call.answered",2,"2026-10-29T09:08:43Z","helmet-a");assertEquals("unknown",f.service.callState("SIP-stages").getString("status"));assertTrue(f.service.callState("SIP-stages").getJSONArray("connectedDeviceIds").isEmpty());
    }
    @Test void knownCallRejectionsHappenBeforeMediaRowsAndCommands() throws Exception {
        Fixture f=fixture();when(f.gateway.isOnline("helmet-a")).thenReturn(false);
        assertEquals("DEVICE_OFFLINE",assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.call("owner",Arrays.asList("helmet-a"),false)).errorCode);
        when(f.gateway.isOnline("helmet-a")).thenReturn(true);
        assertEquals("SIP_NOT_REGISTERED",assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.call("owner",Arrays.asList("helmet-a"),false)).errorCode);
        ReflectionTestUtils.setField(f.service,"healthy",false);
        assertEquals("MEDIA_SERVICE_UNAVAILABLE",assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->f.service.call("owner",Arrays.asList("helmet-a"),false)).errorCode);
        assertNull(f.store.snapshot().getJSONObject("calls"));verify(f.gateway,never()).sendCommand(anyString(),any());verify(f.cloud,never()).request(anyString(),anyString(),any());
        Fixture busy=offeredCall();callEvent(busy,"call.answered",1,"2026-10-29T10:00:30Z","helmet-a");
        assertEquals("CALL_BUSY",assertThrows(com.ruoyi.guardian.AdminQueryService.QueryFailed.class,()->busy.service.call("another-owner",Arrays.asList("helmet-a"),false)).errorCode);
        assertEquals(1,busy.store.snapshot().getJSONObject("calls").size());verify(busy.gateway,never()).sendCommand(anyString(),any());verify(busy.cloud,never()).request(anyString(),anyString(),any());
    }
    @Test void uploadedHistoricalVideoCanMatchCommandWithoutClaimingCurrentWearer(){
        Fixture f=fixture();String now=java.time.Instant.now().toString();
        f.store.update(s->{s.put("commands",obj("HC-upload",obj("id","HC-upload","deviceId","helmet-a","action","upload_recording","createdAt",java.time.Instant.now().minusSeconds(30).toString(),"personId","new-wearer","siteId","new-site","requestedFiles",JSONArray.of(obj("fileName","old.mp4","progressId","abc123")))));return null;});
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("assets",JSONArray.of(obj("assetId","asset-old","kind","video","status","ready","deviceId","helmet-a","originalName","old.mp4","progressId","abc123","createdAt",now))));
        JSONObject asset=f.service.assets("helmet-a").getJSONObject(0);
        assertEquals("HC-upload",asset.getString("requestId"));assertFalse(asset.getBooleanValue("unassigned"));assertNull(asset.get("personId"));assertEquals("new-site",asset.get("siteId"));
        assertEquals("new-wearer",asset.getString("receivedPersonId"));assertEquals("UPLOAD_REQUEST",asset.getString("scopeBasis"));
        assertEquals("RECEIVED_AT",asset.getString("timeBasis"));assertEquals(now,asset.getString("receivedAt"));
        JSONObject different=obj("assetId","another","kind","video","status","ready","deviceId","helmet-a","originalName","old.mp4","progressId","unmatched","createdAt",now);
        when(f.cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("assets",JSONArray.of(different)));
        JSONObject unmatched=f.service.assets("helmet-a").getJSONObject(0);assertNull(unmatched.get("siteId"));assertNull(unmatched.get("receivedPersonId"));
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
