package com.ruoyi.fuda;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import com.ruoyi.framework.config.WebDataConvertConfigLong;
import com.ruoyi.common.filter.RepeatableFilter;
import java.nio.charset.StandardCharsets;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.fuda.FudaMapping.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

class FudaControllerTest {
    @Test void envelopeAndExplicitErrorsDoNotLeakInternalDetails(){
        FudaQueryService query=mock(FudaQueryService.class);when(query.query(anyString(),any(),any())).thenReturn(object("items",Collections.emptyList()));
        FudaController controller=new FudaController(new FudaAuth(FudaAuthTest.properties(),(app,nonce)->true,FudaAuthTest.CLOCK),query,FudaAuthTest.CLOCK);
        ResponseEntity<JSONObject> result=controller.query(FudaAuthTest.signed("{}",UUID.randomUUID().toString()));
        assertEquals(200,result.getStatusCodeValue());assertEquals(0,result.getBody().getIntValue("code"));assertEquals("2026-10-27T08:00:00.000Z",result.getBody().getString("serverTime"));assertNotNull(UUID.fromString(result.getBody().getString("requestId")));
        when(query.query(anyString(),any(),any())).thenThrow(new IllegalStateException("private database password"));
        result=controller.query(FudaAuthTest.signed("{}",UUID.randomUUID().toString()));assertEquals(503,result.getStatusCodeValue());assertFalse(result.getBody().toJSONString().contains("password"));
    }
    @Test void rejectsMalformedDuplicateAndOversizeBodies(){
        FudaQueryService query=mock(FudaQueryService.class);FudaController c=new FudaController(new FudaAuth(FudaAuthTest.properties(),(app,nonce)->true,FudaAuthTest.CLOCK),query,FudaAuthTest.CLOCK);
        assertEquals(400,c.query(FudaAuthTest.signed("{\"limit\":1,\"limit\":2}",UUID.randomUUID().toString())).getStatusCodeValue());
        assertEquals(400,c.query(FudaAuthTest.signed("{}{}",UUID.randomUUID().toString())).getStatusCodeValue());
        MockHttpServletRequest r=FudaAuthTest.signed("{}",UUID.randomUUID().toString());r.setContent(new byte[65537]);assertEquals(413,c.query(r).getStatusCodeValue());verifyNoInteractions(query);
    }
    @Test void requestQueryAndUnsupportedEncodingAreRejected(){
        FudaController c=new FudaController(new FudaAuth(FudaAuthTest.properties(),(app,nonce)->true,FudaAuthTest.CLOCK),mock(FudaQueryService.class),FudaAuthTest.CLOCK);
        MockHttpServletRequest r=FudaAuthTest.signed("{}",UUID.randomUUID().toString());r.setQueryString("cursor=forged");assertEquals(400,c.query(r).getStatusCodeValue());
        r=FudaAuthTest.signed("{}",UUID.randomUUID().toString());r.addHeader("Content-Encoding","gzip");assertEquals(415,c.query(r).getStatusCodeValue());
    }
    @Test void actualProjectJacksonConverterKeepsNullKeysAndNumericCode()throws Exception {
        FudaQueryService service=mock(FudaQueryService.class);when(service.query(anyString(),any(),any())).thenReturn(object("items",Collections.singletonList(object("deviceModel",null,"position",null,"validity","UNKNOWN"))));
        FudaController controller=new FudaController(new FudaAuth(FudaAuthTest.properties(),(app,nonce)->true,FudaAuthTest.CLOCK),service,FudaAuthTest.CLOCK);
        MockMvc mvc=MockMvcBuilders.standaloneSetup(controller).setMessageConverters(new WebDataConvertConfigLong().jackson2HttpMessageConverter()).build();
        MockHttpServletRequest r=FudaAuthTest.signed("{}",UUID.randomUUID().toString());MockHttpServletRequestBuilder input=post(r.getRequestURI()).contentType("application/json").content("{}");
        for(String header:Arrays.asList("X-App-Id","X-Timestamp","X-Nonce","X-Signature"))input.header(header,r.getHeader(header));
        String result=mvc.perform(input).andReturn().getResponse().getContentAsString();
        assertTrue(result.contains("\"position\":null"));assertTrue(result.contains("\"deviceModel\":null"));assertTrue(result.contains("\"code\":0"));assertFalse(result.contains("\"code\":\"0\""));
    }
    @Test void realRepeatableFilterPreservesFormattedLfAndCrLfSignaturesAndRejectsTampering()throws Exception {
        FudaQueryService service=mock(FudaQueryService.class);when(service.query(anyString(),any(),any())).thenReturn(object("items",Collections.emptyList()));
        FudaController controller=new FudaController(new FudaAuth(FudaAuthTest.properties(),(app,nonce)->true,FudaAuthTest.CLOCK),service,FudaAuthTest.CLOCK);
        MockMvc mvc=MockMvcBuilders.standaloneSetup(controller).addFilters(new RepeatableFilter())
                .setMessageConverters(new WebDataConvertConfigLong().jackson2HttpMessageConverter()).build();
        for(String newline:Arrays.asList("\n","\r\n")) {
            String body="{"+newline+"  \"devices\": ["+newline+"    {\"deviceType\": \"HELMET\", \"deviceId\": \"DEMO-HELMET-01\"}"+newline+"  ]"+newline+"}"+newline;
            MockHttpServletRequest signed=FudaAuthTest.signed(body,UUID.randomUUID().toString());
            MockHttpServletRequestBuilder original=post(signed.getRequestURI()).contentType("application/json;charset=UTF-8").content(body.getBytes(StandardCharsets.UTF_8));
            for(String name:Arrays.asList("X-App-Id","X-Timestamp","X-Nonce","X-Signature"))original.header(name,signed.getHeader(name));
            assertEquals(200,mvc.perform(original).andReturn().getResponse().getStatus());
            MockHttpServletRequestBuilder changed=post(signed.getRequestURI()).contentType("application/json;charset=UTF-8").content(body.replace("DEMO-HELMET-01","DEMO-HELMET-02").getBytes(StandardCharsets.UTF_8));
            for(String name:Arrays.asList("X-App-Id","X-Timestamp","X-Nonce","X-Signature"))changed.header(name,signed.getHeader(name));
            org.springframework.mock.web.MockHttpServletResponse denied=mvc.perform(changed).andReturn().getResponse();
            assertEquals(401,denied.getStatus());assertEquals(40101,JSONObject.parseObject(denied.getContentAsString()).getIntValue("code"));
        }
        verify(service,times(2)).query(anyString(),any(),any());
    }
}
