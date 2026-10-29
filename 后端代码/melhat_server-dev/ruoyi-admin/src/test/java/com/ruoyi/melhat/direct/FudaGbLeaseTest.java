package com.ruoyi.melhat.direct;
import com.alibaba.fastjson2.JSONObject;
import com.alibaba.fastjson2.JSONArray;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import java.time.Instant;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;
class FudaGbLeaseTest {
    @TempDir Path directory;
    private static final String LEASE="GB_lease_00000000001";
    @SuppressWarnings("unchecked") private Fixture fixture(){
        HelmetCloudClient cloud=mock(HelmetCloudClient.class);when(cloud.configured()).thenReturn(true);
        DirectHelmetGateway gateway=mock(DirectHelmetGateway.class);when(gateway.supports("helmet-a")).thenReturn(true);when(gateway.isOnline("helmet-a")).thenReturn(true);
        ObjectProvider<DirectHelmetGateway> provider=mock(ObjectProvider.class);when(provider.getObject()).thenReturn(gateway);
        HelmetMediaStore store=new HelmetMediaStore(directory.resolve("media.json").toString());
        HelmetMediaService service=new HelmetMediaService(cloud,store,new HelmetMediaProperties(),provider);ReflectionTestUtils.setField(service,"healthy",true);
        JSONObject stream=obj("streamId","stream-a","pushUrl","rtmp://private/publish-secret","hlsUrl","https://media/hls/stream-a/index.m3u8?token=private-play-token","expiresAt",Instant.now().plusSeconds(3600).toString(),"publishing",true,"statusVerified",true);
        when(cloud.request(eq("POST"),eq("/streams"),any())).thenReturn(stream);when(cloud.request("GET","/streams/stream-a",null)).thenReturn(stream);
        return new Fixture(service,store,gateway,cloud);
    }
    private JSONObject viewing(String action,String key,String session){
        return obj("action",action,"idempotencyKey",key,"viewerSessionId",session,"personId","P1","assignmentId","original-assignment","assignmentVersion",2,"siteId","site-1");
    }
    private JSONObject stream(Fixture f){return f.store.snapshot().getJSONObject("streams").getJSONObject("helmet-a");}
    private void expireLease(Fixture f){f.store.update(s->{s.getJSONObject("gbLeases").getJSONObject(LEASE).put("expiresAt",Instant.now().minusSeconds(1).toString());return null;});}
    @Test void duplicateAcquireDoesNotResendAndOnlyPlaybackTicketIsReturned() throws Exception {
        Fixture f=fixture();JSONObject first=f.service.gbAcquire(LEASE,"helmet-a",90);
        assertEquals("private-play-token",first.getString("playToken"));assertFalse(first.containsKey("pushUrl"));
        f.service.gbAcquire(LEASE,"helmet-a",90);
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),argThat(c->"server_push_open_rtsp".equals(c.getString("cmd"))));
        f.service.gbRelease(LEASE);f.service.gbRelease(LEASE);
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void releasingBothServiceLeasesPreservesHumanViewerSession() throws Exception {
        Fixture f=fixture();f.service.command("human-user","helmet-a",viewing("start_video","human-request-123","human-viewer-001"));
        clearInvocations(f.gateway);f.service.gbAcquire(LEASE,"helmet-a",90);f.service.gbAcquire("GB_lease_00000000002","helmet-a",90);
        f.service.gbRelease(LEASE);f.service.gbRelease("GB_lease_00000000002");
        verify(f.gateway,never()).sendCommand(anyString(),any());
        JSONObject current=stream(f);assertTrue(current.getBooleanValue("watchRequested"));assertTrue(current.getJSONArray("gbLeaseIds").isEmpty());
        assertEquals(1,current.getJSONObject("viewers").size());assertEquals("human-user",current.getJSONObject("viewers").getJSONObject("human-viewer-001").getString("actorId"));
    }
    @Test void expiryReleasesOfflineLeaseAndBusyOrNonHelmetCannotAcquire() throws Exception {
        Fixture f=fixture();assertThrows(IllegalArgumentException.class,()->f.service.gbAcquire(LEASE,"belt-a",90));
        f.store.update(s->{s.put("calls",obj("call-1",obj("deviceIds",JSONArray.of("helmet-a"),"status","connected")));return null;});
        assertEquals("GB_DEVICE_BUSY",assertThrows(IllegalStateException.class,()->f.service.gbAcquire(LEASE,"helmet-a",90)).getMessage());
        f.store.update(s->{s.remove("calls");return null;});f.service.gbAcquire(LEASE,"helmet-a",90);when(f.gateway.isOnline("helmet-a")).thenReturn(false);
        expireLease(f);clearInvocations(f.gateway);f.service.expireGbLeases();assertFalse(stream(f).getBooleanValue("watchRequested"));
        verify(f.gateway,never()).sendCommand(anyString(),any());
    }
    @Test void humanStopCannotCancelServiceLeaseEvenWhenSessionIdsMatch() throws Exception {
        Fixture f=fixture();f.service.gbAcquire(LEASE,"helmet-a",90);
        f.service.command("human-user","helmet-a",viewing("start_video","human-start-same-id",LEASE));
        clearInvocations(f.gateway);
        f.service.command("human-user","helmet-a",viewing("stop_video","human-stop-same-id",LEASE));
        assertTrue(stream(f).getJSONObject("viewers").isEmpty());assertTrue(stream(f).getJSONArray("gbLeaseIds").contains(LEASE));
        assertTrue(stream(f).getBooleanValue("watchRequested"));verify(f.gateway,never()).sendCommand(anyString(),any());
        f.service.gbRelease(LEASE);
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void expiredHumanViewerDoesNotCancelServiceDemand() throws Exception {
        Fixture f=fixture();f.service.command("human-user","helmet-a",viewing("start_video","human-expiry-start","human-expiry-viewer"));
        f.service.gbAcquire(LEASE,"helmet-a",90);clearInvocations(f.gateway);
        f.store.update(s->{s.getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").getJSONObject("human-expiry-viewer").put("expiresAt",Instant.now().minusSeconds(1).toString());return null;});
        ReflectionTestUtils.invokeMethod(f.service,"expireViewers");
        assertTrue(stream(f).getJSONObject("viewers").isEmpty());assertTrue(stream(f).getBooleanValue("watchRequested"));
        verify(f.gateway,never()).sendCommand(anyString(),any());
        f.service.gbRelease(LEASE);
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void assignmentRevocationStillCancelsHumanRecordingButKeepsDeviceAuthorizedGbLease() throws Exception {
        Fixture f=fixture();f.service.command("human-user","helmet-a",viewing("start_video","revoked-human-start","revoked-human-viewer"));
        JSONObject recording=f.service.command("human-user","helmet-a",viewing("start_recording","revoked-record-start","revoked-human-viewer"));
        f.service.gbAcquire(LEASE,"helmet-a",90);clearInvocations(f.gateway);
        ReflectionTestUtils.invokeMethod(f.service,"invalidateSessions",(java.util.function.BiPredicate<String,JSONObject>)(actor,row)->false);
        ReflectionTestUtils.invokeMethod(f.service,"startPendingRecordings");
        JSONObject current=stream(f);assertTrue(current.getJSONObject("viewers").isEmpty());assertFalse(current.getBooleanValue("recordRequested"));
        assertEquals("cancelled",f.store.snapshot().getJSONObject("commands").getJSONObject(recording.getString("id")).getString("status"));
        assertTrue(current.getJSONArray("gbLeaseIds").contains(LEASE));assertTrue(current.getBooleanValue("watchRequested"));
        verify(f.cloud,never()).request(eq("POST"),eq("/recordings"),any());verify(f.gateway,never()).sendCommand(anyString(),any());
        f.service.gbRelease(LEASE);
        verify(f.gateway,times(1)).sendCommand(eq("helmet-a"),argThat(c->"server_push_stop_rtsp".equals(c.getString("cmd"))));
    }
    @Test void expiredGbLeasePreservesHumanViewerAndActiveRecording() throws Exception {
        Fixture f=fixture();f.service.command("human-user","helmet-a",viewing("start_video","keep-human-start","keep-human-viewer"));
        f.service.command("human-user","helmet-a",viewing("start_recording","keep-record-start","keep-human-viewer"));
        f.service.gbAcquire(LEASE,"helmet-a",90);expireLease(f);clearInvocations(f.gateway);f.service.expireGbLeases();
        JSONObject current=stream(f);assertTrue(current.getBooleanValue("recordRequested"));assertTrue(current.getBooleanValue("watchRequested"));
        assertTrue(current.getJSONObject("viewers").containsKey("keep-human-viewer"));assertTrue(current.getJSONArray("gbLeaseIds").isEmpty());
        assertTrue(f.store.snapshot().getJSONObject("gbLeases").getJSONObject(LEASE).getBooleanValue("released"));
        verify(f.gateway,never()).sendCommand(anyString(),any());
    }
    @Test void serviceReleaseCannotRemoveHumanSessionWithSameIdentifier() throws Exception {
        Fixture f=fixture();f.service.command("human-user","helmet-a",viewing("start_video","same-id-human-start",LEASE));
        f.service.gbAcquire(LEASE,"helmet-a",90);clearInvocations(f.gateway);f.service.gbRelease(LEASE);
        assertTrue(stream(f).getJSONObject("viewers").containsKey(LEASE));assertTrue(stream(f).getBooleanValue("watchRequested"));
        verify(f.gateway,never()).sendCommand(anyString(),any());
    }
    @Test void scheduledGbExpiryHonorsCurrentMaintenancePause() throws Exception {
        Fixture f=fixture();f.service.gbAcquire(LEASE,"helmet-a",90);expireLease(f);clearInvocations(f.gateway);
        com.ruoyi.guardian.WearableMaintenance maintenance=mock(com.ruoyi.guardian.WearableMaintenance.class);
        when(maintenance.tryBeginWrite()).thenReturn(false);ReflectionTestUtils.setField(f.service,"maintenance",maintenance);
        f.service.expireGbLeases();assertFalse(f.store.snapshot().getJSONObject("gbLeases").getJSONObject(LEASE).getBooleanValue("released"));
        verify(f.gateway,never()).sendCommand(anyString(),any());verify(maintenance,never()).endWrite();
    }
    private static class Fixture {
        final HelmetMediaService service;final HelmetMediaStore store;final DirectHelmetGateway gateway;final HelmetCloudClient cloud;
        Fixture(HelmetMediaService s,HelmetMediaStore st,DirectHelmetGateway g,HelmetCloudClient c){service=s;store=st;gateway=g;cloud=c;}
    }
}
