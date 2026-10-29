package com.ruoyi.fuda.gb;
import com.ruoyi.melhat.direct.HelmetMediaService;
import com.ruoyi.melhat.direct.HelmetCloudClient;
import com.ruoyi.guardian.WearableMaintenance;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import java.time.Instant;
import java.nio.charset.StandardCharsets;
import com.ruoyi.common.filter.RepeatableFilter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;
class FudaGbInternalControllerTest {
    private static final String KEY="test-internal-key-00000000000000000000";
    private static final String LEASE="lease-test-00000001";
    private WearableMaintenance activeMaintenance(){
        WearableMaintenance maintenance=mock(WearableMaintenance.class);when(maintenance.tryBeginWrite()).thenReturn(true);return maintenance;
    }
    private MockHttpServletRequest leaseRequest(String method,String lease,String body,String nonce)throws Exception{
        MockHttpServletRequest r=new MockHttpServletRequest(method,"/internal/fuda-gb/v1/leases/"+lease);
        String time=String.valueOf(Instant.now().getEpochSecond());r.addHeader("X-GB-Time",time);r.addHeader("X-GB-Nonce",nonce);
        r.addHeader("X-GB-Signature",HelmetCloudClient.signature(KEY,time,nonce,method,r.getRequestURI(),body.getBytes(StandardCharsets.UTF_8)));return r;
    }
    private MockHttpServletRequest request(String nonce)throws Exception{
        MockHttpServletRequest r=new MockHttpServletRequest("GET","/internal/fuda-gb/v1/devices/helmet-a/status");
        String time=String.valueOf(Instant.now().getEpochSecond());r.addHeader("X-GB-Time",time);r.addHeader("X-GB-Nonce",nonce);
        r.addHeader("X-GB-Signature",HelmetCloudClient.signature(KEY,time,nonce,"GET",r.getRequestURI(),new byte[0]));return r;
    }
    @Test void defaultDisabledAndHumanTokenDoNotAuthorize()throws Exception{
        HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=mock(WearableMaintenance.class);
        FudaGbInternalController c=new FudaGbInternalController(media,false,"","",maintenance);
        assertEquals(401,c.status("helmet-a",request("nonce0000000000001")).getStatusCodeValue());verifyNoInteractions(media,maintenance);
    }
    @Test void scopedHmacIsAcceptedOnceAndReplayIsRejected()throws Exception{
        HelmetMediaService media=mock(HelmetMediaService.class);when(media.gbDeviceStatus("helmet-a")).thenReturn(obj("online",true));
        WearableMaintenance maintenance=mock(WearableMaintenance.class);
        FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);MockHttpServletRequest r=request("nonce0000000000002");
        assertEquals(200,c.status("helmet-a",r).getStatusCodeValue());assertEquals(401,c.status("helmet-a",r).getStatusCodeValue());verify(media,times(1)).gbDeviceStatus("helmet-a");
        verifyNoInteractions(maintenance);
    }
    @Test void actualRepeatableFilterKeepsInternalCrLfBodyForHmac()throws Exception{
        String lease="lease-test-00000001",path="/internal/fuda-gb/v1/leases/"+lease,body="{\r\n  \"deviceId\": \"helmet-a\"\r\n}\r\n";
        HelmetMediaService media=mock(HelmetMediaService.class);when(media.gbAcquire(lease,"helmet-a",90)).thenReturn(obj("leaseId",lease));
        WearableMaintenance maintenance=activeMaintenance();
        MockMvc mvc=MockMvcBuilders.standaloneSetup(new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance)).addFilters(new RepeatableFilter()).build();
        String time=String.valueOf(Instant.now().getEpochSecond()),nonce="nonce0000000000099";
        String signature=HelmetCloudClient.signature(KEY,time,nonce,"PUT",path,body.getBytes(StandardCharsets.UTF_8));
        MockHttpServletRequestBuilder original=put(path).contentType("application/json;charset=UTF-8").content(body.getBytes(StandardCharsets.UTF_8))
                .header("X-GB-Time",time).header("X-GB-Nonce",nonce).header("X-GB-Signature",signature);
        assertEquals(200,mvc.perform(original).andReturn().getResponse().getStatus());
        String secondNonce="nonce0000000000100",secondSignature=HelmetCloudClient.signature(KEY,time,secondNonce,"PUT",path,body.getBytes(StandardCharsets.UTF_8));
        MockHttpServletRequestBuilder changed=put(path).contentType("application/json;charset=UTF-8").content(body.replace("helmet-a","helmet-b").getBytes(StandardCharsets.UTF_8))
                .header("X-GB-Time",time).header("X-GB-Nonce",secondNonce).header("X-GB-Signature",secondSignature);
        assertEquals(401,mvc.perform(changed).andReturn().getResponse().getStatus());verify(media,times(1)).gbAcquire(lease,"helmet-a",90);
        verify(maintenance,times(1)).tryBeginWrite();verify(maintenance,times(1)).endWrite();
    }
    @Test void maintenancePauseRejectsPutGetAndDeleteWithoutTouchingMedia()throws Exception{
        for(String method:new String[]{"PUT","GET","DELETE"}){
            HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=mock(WearableMaintenance.class);
            FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);
            String body="PUT".equals(method)?"{\"deviceId\":\"helmet-a\"}":"";
            org.springframework.http.ResponseEntity<com.alibaba.fastjson2.JSONObject> response=c.lease(LEASE,body,leaseRequest(method,LEASE,body,"paused-"+method+"-0000000001"));
            assertEquals(503,response.getStatusCodeValue());assertEquals("GB_MAINTENANCE_PAUSED",response.getBody().getString("error"));
            verify(maintenance).tryBeginWrite();verify(maintenance,never()).endWrite();verifyNoInteractions(media);
        }
    }
    @Test void successfulPutGetAndDeleteHoldMaintenanceLeaseAcrossMediaCall()throws Exception{
        for(String method:new String[]{"PUT","GET","DELETE"}){
            HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=activeMaintenance();
            when(media.gbAcquire(LEASE,"helmet-a",90)).thenReturn(obj("leaseId",LEASE));
            when(media.gbLeaseStatus(LEASE)).thenReturn(obj("leaseId",LEASE));when(media.gbRelease(LEASE)).thenReturn(obj("released",true));
            FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);
            String body="PUT".equals(method)?"{\"deviceId\":\"helmet-a\"}":"";
            assertEquals(200,c.lease(LEASE,body,leaseRequest(method,LEASE,body,"success-"+method+"-00000001")).getStatusCodeValue());
            org.mockito.InOrder order=inOrder(maintenance,media);order.verify(maintenance).tryBeginWrite();
            if("PUT".equals(method))order.verify(media).gbAcquire(LEASE,"helmet-a",90);
            else if("GET".equals(method))order.verify(media).gbLeaseStatus(LEASE);
            else order.verify(media).gbRelease(LEASE);
            order.verify(maintenance).endWrite();order.verifyNoMoreInteractions();
        }
    }
    @Test void mappedMediaFailureStillReleasesMaintenanceLease()throws Exception{
        HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=activeMaintenance();
        when(media.gbLeaseStatus(LEASE)).thenThrow(new IllegalStateException("GB_STREAM_NOT_FOUND"));
        FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);
        assertEquals(503,c.lease(LEASE,"",leaseRequest("GET",LEASE,"","failed-get-00000001")).getStatusCodeValue());
        verify(maintenance).tryBeginWrite();verify(maintenance).endWrite();
    }
    @Test void unexpectedMediaFailureStillReleasesMaintenanceLease()throws Exception{
        HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=activeMaintenance();
        when(media.gbRelease(LEASE)).thenThrow(new UnsupportedOperationException("test failure"));
        FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);
        MockHttpServletRequest r=leaseRequest("DELETE",LEASE,"","failed-delete-000001");
        assertThrows(UnsupportedOperationException.class,()->c.lease(LEASE,"",r));
        verify(maintenance).tryBeginWrite();verify(maintenance).endWrite();
    }
    @Test void unauthenticatedLeaseRequestDoesNotAcquireMaintenanceLease(){
        HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=mock(WearableMaintenance.class);
        FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);
        assertEquals(401,c.lease(LEASE,"",new MockHttpServletRequest("DELETE","/internal/fuda-gb/v1/leases/"+LEASE)).getStatusCodeValue());
        verifyNoInteractions(media,maintenance);
    }
    @Test void invalidLeaseIdentifierDoesNotAcquireMaintenanceLease()throws Exception{
        HelmetMediaService media=mock(HelmetMediaService.class);WearableMaintenance maintenance=mock(WearableMaintenance.class);
        FudaGbInternalController c=new FudaGbInternalController(media,true,KEY,"helmet-a",maintenance);
        assertEquals(400,c.lease("bad","",leaseRequest("GET","bad","","invalid-id-00000001")).getStatusCodeValue());
        verifyNoInteractions(media,maintenance);
    }
}
