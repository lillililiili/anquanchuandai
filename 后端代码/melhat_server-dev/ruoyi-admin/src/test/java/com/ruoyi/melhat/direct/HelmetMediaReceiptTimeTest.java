package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.WearableBusinessStore;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

class HelmetMediaReceiptTimeTest {
    @Test void replayUsesCapturedReceiptTimeAndDoesNotRewriteCommandCreationOrRepeatReceipt(){
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        WearableBusinessStore business=new WearableBusinessStore(jdbc,java.util.Base64.getEncoder().encodeToString(new byte[32]));
        HelmetMediaStore store=new HelmetMediaStore("missing-media-"+UUID.randomUUID()+".json","public-"+UUID.randomUUID(),business);
        String created="2026-10-20T09:00:00Z",received="2026-10-20T09:00:10Z";
        store.update(s->{s.put("commands",obj("HC-original",obj("id","HC-original","deviceId","hat","action","take_photo","status","sent","createdAt",created)));return null;});
        HelmetMediaService media=new HelmetMediaService(mock(HelmetCloudClient.class),store,new HelmetMediaProperties(),mock(ObjectProvider.class));
        JSONObject raw=obj("act","ca_upload_photo","talkback_id","HC-original","res",obj("status",true));
        assertTrue(media.receipt("hat",raw,received));
        JSONObject command=store.snapshot().getJSONObject("commands").getJSONObject("HC-original");assertEquals(received,command.getString("receiptAt"));assertEquals(created,command.getString("createdAt"));
        assertTrue(media.receipt("hat",raw,"2026-10-26T09:00:00Z"));assertEquals(received,store.snapshot().getJSONObject("commands").getJSONObject("HC-original").getString("receiptAt"));
    }
}
