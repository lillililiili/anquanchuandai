package com.ruoyi.guardian;

import com.ruoyi.melhat.split.*;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static com.ruoyi.guardian.WearableModel.object;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class SplitHelmetHttpErrorsTest {
    @Test void deniedHeartbeatAndExpiredSdpUseFailureHttpStatusInsteadOfSuccessEnvelope()throws Exception {
        PersonEquipmentContext equipment=mock(PersonEquipmentContext.class);
        SplitHelmetSessionController controller=new SplitHelmetSessionController(mock(SplitHelmetService.class),equipment,mock(GuardianAccess.class));
        MockMvc http=MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(new GuardianError()).build();
        doThrow(new AdminQueryService.QueryFailed(403,"PERMISSION_DENIED","已撤权")).when(equipment).execute(any(),any());
        http.perform(post("/api/guardian/v1/split/sessions/SPLIT-test/heartbeat").requestAttr("wearable.actor",object("id","actor")))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.errorCode").value("PERMISSION_DENIED"));
        doThrow(new AdminQueryService.QueryFailed(409,"CALL_EXPIRED","已过期")).when(equipment).execute(any(),any());
        http.perform(post("/api/guardian/v1/split/sessions/SPLIT-test/devices/SN1/play").requestAttr("wearable.actor",object("id","actor")).contentType("application/sdp").content("v=0\r\n"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.errorCode").value("CALL_EXPIRED"));
        // The real session interceptor rejects missing login before this controller.
        // Standalone MockMvc verifies the same failure status emitted by the advice.
        doThrow(new GuardianUnauthorized("登录已失效")).when(equipment).execute(isNull(),any());
        http.perform(post("/api/guardian/v1/split/sessions/SPLIT-test/heartbeat"))
                .andExpect(status().isUnauthorized());
    }
}
