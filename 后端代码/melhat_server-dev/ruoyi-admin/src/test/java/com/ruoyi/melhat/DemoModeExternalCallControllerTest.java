package com.ruoyi.melhat;

import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.IntercomRecord;
import com.ruoyi.helmet.pojo.po.IntercomRecordRequest;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.pojo.po.TtsRequest;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;
import com.ruoyi.helmet.service.IIntercomRecordService;
import com.ruoyi.helmet.service.ISafetyHatInfoService;
import com.ruoyi.helmet.service.ITtsTextSynthesisBroadcastService;
import com.ruoyi.melhat.controller.IntercomRecordController;
import com.ruoyi.melhat.controller.TtsTextSynthesisBroadcastController;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 演示模式必须只写本地记录，不能触发 RTC 或 TTS 外部服务。
 */
class DemoModeExternalCallControllerTest {

    @Test
    void demoIntercomSingleGroupAndTeamSaveOneLocalRecordWithoutRtcCall() throws Exception {
        IIntercomRecordService records = mock(IIntercomRecordService.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        when(hats.list(any())).thenReturn(hats());
        doAnswer(invocation -> {
            ((IntercomRecord) invocation.getArgument(0)).setId(101L);
            return true;
        }).when(records).save(any(IntercomRecord.class));
        IntercomRecordController controller = new IntercomRecordController();
        ReflectionTestUtils.setField(controller, "intercomRecordService", records);
        ReflectionTestUtils.setField(controller, "hatInfoService", hats);
        ReflectionTestUtils.setField(controller, "demoMode", true);

        assertDemoIntercom(controller.createSingleCall(intercom("MH-DEMO-001", "演示人员甲", null)), "01", "single", 1, "MH-DEMO-001", "演示人员甲");
        verify(records, times(1)).save(any(IntercomRecord.class));
        verify(records, never()).createIntercom(any(IntercomRecord.class), any(IntercomRecordRequest.class));

        org.mockito.Mockito.reset(records);
        doAnswer(invocation -> {
            ((IntercomRecord) invocation.getArgument(0)).setId(102L);
            return true;
        }).when(records).save(any(IntercomRecord.class));
        assertDemoIntercom(controller.createGroupCall(intercom("MH-DEMO-001,MH-DEMO-002", "演示人员甲,演示人员乙", null)), "02", "group", 2, "MH-DEMO-001,MH-DEMO-002", "演示人员甲,演示人员乙");
        verify(records, times(1)).save(any(IntercomRecord.class));
        verify(records, never()).createIntercom(any(IntercomRecord.class), any(IntercomRecordRequest.class));

        org.mockito.Mockito.reset(records);
        doAnswer(invocation -> {
            ((IntercomRecord) invocation.getArgument(0)).setId(103L);
            return true;
        }).when(records).save(any(IntercomRecord.class));
        assertDemoIntercom(controller.createTeamCall(intercom(null, null, "9")), "03", "team", 2, "MH-DEMO-001,MH-DEMO-002", "演示人员甲,演示人员乙");
        verify(records, times(1)).save(any(IntercomRecord.class));
        verify(records, never()).createIntercom(any(IntercomRecord.class), any(IntercomRecordRequest.class));
    }

    @Test
    void demoTtsSingleGroupAndTeamSaveOneLocalRecordWithoutTtsCall() throws Exception {
        ITtsTextSynthesisBroadcastService records = mock(ITtsTextSynthesisBroadcastService.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        when(hats.list(any())).thenReturn(hats());
        doAnswer(invocation -> {
            ((TtsTextSynthesisBroadcast) invocation.getArgument(0)).setId(201L);
            return true;
        }).when(records).save(any(TtsTextSynthesisBroadcast.class));
        TtsTextSynthesisBroadcastController controller = new TtsTextSynthesisBroadcastController();
        ReflectionTestUtils.setField(controller, "broadcastRecordService", records);
        ReflectionTestUtils.setField(controller, "hatInfoService", hats);
        ReflectionTestUtils.setField(controller, "demoMode", true);

        assertDemoTts(controller.createSingleBroadcast(tts("MH-DEMO-001", "演示人员甲", null)), "01", "single", 1, "MH-DEMO-001", "演示人员甲");
        verify(records, times(1)).save(any(TtsTextSynthesisBroadcast.class));
        verify(records, never()).createSingleBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));

        org.mockito.Mockito.reset(records);
        doAnswer(invocation -> {
            ((TtsTextSynthesisBroadcast) invocation.getArgument(0)).setId(202L);
            return true;
        }).when(records).save(any(TtsTextSynthesisBroadcast.class));
        assertDemoTts(controller.createGroupBroadcast(tts("MH-DEMO-001,MH-DEMO-002", "演示人员甲,演示人员乙", null)), "02", "group", 2, "MH-DEMO-001,MH-DEMO-002", "演示人员甲,演示人员乙");
        verify(records, times(1)).save(any(TtsTextSynthesisBroadcast.class));
        verify(records, never()).createBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));

        org.mockito.Mockito.reset(records);
        doAnswer(invocation -> {
            ((TtsTextSynthesisBroadcast) invocation.getArgument(0)).setId(203L);
            return true;
        }).when(records).save(any(TtsTextSynthesisBroadcast.class));
        assertDemoTts(controller.createTeamBroadcast(tts(null, null, "9")), "03", "team", 2, "MH-DEMO-001,MH-DEMO-002", "演示人员甲,演示人员乙");
        verify(records, times(1)).save(any(TtsTextSynthesisBroadcast.class));
        verify(records, never()).createBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));
    }

    private void assertDemoIntercom(R<Object> response, String type, String mode, int count, String number, String participant) {
        assertEquals(200, response.getCode());
        assertTrue(response.getMsg().contains("本地模拟"));
        Map<String, Object> data = (Map<String, Object>) response.getData();
        assertEquals(true, data.get("demo"));
        assertEquals(mode, data.get("mode"));
        assertEquals(type, data.get("intercomType"));
        assertEquals(count, data.get("recipientCount"));
        assertEquals(number, data.get("hatNumber"));
        assertEquals(participant, data.get("participant"));
        assertEquals("demo", data.get("createBy"));
    }

    private void assertDemoTts(R response, String type, String mode, int count, String number, String recipient) {
        assertEquals(200, response.getCode());
        assertTrue(response.getMsg().contains("本地模拟"));
        Map<String, Object> data = (Map<String, Object>) response.getData();
        assertEquals(true, data.get("demo"));
        assertEquals(mode, data.get("mode"));
        assertEquals(type, data.get("broadcastType"));
        assertEquals(count, data.get("recipientCount"));
        assertEquals(number, data.get("hatNumber"));
        assertEquals(recipient, data.get("recipient"));
        assertEquals("demo", data.get("createBy"));
    }

    private IntercomRecordRequest intercom(String number, String participant, String groupId) {
        IntercomRecordRequest request = new IntercomRecordRequest();
        request.setHatNumber(number);
        request.setParticipant(participant);
        request.setGroupId(groupId);
        return request;
    }

    private TtsRequest tts(String number, String participant, String groupId) {
        TtsRequest request = new TtsRequest();
        request.setHatNumber(number);
        request.setParticipant(participant);
        request.setGroupId(groupId);
        request.setContent("本地模拟广播");
        return request;
    }

    private List<SafetyHatInfo> hats() {
        SafetyHatInfo first = new SafetyHatInfo();
        first.setHatNumber("MH-DEMO-001");
        first.setBindUserName("演示人员甲");
        SafetyHatInfo second = new SafetyHatInfo();
        second.setHatNumber("MH-DEMO-002");
        second.setBindUserName("演示人员乙");
        return Arrays.asList(first, second);
    }
}
