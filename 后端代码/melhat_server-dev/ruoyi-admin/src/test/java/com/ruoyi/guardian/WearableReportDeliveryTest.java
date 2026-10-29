package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.DirectHelmetTelemetryService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.guardian.WearableModel.object;

class WearableReportDeliveryTest {
    @Test void pausedReportsPersistWithoutProcessingAndReplayOriginalOwnershipExactlyOnce(){
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));WearableBusinessStore journal=new WearableBusinessStore(jdbc);
        GuardianIngest ingest=mock(GuardianIngest.class);JSONObject owner=object("personId","original-person","station","S1");when(ingest.captureBelt("belt-1")).thenReturn(owner);
        DirectBeltTelemetryService belt=mock(DirectBeltTelemetryService.class);ObjectProvider<DirectBeltTelemetryService> belts=mock(ObjectProvider.class);when(belts.getObject()).thenReturn(belt);
        WearableReportDelivery service=new WearableReportDelivery(journal,ingest,mock(ObjectProvider.class),belts);WearableMaintenance maintenance=mock(WearableMaintenance.class);when(maintenance.paused()).thenReturn(true);ReflectionTestUtils.setField(service,"maintenance",maintenance);
        JSONObject status=object("lastSeenAt","2026-10-26T10:00:00Z","online",true);assertFalse(service.belt("belt-1","{\"act\":\"ca_sip_sos\"}",status,null,"2026-10-26T10:00:00Z",true));
        assertEquals(1,journal.pendingReports(0,100).size());verifyNoInteractions(belt);
        when(ingest.captureBelt("belt-1")).thenReturn(object("personId","new-person"));when(maintenance.paused()).thenReturn(false);service.recover();service.recover();
        verify(belt,times(1)).receiveCaptured(eq("belt-1"),eq(status),isNull(),eq("2026-10-26T10:00:00Z"),eq(true),eq(owner));assertTrue(journal.pendingReports(0,100).isEmpty());
    }
    @Test void equalPayloadsReceivedTwiceRemainTwoReceipts(){JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));WearableBusinessStore journal=new WearableBusinessStore(jdbc);GuardianIngest ingest=mock(GuardianIngest.class);when(ingest.captureBelt("belt-1")).thenReturn(new JSONObject());DirectBeltTelemetryService belt=mock(DirectBeltTelemetryService.class);ObjectProvider<DirectBeltTelemetryService> belts=mock(ObjectProvider.class);when(belts.getObject()).thenReturn(belt);WearableReportDelivery service=new WearableReportDelivery(journal,ingest,mock(ObjectProvider.class),belts);
        service.belt("belt-1","{\"act\":\"ca_report_location\"}",new JSONObject(),null,"2026-10-26T10:00:00Z",false);service.belt("belt-1","{\"act\":\"ca_report_location\"}",new JSONObject(),null,"2026-10-26T10:00:00Z",false);assertEquals(2,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report",Integer.class));assertTrue(journal.pendingReports(0,100).isEmpty());verify(belt,times(2)).receiveCaptured(anyString(),any(),isNull(),anyString(),eq(false),any());}
}
