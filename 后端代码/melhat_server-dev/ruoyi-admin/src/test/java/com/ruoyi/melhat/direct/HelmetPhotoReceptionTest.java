package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import java.util.Arrays;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class HelmetPhotoReceptionTest {
    @TempDir Path directory;
    final String assetId="11111111-2222-4333-8444-555555555555",received="2026-11-03T08:17:42Z";
    final HelmetCloudClient cloud=mock(HelmetCloudClient.class);
    final HelmetMediaProperties properties=new HelmetMediaProperties();
    HelmetMediaStore store;
    HelmetMediaService service(){
        if(store==null)store=new HelmetMediaStore(directory.resolve("photo-journal.json").toString());
        properties.setControlUrl("https://media.example");when(cloud.configured()).thenReturn(true);
        HelmetMediaService service=new HelmetMediaService(cloud,store,properties,mock(ObjectProvider.class));
        ReflectionTestUtils.setField(service,"healthy",true);return service;
    }
    JSONObject report(){return obj("act","ca_upload_photo","image_url","https://media.example/helmet-media/files/"+assetId+"?token=private");}
    JSONObject context(){return obj("siteId","site-original","areaId","area-original","personId","person-original","personName","原领用人",
            "bindingId","issue-original","bindingStart","2026-11-03T08:00:00Z","bindingEnd",null,"device",obj("areaId","device-area"));}
    JSONObject asset(){return obj("assetId",assetId,"deviceId","helmet-a","kind","photo","status","ready","deviceBindingConfirmed",true,"createdAt","2026-11-03T08:17:40Z");}
    JSONObject file(HelmetMediaService service,JSONObject asset){when(cloud.request("GET","/assets?deviceId=helmet-a",null)).thenReturn(obj("items",JSONArray.of(asset)));return service.assets("helmet-a").getJSONObject(0);}

    @Test void physicalPhotoKeepsFirstReceptionScopeAcrossReplayAndRestartWithoutInventingCaptureOwnership(){
        HelmetMediaService service=service();JSONObject captured=context();
        store.update(s->{s.put("commands",obj("HC-other",obj("id","HC-other","deviceId","helmet-a","action","take_photo","status","sent","createdAt","2026-11-03T08:17:00Z")));return null;});
        assertTrue(service.receipt("helmet-a",report(),received,captured));
        JSONObject injected=asset();injected.put("siteId","forged");injected.put("personId","forged");injected.put("personName","伪造");
        JSONObject result=file(service,injected);
        assertEquals("site-original",result.getString("siteId"));assertEquals("area-original",result.getString("areaId"));
        assertEquals("person-original",result.getString("receivedPersonId"));assertEquals("原领用人",result.getString("receivedPersonName"));
        assertEquals(received,result.getString("receivedAt"));assertEquals("RECEIVED_AT",result.getString("timeBasis"));
        assertEquals("DEVICE_RECEIPT",result.getString("scopeBasis"));assertFalse(result.getBooleanValue("unassigned"));
        assertNull(result.get("personId"));assertNull(result.get("personName"));assertNull(result.get("captureTime"));assertNull(result.get("requestId"));
        assertEquals("sent",store.snapshot().getJSONObject("commands").getJSONObject("HC-other").getString("status"));
        captured.put("siteId","new-site");captured.put("personId","new-person");
        service.receipt("helmet-a",report(),"2026-11-04T09:00:00Z",captured);
        store=new HelmetMediaStore(directory.resolve("photo-journal.json").toString());
        assertEquals(result,file(service(),injected));assertFalse(store.snapshot().toJSONString().contains("token="));
    }
    @Test void onlyConfirmedFreshPhotoFromExactDeviceCanReceiveFrozenScope(){
        HelmetMediaService service=service();service.receipt("helmet-a",report(),received,context());
        for(JSONObject change:Arrays.asList(obj("deviceId","helmet-b"),obj("kind","video"),obj("status","uploading"),
                obj("deviceBindingConfirmed",false),obj("deviceBindingConfirmed",null),obj("createdAt",null),
                obj("createdAt","2026-11-03T08:18:13Z"),obj("createdAt","2026-11-03T08:12:41Z"))){
            JSONObject invalid=asset();invalid.putAll(change);invalid.put("siteId","upstream-site");invalid.put("receivedPersonId","upstream-person");
            JSONObject result=file(service,invalid);assertNull(result.get("siteId"),change.toJSONString());assertNull(result.get("receivedPersonId"));
        }
        assertEquals("site-original",file(service,asset()).getString("siteId"));
    }
    @Test void oneSecondCloudClockLeadKeepsReceptionScopeWithoutClaimingCaptureTime(){
        HelmetMediaService service=service();service.receipt("helmet-a",report(),received,context());
        JSONObject cloudAhead=asset();cloudAhead.put("createdAt","2026-11-03T08:17:43Z");
        JSONObject result=file(service,cloudAhead);assertEquals("site-original",result.getString("siteId"));
        assertEquals(received,result.getString("receivedAt"));assertEquals("RECEIVED_AT",result.getString("timeBasis"));
        assertNull(result.get("personId"));assertNull(result.get("captureTime"));
    }
    @Test void arbitraryUrlsAndCrossDeviceReceiptsNeverAuthorizeAFileOrTriggerUrlFetch(){
        HelmetMediaService service=service();
        for(String url:Arrays.asList("https://foreign.example/helmet-media/files/"+assetId,"http://media.example/helmet-media/files/"+assetId,
                "https://evil@media.example/helmet-media/files/"+assetId,"https://media.example/helmet-media/files/"+assetId+"#fragment",
                "https://media.example/helmet-media/files/"+assetId+"?redirect=elsewhere","https://media.example/other/"+assetId)){
            JSONObject raw=report();raw.put("image_url",url);service.receipt("helmet-a",raw,received,context());
        }
        assertNull(store.snapshot().getJSONObject("photoReceptions"));verify(cloud,never()).request(anyString(),anyString(),any());
        service.receipt("helmet-b",report(),received,context());assertNull(file(service,asset()).get("siteId"));
    }
    @Test void legacyWithoutContextCannotGainTodaysScopeEvenOnRetransmission(){
        HelmetMediaService service=service();service.receipt("helmet-a",report(),received);
        service.receipt("helmet-a",report(),received,context());
        JSONObject result=file(service,asset());assertTrue(result.getBooleanValue("unassigned"));assertNull(result.get("siteId"));assertNull(result.get("receivedPersonId"));
    }
    @Test void returnedOrFutureBindingNeverBecomesReceptionWearer(){
        for(JSONObject change:Arrays.asList(obj("bindingEnd","2026-11-03T08:10:00Z"),obj("bindingStart","2026-11-03T08:20:00Z"),obj("bindingStart","invalid"),obj("bindingId",null))){
            store=new HelmetMediaStore(directory.resolve("photo-"+java.util.UUID.randomUUID()+".json").toString());HelmetMediaService service=service();
            JSONObject captured=context();captured.putAll(change);service.receipt("helmet-a",report(),received,captured);
            JSONObject result=file(service,asset());assertEquals("site-original",result.getString("siteId"));assertEquals("device-area",result.getString("areaId"));
            assertNull(result.get("receivedPersonId"));assertNull(result.get("personId"));
        }
    }
}
