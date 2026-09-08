package com.ruoyi.melhat;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.headband.pojo.vo.ResponseVO;
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
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** 演示模式的本地数据边界：绝不信任调用方提供的人员或非演示帽号。 */
class DemoModeExternalCallControllerBoundaryTest {

    @BeforeEach
    void asAdmin() {
        SysUser user = new SysUser();
        user.setUserName("admin");
        LoginUser loginUser = new LoginUser(user, java.util.Collections.emptySet());
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(loginUser, null));
    }

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void demoBroadcastDerivesRecipientsFromConstrainedHatsAndTrimsContent() throws Exception {
        ITtsTextSynthesisBroadcastService records = mock(ITtsTextSynthesisBroadcastService.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        when(hats.list(any(Wrapper.class))).thenReturn(demoHats());
        doAnswer(invocation -> {
            ((TtsTextSynthesisBroadcast) invocation.getArgument(0)).setId(11L);
            return true;
        }).when(records).save(any(TtsTextSynthesisBroadcast.class));
        TtsTextSynthesisBroadcastController controller = ttsController(records, hats, true);

        R response = controller.createGroupBroadcast(tts("MH-DEMO-002,MH-DEMO-001", "MH-DEMO-002,MH-DEMO-001", null, "  本地广播  "));

        Map<String, Object> data = (Map<String, Object>) response.getData();
        assertEquals("MH-DEMO-002,MH-DEMO-001", data.get("hatNumber"));
        assertEquals("演示人员乙,演示人员甲", data.get("recipient"));
        assertEquals(2, data.get("recipientCount"));
        assertEquals("admin", data.get("operator"));
        org.mockito.ArgumentCaptor<TtsTextSynthesisBroadcast> saved = org.mockito.ArgumentCaptor.forClass(TtsTextSynthesisBroadcast.class);
        verify(records).save(saved.capture());
        assertEquals("本地广播", saved.getValue().getContent());
        verify(hats).list(any(Wrapper.class));
        verify(records, never()).createBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));
    }

    @Test
    void demoRejectsInvalidCsvMissingOrNonDemoHatsBlankContentEmptyTeamAndSaveFailureWithoutExternalCalls() throws Exception {
        IIntercomRecordService intercomRecords = mock(IIntercomRecordService.class);
        ITtsTextSynthesisBroadcastService broadcastRecords = mock(ITtsTextSynthesisBroadcastService.class);
        ISafetyHatInfoService hats = mock(ISafetyHatInfoService.class);
        IntercomRecordController intercom = intercomController(intercomRecords, hats, true);
        TtsTextSynthesisBroadcastController tts = ttsController(broadcastRecords, hats, true);

        assertThrows(ServiceException.class, () -> intercom.createSingleCall(intercom(",,", "伪造人员", null)));
        assertThrows(ServiceException.class, () -> tts.createSingleBroadcast(tts("MH-DEMO-001", "伪造人员", null, "   ")));

        when(hats.list(any(Wrapper.class))).thenReturn(Arrays.asList(demoHat("MH-DEMO-001", "演示人员甲", 9L)));
        assertThrows(ServiceException.class, () -> intercom.createGroupCall(intercom("MH-DEMO-001,MH-EXTERNAL-001", "任意", null)));

        when(hats.list(any(Wrapper.class))).thenReturn(java.util.Collections.emptyList());
        assertThrows(ServiceException.class, () -> tts.createTeamBroadcast(tts(null, null, "9", "组播")));

        when(hats.list(any(Wrapper.class))).thenReturn(demoHats());
        when(broadcastRecords.save(any(TtsTextSynthesisBroadcast.class))).thenReturn(false);
        assertThrows(ServiceException.class, () -> tts.createSingleBroadcast(tts("MH-DEMO-001", "任意", null, "保存失败")));

        verify(intercomRecords, never()).save(any(IntercomRecord.class));
        verify(intercomRecords, never()).createIntercom(any(IntercomRecord.class), any(IntercomRecordRequest.class));
        verify(broadcastRecords, never()).createSingleBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));
        verify(broadcastRecords, never()).createBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));
        verify(hats, times(3)).list(any(Wrapper.class));
    }

    @Test
    void productionModeKeepsOriginalServiceCalls() throws Exception {
        IIntercomRecordService intercomRecords = mock(IIntercomRecordService.class);
        ITtsTextSynthesisBroadcastService broadcastRecords = mock(ITtsTextSynthesisBroadcastService.class);
        ResponseVO response = new ResponseVO(200, "ok", "production-data");
        when(intercomRecords.createIntercom(any(IntercomRecord.class), any(IntercomRecordRequest.class))).thenReturn(response);
        when(broadcastRecords.createSingleBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class))).thenReturn(true);
        IntercomRecordController intercom = intercomController(intercomRecords, mock(ISafetyHatInfoService.class), false);
        TtsTextSynthesisBroadcastController tts = ttsController(broadcastRecords, mock(ISafetyHatInfoService.class), false);

        assertEquals("production-data", intercom.createSingleCall(intercom("MH-EXTERNAL-001", "生产人员", null)).getData());
        assertEquals(200, tts.createSingleBroadcast(tts("MH-EXTERNAL-001", "生产人员", null, "生产广播")).getCode());
        verify(intercomRecords).createIntercom(any(IntercomRecord.class), any(IntercomRecordRequest.class));
        verify(broadcastRecords).createSingleBroadcast(any(TtsTextSynthesisBroadcast.class), any(TtsRequest.class));
        verify(intercomRecords, never()).save(any(IntercomRecord.class));
        verify(broadcastRecords, never()).save(any(TtsTextSynthesisBroadcast.class));
    }

    private IntercomRecordController intercomController(IIntercomRecordService records, ISafetyHatInfoService hats, boolean demoMode) {
        IntercomRecordController controller = new IntercomRecordController();
        ReflectionTestUtils.setField(controller, "intercomRecordService", records);
        ReflectionTestUtils.setField(controller, "hatInfoService", hats);
        ReflectionTestUtils.setField(controller, "demoMode", demoMode);
        return controller;
    }

    private TtsTextSynthesisBroadcastController ttsController(ITtsTextSynthesisBroadcastService records, ISafetyHatInfoService hats, boolean demoMode) {
        TtsTextSynthesisBroadcastController controller = new TtsTextSynthesisBroadcastController();
        ReflectionTestUtils.setField(controller, "broadcastRecordService", records);
        ReflectionTestUtils.setField(controller, "hatInfoService", hats);
        ReflectionTestUtils.setField(controller, "demoMode", demoMode);
        return controller;
    }

    private IntercomRecordRequest intercom(String numbers, String participant, String groupId) {
        IntercomRecordRequest request = new IntercomRecordRequest();
        request.setHatNumber(numbers);
        request.setParticipant(participant);
        request.setGroupId(groupId);
        return request;
    }

    private TtsRequest tts(String numbers, String participant, String groupId, String content) {
        TtsRequest request = new TtsRequest();
        request.setHatNumber(numbers);
        request.setParticipant(participant);
        request.setGroupId(groupId);
        request.setContent(content);
        return request;
    }

    private List<SafetyHatInfo> demoHats() {
        return Arrays.asList(demoHat("MH-DEMO-001", "演示人员甲", 9L), demoHat("MH-DEMO-002", "演示人员乙", 9L));
    }

    private SafetyHatInfo demoHat(String number, String userName, Long groupId) {
        SafetyHatInfo hat = new SafetyHatInfo();
        hat.setHatNumber(number);
        hat.setBindUserName(userName);
        hat.setBindGroupId(groupId);
        hat.setCreateBy("demo");
        hat.setDelFlag("0");
        return hat;
    }
}
