package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.GuardianIngest;
import com.ruoyi.guardian.WearableBusinessStore;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class HelmetLocalRecordingSyncTest {
    final Instant start=Instant.now().minusSeconds(90),stop=start.plusSeconds(20);
    final String fileName=DateTimeFormatter.ofPattern("yyyyMMddHHmmss").withZone(ZoneId.of("Asia/Shanghai")).format(start.minusSeconds(1))+".mp4";
    final String md5="file-md5-for-new-recording";
    final WearableBusinessStore business=new WearableBusinessStore(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","")),Base64.getEncoder().encodeToString(new byte[32]));
    final HelmetMediaStore store=new HelmetMediaStore("missing-"+UUID.randomUUID()+".json","public-"+UUID.randomUUID(),business);
    final DirectHelmetGateway gateway=mock(DirectHelmetGateway.class);
    final HelmetCloudClient cloud=mock(HelmetCloudClient.class);
    final GuardianIngest ingest=mock(GuardianIngest.class);
    final HelmetMediaService media;
    final HelmetLocalRecordingSync sync;
    @SuppressWarnings("unchecked") HelmetLocalRecordingSyncTest(){
        ObjectProvider<DirectHelmetGateway> gatewayProvider=mock(ObjectProvider.class);when(gatewayProvider.getObject()).thenReturn(gateway);
        when(gateway.supports("helmet-a")).thenReturn(true);when(gateway.isOnline("helmet-a")).thenReturn(true);when(cloud.configured()).thenReturn(true);
        when(cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",new JSONArray()));
        media=new HelmetMediaService(cloud,store,new HelmetMediaProperties(),gatewayProvider);ReflectionTestUtils.setField(media,"healthy",true);
        ObjectProvider<HelmetMediaService> mediaProvider=mock(ObjectProvider.class);when(mediaProvider.getObject()).thenReturn(media);
        sync=new HelmetLocalRecordingSync(store,gatewayProvider,mediaProvider);
        ReflectionTestUtils.setField(sync,"ledger",mock(com.ruoyi.guardian.AdminLedgerStore.class));
        ObjectProvider<GuardianIngest> ingestProvider=mock(ObjectProvider.class);when(ingestProvider.getObject()).thenReturn(ingest);ReflectionTestUtils.setField(sync,"ingest",ingestProvider);
        when(ingest.captureDirect("helmet-a")).thenAnswer(i->context(Instant.now()));
    }
    JSONObject context(Instant at){return obj("device",obj("source","DIRECT_HELMET"),"siteId","site-a","areaId","area-a","personId","person-a","personName","设备领用人", "bindingId","issue-a","bindingStart",start.minusSeconds(3600).toString(),"bindingEnd",null,"receivedAt",at.toString());}
    void session(){sync.observe("on-1","helmet-a","0",context(start));sync.observe("off-1","helmet-a","1",context(stop));}
    JSONObject task(){return (JSONObject)store.snapshot().getJSONObject("autoSyncTasks").values().iterator().next();}
    void list(JSONArray files){String id=task().getString("queryCommandId");media.receipt("helmet-a",obj("act","push_to_client","talkback_id",id,"res",obj("status",true,"data",files)),Instant.now().toString());}
    JSONArray currentFile(){return JSONArray.of(obj("file_name",fileName,"file_md5",md5));}
    JSONObject readyAsset(){return obj("assetId","ready-video","deviceId","helmet-a","kind","video","status","ready","originalName",fileName,"progressId",md5,"createdAt",Instant.now().plusSeconds(1).toString());}

    @Test void completeNewSessionQueriesOnlyItsWindowAndCompletesOnlyAfterActualReadyFile() throws Exception {
        session();assertEquals("queued",task().getString("status"));verifyNoInteractions(gateway,cloud);
        sync.reconcile();String query=task().getString("queryCommandId");assertEquals("querying",task().getString("status"));
        verify(gateway).sendCommand(eq("helmet-a"),argThat(w->"server_push_get_local_video_list".equals(w.getString("cmd"))&&"1".equals(w.getString("video_type"))&&query.equals(w.getString("talkback_id"))));
        JSONArray files=currentFile();files.add(obj("file_name","20260101000000.mp4","file_md5","old-file-md5"));list(files);sync.reconcile();
        String upload=task().getString("uploadCommandId");assertEquals(1,task().getIntValue("fileCount"));
        verify(gateway).sendCommand(eq("helmet-a"),argThat(w->"server_push_upload_video".equals(w.getString("cmd"))&&w.getJSONArray("file_list").equals(JSONArray.of(fileName))));
        JSONObject command=store.snapshot().getJSONObject("commands").getJSONObject(upload);assertNull(command.get("actorId"));assertEquals("DEVICE_LOCAL_RECORDING",command.getString("source"));
        media.receipt("helmet-a",obj("act","push_to_client","talkback_id",upload,"res",obj("status",true)),Instant.now().toString());
        sync.reconcile();assertEquals("uploading",task().getString("status"));assertEquals(0,task().getIntValue("receivedCount"));
        when(cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(readyAsset())));
        sync.reconcile();assertEquals("completed",task().getString("status"));assertEquals(JSONArray.of("ready-video"),task().getJSONArray("assetIds"));
        sync.reconcile();verify(gateway,times(2)).sendCommand(eq("helmet-a"),any());
        JSONObject file=media.assets("helmet-a").getJSONObject(0);assertNull(file.get("personId"));assertEquals("person-a",file.getString("receivedPersonId"));
    }
    @Test void duplicateReportsAndRestartDoNotResendAnAmbiguousUpload() throws Exception {
        session();sync.observe("same-off","helmet-a","1",context(stop.plusSeconds(20)));sync.observe("late-on","helmet-a","0",context(start));
        assertEquals(1,store.snapshot().getJSONObject("autoSyncTasks").size());sync.reconcile();list(currentFile());
        doThrow(new java.io.IOException("uncertain transport")).when(gateway).sendCommand(eq("helmet-a"),argThat(w->"server_push_upload_video".equals(w.getString("cmd"))));
        sync.reconcile();String upload=task().getString("uploadCommandId");assertEquals("unknown",store.snapshot().getJSONObject("commands").getJSONObject(upload).getString("status"));
        HelmetLocalRecordingSync restarted=new HelmetLocalRecordingSync(store,provider(gateway),provider(media));ReflectionTestUtils.setField(restarted,"ingest",provider(ingest));
        ReflectionTestUtils.setField(restarted,"ledger",mock(com.ruoyi.guardian.AdminLedgerStore.class));
        restarted.reconcile();restarted.reconcile();verify(gateway,times(1)).sendCommand(eq("helmet-a"),argThat(w->"server_push_upload_video".equals(w.getString("cmd"))));
        when(cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(readyAsset())));restarted.reconcile();assertEquals("completed",task().getString("status"));
    }
    @Test void sameTimestampReportsRemainOrderedAndReplaysCannotReopenOrStopAnotherSession() {
        sync.observe("on-1","helmet-a","0",context(start));
        sync.observe("off-1","helmet-a","1",context(start));
        assertEquals("queued",task().getString("status"));
        sync.observe("on-1","helmet-a","0",context(start));
        assertEquals("queued",task().getString("status"));
        sync.observe("on-2","helmet-a","0",context(start));
        sync.observe("off-1","helmet-a","1",context(start));
        JSONObject tasks=store.snapshot().getJSONObject("autoSyncTasks");
        assertEquals(2,tasks.size());
        assertEquals(1,tasks.values().stream().filter(v->"recording".equals(((JSONObject)v).getString("status"))).count());
        sync.observe("off-2","helmet-a","1",context(start));
        HelmetLocalRecordingSync restarted=new HelmetLocalRecordingSync(store,provider(gateway),provider(media));
        restarted.observe("on-2","helmet-a","0",context(start));
        tasks=store.snapshot().getJSONObject("autoSyncTasks");
        assertEquals(2,tasks.size());
        assertTrue(tasks.values().stream().allMatch(v->"queued".equals(((JSONObject)v).getString("status"))));
        verifyNoInteractions(gateway,cloud);
    }
    @Test void noStartUnassignedOrChangedScopeNeverSendsAnUpload() {
        sync.observe("off-alone","helmet-a","1",context(stop));assertTrue(store.snapshot().getJSONObject("autoSyncTasks").isEmpty());
        JSONObject unassigned=context(stop.plusSeconds(1));unassigned.put("bindingEnd",stop.toString());sync.observe("unassigned","helmet-a","0",unassigned);assertTrue(store.snapshot().getJSONObject("autoSyncTasks").isEmpty());
        sync.observe("new-on","helmet-a","0",context(stop.plusSeconds(2)));JSONObject changed=context(stop.plusSeconds(3));changed.put("personId","other");sync.observe("changed-off","helmet-a","1",changed);
        assertEquals("failed",task().getString("status"));sync.reconcile();verifyNoInteractions(gateway,cloud);
    }
    @Test void currentAssignmentIsRecheckedBeforeSendingAndOfflineWorkRemainsQueued() throws Exception {
        session();when(gateway.isOnline("helmet-a")).thenReturn(false);sync.reconcile();assertEquals("waiting_device",task().getString("status"));verify(gateway,never()).sendCommand(anyString(),any());
        when(gateway.isOnline("helmet-a")).thenReturn(true);JSONObject changed=context(Instant.now());changed.put("bindingId","new-issue");when(ingest.captureDirect("helmet-a")).thenReturn(changed);
        sync.reconcile();assertEquals("failed",task().getString("status"));verify(gateway,never()).sendCommand(anyString(),any());
    }
    @Test void unknownNamesAndUnmatchedFilesCannotTurnOldInventoryIntoANewRecording() throws Exception {
        session();sync.reconcile();list(JSONArray.of(obj("file_name","unknown.mp4","file_md5",md5)));sync.reconcile();assertEquals("failed",task().getString("status"));
        verify(gateway,never()).sendCommand(eq("helmet-a"),argThat(w->"server_push_upload_video".equals(w.getString("cmd"))));
    }
    @Test void disabledDeviceCannotStartANewSynchronizationTask(){
        JSONObject disabled=context(start);disabled.getJSONObject("device").put("lifecycle","DISABLED");
        sync.observe("disabled-on","helmet-a","0",disabled);sync.observe("disabled-off","helmet-a","1",context(stop));
        assertTrue(store.snapshot().getJSONObject("autoSyncTasks").isEmpty());sync.reconcile();verifyNoInteractions(gateway,cloud);
    }
    @Test void fileWindowCannotReachBeforeTheCurrentIssueStarted() throws Exception {
        JSONObject on=context(start),off=context(stop);String bound=start.minusSeconds(2).toString();on.put("bindingStart",bound);off.put("bindingStart",bound);
        when(ingest.captureDirect("helmet-a")).thenAnswer(i->{JSONObject c=context(Instant.now());c.put("bindingStart",bound);return c;});
        sync.observe("on-bounded","helmet-a","0",on);sync.observe("off-bounded","helmet-a","1",off);sync.reconcile();
        String beforeIssue=DateTimeFormatter.ofPattern("yyyyMMddHHmmss").withZone(ZoneId.of("Asia/Shanghai")).format(start.minusSeconds(10))+".mp4";
        JSONArray files=currentFile();files.add(obj("file_name",beforeIssue,"file_md5","previous-person-file"));list(files);sync.reconcile();
        assertEquals(1,task().getIntValue("fileCount"));verify(gateway).sendCommand(eq("helmet-a"),argThat(w->"server_push_upload_video".equals(w.getString("cmd"))&&w.getJSONArray("file_list").equals(JSONArray.of(fileName))));
    }
    @Test void assignmentChangeAfterInitialCheckIsRejectedAtTheFinalSendGuard() throws Exception {
        session();JSONObject changed=context(Instant.now());changed.put("bindingId","new-issue");
        when(ingest.captureDirect("helmet-a")).thenReturn(context(Instant.now()),changed);
        sync.reconcile();assertEquals("failed",task().getString("status"));verify(gateway,never()).sendCommand(anyString(),any());
        assertNull(store.snapshot().getJSONObject("commands"));
    }
    @Test void immediateDeviceReplyIsNotOverwrittenWhenSocketSendReturns() throws Exception {
        session();doAnswer(i->{assertTrue(Thread.holdsLock(ReflectionTestUtils.getField(sync,"ledger")));assertFalse(Thread.holdsLock(WearableBusinessStore.transactionLock()));
            JSONObject wire=i.getArgument(1);media.receipt("helmet-a",obj("act","push_to_client","talkback_id",wire.getString("talkback_id"),"res",obj("status",true,"data",currentFile())),Instant.now().toString());return null;})
                .when(gateway).sendCommand(eq("helmet-a"),argThat(w->"server_push_get_local_video_list".equals(w.getString("cmd"))));
        sync.reconcile();JSONObject query=store.snapshot().getJSONObject("commands").getJSONObject(task().getString("queryCommandId"));
        assertEquals("acknowledged",query.getString("status"));assertEquals(currentFile(),query.getJSONArray("result"));
        sync.reconcile();assertEquals("uploading",task().getString("status"));
    }
    @Test void emptyOrOldOnlyListsHaveBoundedRetriesAndNeverUploadHistory() throws Exception {
        session();sync.reconcile();for(int i=0;i<3;i++){list(JSONArray.of(obj("file_name","20260101000000.mp4","file_md5","old-file-md5")));sync.reconcile();}
        assertEquals("failed",task().getString("status"));assertEquals(3,task().getIntValue("queryAttempts"));
        verify(gateway,times(3)).sendCommand(eq("helmet-a"),argThat(w->"server_push_get_local_video_list".equals(w.getString("cmd"))));
        verify(gateway,never()).sendCommand(eq("helmet-a"),argThat(w->"server_push_upload_video".equals(w.getString("cmd"))));
    }
    @SuppressWarnings("unchecked") static <T> ObjectProvider<T> provider(T value){ObjectProvider<T> p=mock(ObjectProvider.class);when(p.getObject()).thenReturn(value);return p;}
}
