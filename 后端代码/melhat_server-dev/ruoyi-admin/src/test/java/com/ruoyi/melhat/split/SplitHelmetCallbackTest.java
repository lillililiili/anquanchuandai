package com.ruoyi.melhat.split;
import org.junit.jupiter.api.*;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static com.ruoyi.melhat.split.SplitTelemetry.obj;

class SplitHelmetCallbackTest {
    SplitHelmetProperties p;SplitHelmetService service;MockMvc http;
    final String secret="01234567890123456789012345678901";
    @BeforeEach void setup(){p=new SplitHelmetProperties();p.setEnabled(true);p.setCallbackSecret(secret);service=mock(SplitHelmetService.class);http=MockMvcBuilders.standaloneSetup(new SplitHelmetCallbackController(p,service)).build();}
    @Test void disabledAndUnauthenticatedCallbacksNeverReachService()throws Exception {
        http.perform(post("/api/helmet/notify/sos").contentType("application/json").content("{}")).andExpect(status().isUnauthorized());
        p.setEnabled(false);http.perform(post("/api/helmet/notify/sos").header("X-Helmet-Callback-Secret",secret).contentType("application/json").content("{}")).andExpect(status().isServiceUnavailable());verifyNoInteractions(service);
    }
    @Test void duplicateKeysAndTrailingDocumentsAreRejected()throws Exception {
        for(String body:new String[]{"{\"helmetSn\":\"SN1\",\"helmetSn\":\"SN2\"}","{}{}","[]"})http.perform(post("/api/helmet/notify/sos").header("X-Helmet-Callback-Secret",secret).contentType("application/json").content(body)).andExpect(status().isBadRequest());verifyNoInteractions(service);
    }
    @Test void sixExplicitRoutesPassStableIngressHeadersAndUnknownRoutesStayClosed()throws Exception {
        when(service.receive(anyString(),any(),anyString(),anyString())).thenReturn(obj("code",200));
        for(String kind:new String[]{"gnss","baro","deviceStatus","sosCall","sosCallEnd","sos"})http.perform(post("/api/helmet/notify/"+kind).header("X-Helmet-Callback-Secret",secret).header("X-Split-Ingress-Id","stable-id").header("X-Split-Received-At","2026-11-16T00:00:00Z").contentType("application/json").content("{\"helmetSn\":\"SN1\"}")).andExpect(status().isOk());
        verify(service,times(6)).receive(anyString(),eq(obj("helmetSn","SN1")),eq("stable-id"),eq("2026-11-16T00:00:00Z"));http.perform(post("/api/helmet/notify/unknown").contentType("application/json").content("{}")).andExpect(status().isNotFound());
    }
}
