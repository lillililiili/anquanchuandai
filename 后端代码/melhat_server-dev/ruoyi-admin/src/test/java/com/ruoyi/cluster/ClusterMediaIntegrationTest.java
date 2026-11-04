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
}
