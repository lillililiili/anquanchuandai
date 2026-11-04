package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.AdminQueryService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Arrays;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

class HelmetUploadRetryTest {
    @TempDir Path directory;
    private static final String ID="HC-original-upload",DEVICE="helmet-a",NAME="20261103161708.mp4",MD5="0123456789abcdef";
    @SuppressWarnings("unchecked") private Fixture fixture(){
        Fixture f=new Fixture();f.cloud=mock(HelmetCloudClient.class);when(f.cloud.configured()).thenReturn(true);
        when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenReturn(obj("items",new JSONArray()));
        f.gateway=mock(DirectHelmetGateway.class);when(f.gateway.isOnline(DEVICE)).thenReturn(true);
        f.provider=mock(ObjectProvider.class);when(f.provider.getObject()).thenReturn(f.gateway);
        f.store=new HelmetMediaStore(directory.resolve("retry.json").toString());
        f.service=new HelmetMediaService(f.cloud,f.store,new HelmetMediaProperties(),f.provider);ReflectionTestUtils.setField(f.service,"healthy",true);
        JSONObject original=context();original.remove("retryKey");original.putAll(obj("id",ID,"deviceId",DEVICE,"actorId","operator",
                "action","upload_recording","requestId","original-request-key","fingerprint","original-fingerprint","personName","原姓名",
                "status","acknowledged","createdAt",Instant.now().minusSeconds(600).toString(),"expiresAt",Instant.now().minusSeconds(570).toString(),
                "requestedFiles",JSONArray.of(obj("fileName",NAME,"progressId",MD5))));
        f.store.update(s->{s.put("commands",obj(ID,original));return null;});return f;
    }
    private JSONObject context(){return obj("retryKey","retry-intent-001","personId","person-original","assignmentId","issue-original",
            "assignmentVersion",3,"siteId","site-original","areaId","area-original","ledgerDeviceId","ledger-original");}
    private JSONObject saved(Fixture f){return f.store.snapshot().getJSONObject("commands").getJSONObject(ID);}
    private JSONObject ready(){return obj("assetId","actual-video","deviceId",DEVICE,"kind","video","status","ready",
            "createdAt",Instant.now().toString(),"originalName",NAME,"progressId",MD5);}
    @Test void retryUsesSameCommandAndFrozenScopeAndPersistsBeforeWrite() throws Exception {
        Fixture f=fixture();JSONObject before=saved(f),input=context();input.put("name","后来姓名");input.put("parameters",obj("files",JSONArray.of("wrong.mp4")));
        doAnswer(call->{JSONObject intent=saved(f);assertEquals("requesting",intent.getString("status"));
            assertEquals("retry-intent-001",intent.getJSONArray("uploadRetries").getJSONObject(0).getString("retryKey"));
            JSONObject wire=call.getArgument(1);assertEquals(ID,wire.getString("talkback_id"));assertEquals(JSONArray.of(NAME),wire.getJSONArray("file_list"));return null;
        }).when(f.gateway).sendCommand(eq(DEVICE),any());
        JSONObject answer=f.service.retryUpload("operator",DEVICE,ID,input);assertEquals(ID,answer.getString("id"));assertEquals("sent",answer.getString("status"));
        JSONObject after=saved(f);assertEquals(1,f.store.snapshot().getJSONObject("commands").size());
        for(String key:Arrays.asList("createdAt","requestId","fingerprint","requestedFiles","personId","personName","siteId","areaId","assignmentId","assignmentVersion","ledgerDeviceId"))assertEquals(before.get(key),after.get(key),key);
        assertTrue(Instant.parse(after.getString("expiresAt")).isAfter(Instant.now()));
        f.service.retryUpload("operator",DEVICE,ID,input);verify(f.gateway,times(1)).sendCommand(eq(DEVICE),any());
    }
    @Test void unknownWriteRemainsSingleIntentAcrossRestartAndNewKeyNeedsCooldown() throws Exception {
        Fixture f=fixture();doThrow(new java.io.IOException("socket outcome unknown")).when(f.gateway).sendCommand(eq(DEVICE),any());
        assertEquals("unknown",f.service.retryUpload("operator",DEVICE,ID,context()).getString("status"));
        HelmetMediaStore recovered=new HelmetMediaStore(directory.resolve("retry.json").toString());
        HelmetMediaService restarted=new HelmetMediaService(f.cloud,recovered,new HelmetMediaProperties(),f.provider);
        // Even an unavailable cloud cannot cause the same durable intent to send again.
        assertEquals("unknown",restarted.retryUpload("operator",DEVICE,ID,context()).getString("status"));
        JSONObject next=context();next.put("retryKey","retry-intent-002");
        assertThrows(IllegalStateException.class,()->f.service.retryUpload("operator",DEVICE,ID,next));
        verify(f.gateway,times(1)).sendCommand(eq(DEVICE),any());assertEquals(1,saved(f).getJSONArray("uploadRetries").size());
    }
    @Test void readyAssetReturnsCompletedWithoutResendingOrInventingCapturePerson() throws Exception {
        Fixture f=fixture();when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenReturn(obj("items",JSONArray.of(ready())));
        JSONObject answer=f.service.retryUpload("operator",DEVICE,ID,context());assertEquals("completed",answer.getString("status"));
        assertEquals("already_available",answer.getJSONArray("uploadRetries").getJSONObject(0).getString("status"));
        assertEquals("actual-video",answer.getString("assetId"));verify(f.gateway,never()).sendCommand(anyString(),any());
        JSONObject asset=f.service.assets(DEVICE).getJSONObject(0);assertEquals(ID,asset.getString("requestId"));assertNull(asset.get("personId"));
        assertEquals("person-original",asset.getString("receivedPersonId"));assertEquals("原姓名",asset.getString("receivedPersonName"));
    }
    @Test void cloudFailureAndUnreadyMatchingFileNeverPermitAResend() throws Exception {
        Fixture f=fixture();when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenThrow(new IllegalStateException("cloud timeout"));
        assertEquals(503,assertThrows(AdminQueryService.QueryFailed.class,()->f.service.retryUpload("operator",DEVICE,ID,context())).code);
        JSONObject asset=ready();asset.put("status","processing");doReturn(obj("items",JSONArray.of(asset))).when(f.cloud).request("GET","/assets?deviceId="+DEVICE,null);
        assertThrows(IllegalStateException.class,()->f.service.retryUpload("operator",DEVICE,ID,context()));
        verify(f.gateway,never()).sendCommand(anyString(),any());assertNull(saved(f).get("uploadRetries"));
    }
    @Test void differentActorDeviceOrCurrentScopeCannotBorrowOriginalUpload() throws Exception {
        Fixture f=fixture();assertThrows(AdminQueryService.QueryFailed.class,()->f.service.retryUpload("other",DEVICE,ID,context()));
        assertThrows(AdminQueryService.QueryFailed.class,()->f.service.retryUpload("operator","helmet-b",ID,context()));
        for(String field:Arrays.asList("personId","assignmentId","assignmentVersion","siteId","areaId","ledgerDeviceId")){
            JSONObject changed=context();changed.put(field,"changed");assertThrows(AdminQueryService.QueryFailed.class,()->f.service.retryUpload("operator",DEVICE,ID,changed),field);}
        verify(f.gateway,never()).sendCommand(anyString(),any());verify(f.cloud,never()).request(anyString(),anyString(),any());
    }
    @Test void fastAckOrReadyEvidenceCannotBeOverwrittenBySocketReturn() throws Exception {
        Fixture f=fixture();doAnswer(call->{f.service.receipt(DEVICE,obj("act","push_to_client","talkback_id",ID,"res",obj("status",true)));return null;}).when(f.gateway).sendCommand(eq(DEVICE),any());
        JSONObject answer=f.service.retryUpload("operator",DEVICE,ID,context());assertEquals("acknowledged",answer.getString("status"));
        assertEquals("acknowledged",answer.getJSONArray("uploadRetries").getJSONObject(0).getString("status"));assertNull(answer.get("assetId"));
        when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenReturn(obj("items",JSONArray.of(ready())));
        ReflectionTestUtils.invokeMethod(f.service,"applyEvent",obj("type","asset.ready","assetId","actual-video","deviceId",DEVICE,"sequence",1));
        assertEquals("completed",saved(f).getString("status"));assertEquals("completed",saved(f).getJSONArray("uploadRetries").getJSONObject(0).getString("status"));
    }
    @Test void concurrentDuplicateRequestsOnlyWriteOnce() throws Exception {
        Fixture f=fixture();ExecutorService pool=Executors.newFixedThreadPool(2);CountDownLatch start=new CountDownLatch(1);
        Callable<JSONObject> request=()->{start.await();return f.service.retryUpload("operator",DEVICE,ID,context());};
        try{Future<JSONObject> first=pool.submit(request),second=pool.submit(request);start.countDown();assertEquals(ID,first.get(10,TimeUnit.SECONDS).getString("id"));assertEquals(ID,second.get(10,TimeUnit.SECONDS).getString("id"));}
        finally{pool.shutdownNow();}
        verify(f.gateway,times(1)).sendCommand(eq(DEVICE),any());assertEquals(1,saved(f).getJSONArray("uploadRetries").size());
    }
    @Test void fileReadyDuringSocketWriteRemainsCompleted() throws Exception {
        Fixture f=fixture();doAnswer(call->{
            when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenReturn(obj("items",JSONArray.of(ready())));
            ReflectionTestUtils.invokeMethod(f.service,"applyEvent",obj("type","asset.ready","assetId","actual-video","deviceId",DEVICE,"sequence",1));return null;
        }).when(f.gateway).sendCommand(eq(DEVICE),any());
        JSONObject answer=f.service.retryUpload("operator",DEVICE,ID,context());assertEquals("completed",answer.getString("status"));
        assertEquals("completed",answer.getJSONArray("uploadRetries").getJSONObject(0).getString("status"));assertEquals("actual-video",answer.getString("assetId"));
        verify(f.gateway,times(1)).sendCommand(eq(DEVICE),any());
    }
    @Test void similarlyNamedButDifferentContentCannotCompleteOriginalUpload() throws Exception {
        Fixture f=fixture();JSONObject wrong=ready();wrong.put("progressId","different-md5");when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenReturn(obj("items",JSONArray.of(wrong)));
        assertEquals("sent",f.service.retryUpload("operator",DEVICE,ID,context()).getString("status"));assertNull(saved(f).get("assetId"));
        verify(f.gateway,times(1)).sendCommand(eq(DEVICE),any());
    }
    @Test void narrowRetryRejectsMultiFileBatchIncludingPartiallyReadyBatch() throws Exception {
        Fixture f=fixture();f.store.update(s->{s.getJSONObject("commands").getJSONObject(ID).getJSONArray("requestedFiles").add(obj("fileName","20261103161808.mp4","progressId","another-file-md5"));return null;});
        when(f.cloud.request("GET","/assets?deviceId="+DEVICE,null)).thenReturn(obj("items",JSONArray.of(ready())));
        assertThrows(IllegalArgumentException.class,()->f.service.retryUpload("operator",DEVICE,ID,context()));
        verify(f.gateway,never()).sendCommand(anyString(),any());assertNull(saved(f).get("uploadRetries"));assertNull(saved(f).get("assetId"));
    }
    private static class Fixture {HelmetMediaService service;HelmetCloudClient cloud;DirectHelmetGateway gateway;HelmetMediaStore store;ObjectProvider<DirectHelmetGateway> provider;}
}
