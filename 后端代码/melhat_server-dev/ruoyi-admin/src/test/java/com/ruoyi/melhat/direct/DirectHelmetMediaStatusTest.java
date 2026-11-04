package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import javax.websocket.Session;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DirectHelmetMediaStatusTest {
    @Test @SuppressWarnings("unchecked") void cameraActionsFollowMediaAvailabilityWithoutRequiringVoiceRegistration(){
        DirectHelmetProperties config=new DirectHelmetProperties();config.setEnabled(true);
        DirectHelmetTelemetryService telemetry=mock(DirectHelmetTelemetryService.class);
        DirectHelmetGateway gateway=new DirectHelmetGateway(config,telemetry,new DirectHelmetSessions());
        HelmetMediaService media=mock(HelmetMediaService.class);ObjectProvider<HelmetMediaService> provider=mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(media);ReflectionTestUtils.setField(gateway,"mediaProvider",provider);
        JSONObject mediaState=HelmetMediaService.obj("mediaAvailable",true,"voiceAvailable",false,"broadcastAvailable",false,"mediaStatus","ready");
        when(media.capabilities("helmet-test")).thenAnswer(invocation->mediaState);
        String[] cameraActions={"video","take_photo","start_video","stop_video","list_recordings","upload_recording","start_recording","stop_recording"};
        for(int read=0;read<2;read++){
            com.alibaba.fastjson2.JSONArray actions=gateway.status("helmet-test").getJSONArray("capabilities");
            for(String action:cameraActions)assertEquals(1,java.util.Collections.frequency(actions,action),action);
            assertFalse(actions.contains("intercom"));assertFalse(actions.contains("tts"));
        }
        mediaState.put("mediaAvailable",false);mediaState.put("mediaStatus","unavailable");
        com.alibaba.fastjson2.JSONArray unavailable=gateway.status("helmet-test").getJSONArray("capabilities");
        for(String action:cameraActions)assertFalse(unavailable.contains(action),action);
        assertTrue(unavailable.contains("battery"));assertTrue(unavailable.contains("location"));
        mediaState.put("mediaAvailable",true);mediaState.put("voiceAvailable",true);mediaState.put("broadcastAvailable",true);mediaState.put("mediaStatus","ready");
        com.alibaba.fastjson2.JSONArray recovered=gateway.status("helmet-test").getJSONArray("capabilities");
        assertTrue(recovered.contains("list_recordings"));assertTrue(recovered.contains("upload_recording"));
        assertTrue(recovered.contains("intercom"));assertTrue(recovered.contains("tts"));
    }

    @Test @SuppressWarnings("unchecked") void readyMediaRemovesStaleUnavailableReasonAndSosDoesNotClaimAConnectedCall(){
        DirectHelmetProperties config=new DirectHelmetProperties();config.setEnabled(true);
        DirectHelmetTelemetryService telemetry=mock(DirectHelmetTelemetryService.class);
        when(telemetry.registered("helmet-test")).thenReturn(new SafetyHatInfo());
        DirectHelmetGateway gateway=new DirectHelmetGateway(config,telemetry,new DirectHelmetSessions());
        HelmetMediaService media=mock(HelmetMediaService.class);ObjectProvider<HelmetMediaService> provider=mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(media);ReflectionTestUtils.setField(gateway,"mediaProvider",provider);
        when(media.capabilities("helmet-test")).thenReturn(HelmetMediaService.obj("mediaAvailable",true,"voiceAvailable",true,"mediaStatus","ready"));
        Session session=mock(Session.class);when(session.isOpen()).thenReturn(true);
        assertTrue(gateway.receive(session,"{\"act\":\"ca_login\",\"device_id\":\"helmet-test\"}").getBooleanValue("status"));
        assertFalse(gateway.status("helmet-test").containsKey("mediaUnavailableReason"));
        JSONObject result=gateway.receive(session,"{\"act\":\"ca_sip_sos\",\"device_id\":\"helmet-test\"}");
        assertEquals("ready",result.getString("media_status"));assertFalse(result.getString("msg").contains("未配置"));assertTrue(result.getString("msg").contains("不代表通话已接通"));
        verify(media,never()).receipt(anyString(),any());
    }
}
