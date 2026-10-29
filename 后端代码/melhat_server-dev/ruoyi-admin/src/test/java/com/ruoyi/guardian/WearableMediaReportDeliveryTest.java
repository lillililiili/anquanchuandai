package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.HelmetMediaService;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.guardian.WearableModel.object;

class WearableMediaReportDeliveryTest {
    final JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
    final WearableBusinessStore journal=new WearableBusinessStore(jdbc);
    final GuardianIngest ingest=mock(GuardianIngest.class);
    final HelmetMediaService media=mock(HelmetMediaService.class);
    final WearableMaintenance maintenance=mock(WearableMaintenance.class);
    WearableReportDelivery delivery(){
        ObjectProvider<HelmetMediaService> provider=mock(ObjectProvider.class);when(provider.getObject()).thenReturn(media);
        WearableReportDelivery service=new WearableReportDelivery(journal,ingest,mock(ObjectProvider.class),mock(ObjectProvider.class));
        ReflectionTestUtils.setField(service,"maintenance",maintenance);ReflectionTestUtils.setField(service,"media",provider);return service;
    }
    JSONObject raw(String action,String request){return object("act",action,"talkback_id",request,"res",object("status",true,"data",Arrays.asList("original-file.mp4")),"vendorField",object("sequence",7));}
    @Test void allMediaReceiptTypesPersistDuringPauseAndReplayOriginalFieldsInOrderExactlyOnce(){
        WearableReportDelivery service=delivery();when(maintenance.paused()).thenReturn(true);
        List<JSONObject> messages=Arrays.asList(raw("ca_upload_photo","photo"),raw("upload_video_success","video"),raw("push_to_client","files"));
        for(JSONObject message:messages)service.helmetMedia("866652021714127",message.toJSONString());
        List<JSONObject> saved=journal.pendingReports(0,100);assertEquals(3,saved.size());verifyNoInteractions(media,ingest);
        for(int i=0;i<3;i++){assertEquals("direct-helmet-media",saved.get(i).getString("protocol"));assertEquals(messages.get(i),saved.get(i).getJSONObject("payload").getJSONObject("raw"));assertNotNull(saved.get(i).getJSONObject("payload").getString("receivedAt"));}
        when(maintenance.paused()).thenReturn(false);when(media.receipt(anyString(),any(),anyString())).thenReturn(true);
        service.recover();service.recover();InOrder order=inOrder(media);
        for(int i=0;i<messages.size();i++)order.verify(media).receipt("866652021714127",messages.get(i),saved.get(i).getJSONObject("payload").getString("receivedAt"));
        order.verifyNoMoreInteractions();assertTrue(journal.pendingReports(0,100).isEmpty());verifyNoInteractions(ingest);
    }
    @Test void failurePreservesPendingAndPreventsLaterMediaReceiptFromOvertaking(){
        WearableReportDelivery service=delivery();when(maintenance.paused()).thenReturn(true);
        JSONObject first=raw("ca_upload_photo","first"),second=raw("upload_video_success","second");
        service.helmetMedia("hat",first.toJSONString());service.helmetMedia("hat",second.toJSONString());
        when(media.receipt(eq("hat"),eq(first),anyString())).thenThrow(new IllegalStateException("temporary storage failure")).thenReturn(true);when(media.receipt(eq("hat"),eq(second),anyString())).thenReturn(true);
        when(maintenance.paused()).thenReturn(false);service.recover();
        assertEquals(2,journal.pendingReports(0,100).size());verify(media,never()).receipt(eq("hat"),eq(second),anyString());
        service.recover();assertTrue(journal.pendingReports(0,100).isEmpty());
        InOrder order=inOrder(media);order.verify(media,times(2)).receipt(eq("hat"),eq(first),anyString());order.verify(media).receipt(eq("hat"),eq(second),anyString());order.verifyNoMoreInteractions();
    }
    @Test void unmatchedReceiptStaysPendingAndUnknownActionsNeverEnterJournal(){
        WearableReportDelivery service=delivery();when(media.receipt(anyString(),any(),anyString())).thenReturn(false);
        assertDoesNotThrow(()->service.helmetMedia("hat",raw("push_to_client","wrong-command").toJSONString()));
        assertEquals(1,journal.pendingReports(0,100).size());
        assertThrows(IllegalArgumentException.class,()->service.helmetMedia("hat",raw("unknown","x").toJSONString()));
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Integer.class));
    }
}
