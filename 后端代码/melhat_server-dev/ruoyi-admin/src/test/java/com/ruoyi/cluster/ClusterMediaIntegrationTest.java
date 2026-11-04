package com.ruoyi.cluster;
import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.WearableBusinessStore;
import com.ruoyi.melhat.direct.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class ClusterMediaIntegrationTest extends ClusterRoutingContractTest {
    @TempDir Path directory;
    HelmetMediaService media;
    HelmetMediaStore store;
    HelmetCloudClient cloud;
    final List<JSONObject> sentWires=new ArrayList<>();
    @BeforeEach @SuppressWarnings("unchecked") void mediaSetup()throws Exception {
        oa.claimLogin("helmet","h","socket",30000,new JSONObject());
        store=new HelmetMediaStore(directory.resolve("private.json").toString(),directory.resolve("public").toString(),new WearableBusinessStore(db.jdbc,Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes(java.nio.charset.StandardCharsets.UTF_8))));
        cloud=mock(HelmetCloudClient.class);
        when(cloud.configured()).thenReturn(true);
        when(cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(obj("streamId","stream","pushUrl","rtmp://fixture/stream","expiresAt",Instant.now().plusSeconds(3600).toString()));
        when(cloud.request("GET","/streams/stream",null)).thenReturn(obj("streamId","stream","publishing",false,"statusVerified",true,"hlsUrl","https://fixture/stream?token=fixture","expiresAt",Instant.now().plusSeconds(20).toString()));
        DirectHelmetGateway gateway=mock(DirectHelmetGateway.class);
        when(gateway.isOnline("h")).thenReturn(true);
        when(gateway.supports("h")).thenReturn(true);
        doAnswer(i-> {
            rb.send(i.getArgument(0),i.getArgument(1),i.getArgument(2));
            return null;
        }
        ).when(gateway).sendCommand(anyString(),any(JSONObject.class),anyString());
        ObjectProvider<DirectHelmetGateway> provider=mock(ObjectProvider.class);
        when(provider.getObject()).thenReturn(gateway);
        media=new HelmetMediaService(cloud,store,new HelmetMediaProperties(),provider);
        ReflectionTestUtils.setField(media,"healthy",true);
        ReflectionTestUtils.setField(media,"commandRouter",rb);
        ra.register("helmet",(o,w,t,fence)-> {
            fence.run();sentWires.add(JSONObject.parseObject(w));
        }
        );
    }
    @Test void queuedPhotoHistoryAndRetryFollowOriginalDelivery() {
        JSONObject input=obj("action","take_photo","idempotencyKey","stable-request");
        JSONObject row=media.command("actor","h",input);
        assertEquals("queued",row.getString("status"));
        String id=row.getString("id");
        assertEquals(id,media.command("actor","h",input).getString("id"));
        assertEquals(1,db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command",Integer.class));
        assertNotNull(store.snapshot().getJSONObject("commands").getJSONObject(id));
        ra.dispatchOwnedBatch();
        assertEquals("sent",media.commandState(id).getString("status"));
        media.receipt("h",obj("act","ca_upload_photo","talkback_id",id,"status",true));
        assertEquals("acknowledged",media.commandState(id).getString("status"));
        assertFalse(media.commandState(id).containsKey("wire"));
    }
    @Test void queuedRecordingDoesNotClaimPushAlreadySent() {
        JSONObject row=media.command("actor","h",obj("action","start_recording","idempotencyKey","record-request","assignmentId","assignment","assignmentVersion",1));
        assertEquals("queued",row.getString("status"));
        assertFalse(row.getString("message").contains("已请求设备推流"));
        ra.dispatchOwnedBatch();
        assertEquals("waiting_media",media.commandState(row.getString("id")).getString("status"));
    }
    @Test void queuedStreamStopDoesNotDisableSipCalling() {
        ReflectionTestUtils.setField(media,"registeredDevices",Collections.singleton("h"));
        when(cloud.request(eq("PUT"),startsWith("/accounts/"),any())).thenReturn(obj("sipHost","fixture.invalid","wssUrl","wss://fixture.invalid"));
        when(cloud.request(eq("POST"),eq("/calls"),any())).thenReturn(obj("target","room"));
        JSONObject result=media.call("actor",Collections.singletonList("h"),false);
        assertNotNull(result.get("authorizationPassword"));
        assertEquals("offered",media.callState(result.getString("callId")).getString("status"));
        assertEquals(1,db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE delivery_status='QUEUED'",Integer.class));
    }
    @Test void queuedGbRequestKeepsLeaseAndDoesNotClaimPublishing() {
        JSONObject result=media.gbAcquire("gb-lease-0000000001","h",60);
        assertFalse(result.getBooleanValue("publishing"));
        assertFalse(store.snapshot().getJSONObject("gbLeases").getJSONObject("gb-lease-0000000001").getBooleanValue("released"));
        assertEquals("QUEUED",result.getString("deliveryStatus"));
    }
    @Test void recordingStopKeepsBusinessPhaseUntilCloudReadyAndSameKeyCompletes() {
        JSONObject start=startRecording(true),input=stopInput(start);
        JSONObject stop=media.command("actor","h",input);
        assertStopDelivery(stop,"finalizing","QUEUED");
        assertEquals(1,sentWires.size());
        assertEquals(stop.getString("id"),media.command("actor","h",input).getString("id"));
        ra.dispatchOwnedBatch();ra.dispatchOwnedBatch();
        assertStopDelivery(media.commandState(stop.getString("id")),"finalizing","SENT");
        assertStopWire(stop);
        // Socket delivery alone cannot create a playable recording.
        assertFalse(media.commandState(stop.getString("id")).containsKey("assetId"));
        when(cloud.request("GET","/recordings/recording",null)).thenReturn(obj("status","ready","assetId","asset-recording"));
        media.reconcile();
        JSONObject completed=media.command("actor","h",input);
        assertEquals(stop.getString("id"),completed.getString("id"));
        assertStopDelivery(completed,"completed","SENT");
        assertEquals("asset-recording",completed.getString("assetId"));
        verify(cloud,times(1)).request("DELETE","/recordings/recording",null);
        ra.dispatchOwnedBatch();assertEquals(2,sentWires.size());
    }
    @Test void recordingStopAssetEventCompletesOriginalCommandWithoutDeliveryOverwritingPhase() {
        JSONObject start=startRecording(true),input=stopInput(start);
        JSONObject stop=media.command("actor","h",input);
        assertStopDelivery(stop,"finalizing","QUEUED");
        ra.dispatchOwnedBatch();assertStopWire(stop);
        // An early transport ACK and a later device media report do not replace the cloud phase.
        rb.acknowledge(stop.getString("id"),"h",true);
        media.receipt("h",obj("act","upload_video_success","talkback_id",stop.get("id"),"status",true));
        assertStopDelivery(media.commandState(stop.getString("id")),"finalizing","ACKNOWLEDGED");
        when(cloud.request("GET","/assets?deviceId=h",null)).thenReturn(obj("assets",Collections.singletonList(obj("assetId","asset-event","kind","video","deviceId","h","requestId",start.get("id"),"status","ready","createdAt",rb.now().toString()))));
        when(cloud.request("GET","/events?after=0&limit=100",null)).thenReturn(obj("events",Collections.singletonList(obj("sequence",1,"type","asset.ready","deviceId","h","assetId","asset-event"))));
        media.reconcile();
        JSONObject completed=media.command("actor","h",input);
        assertEquals(stop.getString("id"),completed.getString("id"));
        assertStopDelivery(completed,"completed","ACKNOWLEDGED");
        assertEquals("asset-event",completed.getString("assetId"));
        ra.dispatchOwnedBatch();assertEquals(2,sentWires.size());
    }
    @Test void cancellingWaitingRecordingRemainsCompletedWhileCleanupQueuesAndSends() {
        JSONObject start=startRecording(false),input=stopInput(start);
        JSONObject stop=media.command("actor","h",input);
        assertStopDelivery(stop,"completed","QUEUED");
        assertEquals("cancelled",media.commandState(start.getString("id")).getString("status"));
        assertFalse(store.snapshot().getJSONObject("streams").getJSONObject("h").getBooleanValue("recordRequested"));
        ra.dispatchOwnedBatch();assertStopWire(stop);
        assertStopDelivery(media.command("actor","h",input),"completed","SENT");
        assertEquals(stop.getString("id"),media.command("actor","h",input).getString("id"));
        media.reconcile();ra.dispatchOwnedBatch();assertEquals(2,sentWires.size());
        verify(cloud,never()).request(eq("POST"),eq("/recordings"),any());
    }
    @Test void stopWithExistingViewerEndsUnusedAdmissionWithoutSendingCleanup() {
        JSONObject start=startRecording(true),input=stopInput(start);
        store.update(s->{s.getJSONObject("streams").getJSONObject("h").put("watchRequested",true);return null;});
        JSONObject stop=media.command("actor","h",input);
        assertStopDelivery(stop,"finalizing","CANCELLED");
        ra.dispatchOwnedBatch();assertEquals(1,sentWires.size());
        when(cloud.request("GET","/recordings/recording",null)).thenReturn(obj("status","ready","assetId","asset-recording"));
        ReflectionTestUtils.invokeMethod(media,"reconcileRecordings");
        assertStopDelivery(media.command("actor","h",input),"completed","CANCELLED");
    }
    @Test void expiredCleanupDoesNotPreventCloudFinalizationOrRetryCleanup() {
        JSONObject start=startRecording(true),input=stopInput(start);
        JSONObject stop=media.command("actor","h",input);
        assertStopDelivery(stop,"finalizing","QUEUED");
        db.jdbc.update("UPDATE wearable_transport_command SET deadline=0 WHERE command_id=?",stop.getString("id"));
        ra.dispatchOwnedBatch();
        assertStopDelivery(media.command("actor","h",input),"finalizing","EXPIRED");
        when(cloud.request("GET","/recordings/recording",null)).thenReturn(obj("status","ready","assetId","asset-recording"));
        media.reconcile();
        JSONObject completed=media.command("actor","h",input);
        assertEquals(stop.getString("id"),completed.getString("id"));
        assertStopDelivery(completed,"completed","EXPIRED");
        ra.dispatchOwnedBatch();assertEquals(1,sentWires.size());
    }
    private JSONObject startRecording(boolean recording) {
        when(cloud.request("GET","/health",null)).thenReturn(obj("ready",true));
        when(cloud.request("GET","/events?after=0&limit=100",null)).thenReturn(obj("events",new JSONArray()));
        JSONObject start=media.command("actor","h",obj("action","start_recording","idempotencyKey","stop-fixture-start"));
        ra.dispatchOwnedBatch();assertEquals(1,sentWires.size());
        if(recording){
            when(cloud.request("GET","/streams/stream",null)).thenReturn(obj("publishing",true));
            when(cloud.request(eq("POST"),eq("/recordings"),any())).thenReturn(obj("recordingId","recording"));
            when(cloud.request("GET","/recordings/recording",null)).thenReturn(obj("status","recording"));
            media.reconcile();assertEquals("recording",media.commandState(start.getString("id")).getString("status"));
        }
        return start;
    }
    private JSONObject stopInput(JSONObject start){return obj("action","stop_recording","idempotencyKey","stable-stop-request","sourceCommandId",start.get("id"));}
    private void assertStopDelivery(JSONObject stop,String phase,String delivery){
        assertEquals(phase,stop.getString("status"));assertEquals(delivery,stop.getString("deliveryStatus"));
        String id=stop.getString("id");assertTrue(id.startsWith("HC-"));
        assertEquals(phase,store.snapshot().getJSONObject("commands").getJSONObject(id).getString("status"));
        assertEquals(delivery,rb.read(id).getString("deliveryStatus"));
        assertEquals(2,db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command",Integer.class));
        assertEquals(0,db.jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE command_id LIKE 'HT-%' OR delivery_status='PREPARING'",Integer.class));
    }
    private void assertStopWire(JSONObject stop){
        assertEquals(2,sentWires.size());assertEquals("server_push_stop_rtsp",sentWires.get(1).getString("cmd"));
        assertEquals(stop.getString("id"),sentWires.get(1).getString("talkback_id"));
    }
}
