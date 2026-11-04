package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import java.time.Instant;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class HelmetDeviceAudioTest {
    final String assetId="11111111-2222-4333-8444-555555555555";
    final String file="https://media.example/helmet-media/files/"+assetId;
    final HelmetCloudClient cloud=mock(HelmetCloudClient.class);
    HelmetMediaService service(){HelmetMediaProperties p=new HelmetMediaProperties();p.setControlUrl("https://media.example/helmet-media/control/v1");return new HelmetMediaService(cloud,mock(HelmetMediaStore.class),p,mock(ObjectProvider.class));}
    @Test void onlyTheConfiguredFixedFileReferenceIsParsedWithoutFetchingIt(){
        HelmetMediaService service=service();assertEquals(assetId,service.audioReference(file+"?token=expired-but-reference-only"));assertEquals(assetId,service.audioReference(file));
        for(String invalid:new String[]{null,"","IyFBTVIKbase64",assetId,file.replace("https:","http:"),file.replace("media.example","media.example.evil"),
                file.replace("media.example","attacker@media.example"),file+"#fragment",file+"?token=a&next=private",file.replace("files/","files/../files/"),file.replace("files/","files%2f"),file.replace("media.example","media.example:444")})
            assertThrows(IllegalArgumentException.class,()->service.audioReference(invalid));
        verifyNoInteractions(cloud);
    }
    @Test void assetMustBeRealAudioFromExactlyTheReportingDevice(){
        HelmetMediaService service=service();JSONObject asset=obj("assetId",assetId,"kind","audio","deviceId","hat-a","status","ready");
        when(cloud.request("GET","/assets?deviceId=hat-a",null)).thenReturn(obj("assets",JSONArray.of(asset)));
        assertEquals(asset,service.deviceAudioAsset("hat-a",assetId));
        for(String key:new String[]{"deviceId","kind","status"}){Object old=asset.get(key);asset.put(key,"wrong");assertThrows(IllegalArgumentException.class,()->service.deviceAudioAsset("hat-a",assetId));asset.put(key,old);}
        assertThrows(IllegalArgumentException.class,()->service.deviceAudioAsset("hat-a","aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"));
        verify(cloud,times(5)).request("GET","/assets?deviceId=hat-a",null);
    }
    @Test void onlyShortLivedDedicatedPlayableCopiesBecomeTickets(){
        HelmetMediaService service=service();JSONObject asset=obj("assetId",assetId,"playbackMime","audio/mpeg","playbackUrl",file+"?variant=playback&token=signed","playbackExpiresAt",Instant.now().plusSeconds(30).toString());
        assertNotNull(service.deviceAudioPlayback(asset));
        for(String url:new String[]{file+"?token=original",file.replace("media.example","evil.example")+"?variant=playback&token=a",file+"?variant=playback&token=a&token=b"}){
            JSONObject bad=JSONObject.parseObject(asset.toJSONString());bad.put("playbackUrl",url);assertNull(service.deviceAudioPlayback(bad));}
        JSONObject bad=JSONObject.parseObject(asset.toJSONString());bad.put("playbackExpiresAt",Instant.now().minusSeconds(1).toString());assertNull(service.deviceAudioPlayback(bad));
        bad.put("playbackExpiresAt",Instant.now().plusSeconds(3600).toString());assertNull(service.deviceAudioPlayback(bad));
        asset.put("playbackMime","video/mp4");assertNull(service.deviceAudioPlayback(asset));assertNull(service.deviceAudioPlayback(obj("assetId",assetId,"url",file)));
        verifyNoInteractions(cloud);
    }
}
