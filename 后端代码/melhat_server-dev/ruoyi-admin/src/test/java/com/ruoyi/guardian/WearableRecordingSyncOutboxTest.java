package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.*;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WearableRecordingSyncOutboxTest {
    @Test void onlyNewReportsProduceAnAtomicOrderedOutboxAndFailedStartCannotLoseItsStop(){
        WearableBusinessStore journal=new WearableBusinessStore(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","")),Base64.getEncoder().encodeToString(new byte[32]));
        HelmetMediaStore mediaStore=new HelmetMediaStore("missing-"+UUID.randomUUID()+".json","public-"+UUID.randomUUID(),journal);
        GuardianIngest ingest=mock(GuardianIngest.class);DirectHelmetTelemetryService telemetry=mock(DirectHelmetTelemetryService.class);
        when(telemetry.registered("hat")).thenReturn(new SafetyHatInfo());
        JSONObject context=object("device",object("source","DIRECT_HELMET"),"siteId","site-a","personId","person-a","personName","原领用人","bindingId","issue-a","bindingStart",Instant.now().minusSeconds(3600).toString());
        when(ingest.captureDirect("hat")).thenAnswer(i->JSONObject.parseObject(context.toJSONString()));
        HelmetLocalRecordingSync sync=spy(new HelmetLocalRecordingSync(mediaStore,mock(ObjectProvider.class),mock(ObjectProvider.class)));
        WearableReportDelivery delivery=new WearableReportDelivery(journal,ingest,provider(telemetry),mock(ObjectProvider.class));ReflectionTestUtils.setField(delivery,"localRecordingSync",sync);
        // These durable reports existed before this version and must not generate synchronization work.
        JSONObject legacyContext=JSONObject.parseObject(context.toJSONString());legacyContext.put("receivedAt",Instant.now().minusSeconds(50).toString());
        journal.appendDeviceReport("old-on","direct-helmet","hat",object("raw",object("act","toggle_localrecord","type","0"),"context",legacyContext));
        delivery.recover();assertNull(mediaStore.snapshot().getJSONObject("autoSyncTasks"));
        assertFalse(delivery.helmet("hat","{\"act\":\"toggle_localrecord\",\"type\":\"0\"}"));
        assertFalse(delivery.helmet("hat","{\"act\":\"toggle_localrecord\",\"type\":\"1\"}"));
        assertEquals(2,journal.pendingReports(0,100).size());verify(sync,never()).observe(anyString(),anyString(),anyString(),any());
        doAnswer(i->{i.callRealMethod();throw new IllegalStateException("transaction failure after outbox write");}).when(sync).observe(anyString(),eq("hat"),eq("0"),any());
        delivery.recover();assertEquals(2,journal.pendingReports(0,100).size());assertNull(mediaStore.snapshot().getJSONObject("autoSyncTasks"));
        verify(sync,never()).observe(anyString(),eq("hat"),eq("1"),any());
        doCallRealMethod().when(sync).observe(anyString(),eq("hat"),eq("0"),any());
        context.put("personId","new-owner");delivery.recover();delivery.recover();
        assertTrue(journal.pendingReports(0,100).isEmpty());JSONObject tasks=mediaStore.snapshot().getJSONObject("autoSyncTasks");assertEquals(1,tasks.size());
        JSONObject task=(JSONObject)tasks.values().iterator().next();assertEquals("queued",task.getString("status"));assertEquals("person-a",task.getString("receivedPersonId"));
        verify(ingest,times(2)).captureDirect("hat");
    }
    @SuppressWarnings("unchecked") static <T> ObjectProvider<T> provider(T value){ObjectProvider<T> p=mock(ObjectProvider.class);when(p.getObject()).thenReturn(value);return p;}
}
