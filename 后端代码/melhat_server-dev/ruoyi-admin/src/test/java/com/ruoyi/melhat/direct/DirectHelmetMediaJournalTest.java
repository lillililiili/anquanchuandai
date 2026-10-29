package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.WearableReportDelivery;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import javax.websocket.Session;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectHelmetMediaJournalTest {
    @Test void authenticatedReceiptUsesJournalAndNeverPublishesAnOnlineProjection(){
        String id="866652021714127";DirectHelmetProperties config=new DirectHelmetProperties();config.setEnabled(true);
        DirectHelmetTelemetryService telemetry=mock(DirectHelmetTelemetryService.class);SafetyHatInfo hat=new SafetyHatInfo();hat.setHatNumber(id);when(telemetry.registered(id)).thenReturn(hat);
        Session session=mock(Session.class);when(session.isOpen()).thenReturn(true);DirectHelmetSessions sessions=new DirectHelmetSessions();sessions.register(id,session);
        DirectHelmetGateway gateway=new DirectHelmetGateway(config,telemetry,sessions);WearableReportDelivery reports=mock(WearableReportDelivery.class);ReflectionTestUtils.setField(gateway,"reports",reports);
        HelmetMediaService media=mock(HelmetMediaService.class);ObjectProvider<HelmetMediaService> provider=mock(ObjectProvider.class);when(provider.getIfAvailable()).thenReturn(media);ReflectionTestUtils.setField(gateway,"mediaProvider",provider);
        String raw="{\"act\":\"ca_upload_photo\",\"talkback_id\":\"HC-real\",\"res\":{\"status\":true},\"vendorField\":17}";
        JSONObject response=gateway.receive(session,raw);assertTrue(response.getBooleanValue("status"));verify(reports).helmetMedia(id,raw);verify(media,never()).receipt(anyString(),any());verify(telemetry,never()).snapshot(anyString(),any());verify(telemetry,never()).connection(any(),anyBoolean());
        Session unknown=mock(Session.class);assertFalse(gateway.receive(unknown,raw).getBooleanValue("status"));verifyNoMoreInteractions(reports);
    }
    @Test void journalFailureCannotAcknowledgeReceiptAsSaved(){
        String id="866652021714127";DirectHelmetProperties config=new DirectHelmetProperties();config.setEnabled(true);DirectHelmetTelemetryService telemetry=mock(DirectHelmetTelemetryService.class);when(telemetry.registered(id)).thenReturn(new SafetyHatInfo());
        Session session=mock(Session.class);DirectHelmetSessions sessions=new DirectHelmetSessions();sessions.register(id,session);DirectHelmetGateway gateway=new DirectHelmetGateway(config,telemetry,sessions);WearableReportDelivery reports=mock(WearableReportDelivery.class);ReflectionTestUtils.setField(gateway,"reports",reports);doThrow(new IllegalStateException("database unavailable")).when(reports).helmetMedia(anyString(),anyString());
        assertFalse(gateway.receive(session,"{\"act\":\"upload_video_success\",\"talkback_id\":\"HC-real\"}").getBooleanValue("status"));verify(telemetry,never()).snapshot(anyString(),any());
    }
}
