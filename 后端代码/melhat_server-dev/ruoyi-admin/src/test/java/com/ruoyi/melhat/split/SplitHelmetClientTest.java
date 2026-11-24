package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.AdminQueryService;
import okhttp3.*;
import org.junit.jupiter.api.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;
import static com.ruoyi.melhat.split.SplitTelemetry.obj;

class SplitHelmetClientTest {
    SplitHelmetProperties p;
    @BeforeEach void setup(){p=new SplitHelmetProperties();p.setEnabled(true);p.setClientId("test-id");p.setClientSecret("test-secret");p.setCallbackSecret("01234567890123456789012345678901");p.setAllowedDevices("SN1");}
    String signal(String kind){return p.getBaseUrl()+"/index/api/webrtc?app=app_rl&stream=stream_SN1"+("talk".equals(kind)?"_talk":"")+"&type="+("talk".equals(kind)?"push":"play");}
    Response response(Request r,int status,String body){return new Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(status).message("test").body(ResponseBody.create(MediaType.get("application/json"),body)).build();}

    @Test void defaultDisabledAndEnabledSettingsAreValidated(){assertFalse(new SplitHelmetProperties().isEnabled());p.validate();p.setFileOrigins("http://192.168.1.10:18080/media");assertThrows(IllegalArgumentException.class,p::validate);p.setFileOrigins("http://user:pass@192.168.1.10:18080");assertThrows(IllegalArgumentException.class,p::validate);p.setFileOrigins("http://192.168.1.10:18080");p.validate();}
    @Test void sdpProxyRequiresExactOriginDeviceAndDirection(){
        SplitHelmetClient client=new SplitHelmetClient(p);client.validateSignal(signal("play"),"SN1","play");client.validateSignal(signal("talk"),"SN1","talk");
        for(String bad:Arrays.asList(signal("play").replace("api.hel.epplink.com","evil.test"),signal("play").replace("SN1","SN2"),signal("play")+"&type=push",signal("play")+"&secret=oops",signal("play").replace("https:","http:"),signal("play").replace("/index/api/webrtc","/api/auth/token"),signal("play").replace("https://","https://user@")))assertThrows(AdminQueryService.QueryFailed.class,()->client.validateSignal(bad,"SN1","play"));
        assertThrows(AdminQueryService.QueryFailed.class,()->client.validateSignal(signal("talk"),"SN1","play"));
    }
    @Test void onlyExplicitHttpFileOriginIsAllowedAndNoAuthorizationLeaks()throws Exception {
        p.setFileOrigins("http://192.168.1.10:18080");List<Request> requests=new ArrayList<>();SplitHelmetClient client=new SplitHelmetClient(p,new OkHttpClient.Builder().followRedirects(false).retryOnConnectionFailure(false).addInterceptor(chain->{requests.add(chain.request());return response(chain.request(),200,"file");}).build());
        String valid="http://192.168.1.10:18080/media/SN1/video.mp4";assertEquals(valid,client.safeFileUrl(valid,"SN1"));
        for(String bad:Arrays.asList(valid.replace("SN1","SN2"),valid.replace("18080","18081"),valid.replace("video.mp4","../SN2/video.mp4"),valid.replace("video.mp4","%2e%2e/video.mp4"),valid.replace("192.168.1.10","evil.test")))assertNull(client.safeFileUrl(bad,"SN1"));
        try(Response ignored=client.file(valid,"SN1","bytes=0-10")){}assertNull(requests.get(0).header("Authorization"));assertEquals("bytes=0-10",requests.get(0).header("Range"));assertThrows(AdminQueryService.QueryFailed.class,()->client.file(valid,"SN1","bytes=0-1,2-3"));
    }
    @Test void rejectedOrUncertainControlIsOneAttemptAndBearerStaysServerSide(){
        AtomicInteger tokens=new AtomicInteger(),controls=new AtomicInteger();List<Request> requests=new ArrayList<>();
        SplitHelmetClient client=new SplitHelmetClient(p,new OkHttpClient.Builder().followRedirects(false).retryOnConnectionFailure(false).addInterceptor(chain->{Request r=chain.request();requests.add(r);if(r.url().encodedPath().equals("/api/auth/token")){tokens.incrementAndGet();return response(r,200,obj("code",200,"data",obj("accessToken","token-value","expireTime",3600,"tokenType","Bearer")).toJSONString());}controls.incrementAndGet();assertTrue(r.body().isOneShot());assertEquals("Bearer token-value",r.header("Authorization"));return response(r,401,"{}");}).build());
        assertThrows(AdminQueryService.QueryFailed.class,()->client.post("/api/monitor/record",obj("helmetSnList",Arrays.asList("SN1"))));assertEquals(1,controls.get());assertEquals(1,tokens.get());
        assertThrows(AdminQueryService.QueryFailed.class,()->client.post("/api/monitor/capture",obj("helmetSnList",Arrays.asList("SN1"))));assertEquals(2,controls.get());assertEquals(2,tokens.get());
        assertFalse(requests.get(1).url().toString().contains("token-value"));
    }
    @Test void zlmJsonIsNormalizedToSdpWithoutVendorBearer(){
        SplitHelmetClient client=new SplitHelmetClient(p,new OkHttpClient.Builder().addInterceptor(chain->{assertNull(chain.request().header("Authorization"));return response(chain.request(),200,obj("code",0,"sdp","v=0\r\nanswer").toJSONString());}).build());assertEquals("v=0\r\nanswer",client.signal(signal("play"),"SN1","play","v=0\r\no=offer"));
    }
}
