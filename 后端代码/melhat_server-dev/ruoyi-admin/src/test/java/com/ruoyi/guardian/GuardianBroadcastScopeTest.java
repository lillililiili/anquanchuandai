package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.headband.service.HeadbandService;
import com.ruoyi.helmet.pojo.po.TtsTextSynthesisBroadcast;
import com.ruoyi.helmet.service.ITtsTextSynthesisBroadcastService;
import com.ruoyi.melhat.direct.HelmetMediaService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianBroadcastScopeTest {
    @Test void pcAndMobileRecipientSnapshotKeepsDispatchTimeAssignment() {
        JSONObject master=object("accounts",new JSONArray(),"devices",new JSONArray(),"assignments",new JSONArray(),"people",new JSONArray());
        rows(master,"accounts").add(object("id","operator","enabled",true));
        rows(master,"people").add(object("id","person-ledger","portalId","P-old","name","原人员"));
        rows(master,"assignments").add(object("active",true,"deviceId","asset-a","personId","person-ledger"));
        JSONObject device=object("id","asset-a","portalDeviceId","helmet-a","siteId","site-old","areaId","area-old");
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(master);
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        JSONObject recipient=GuardianHelmetRecipient.capture(access.context(object("id","operator")),device);
        device.put("siteId","site-new");rows(master,"people").getJSONObject(0).put("portalId","P-new");
        assertEquals("site-old",recipient.getString("siteId"));assertEquals("area-old",recipient.getString("areaId"));assertEquals("P-old",recipient.getString("personId"));
    }
    @Test void directBroadcastCommandRetainsCapturedScopeForHistoricalAuthorization(){
        ITtsTextSynthesisBroadcastService records=mock(ITtsTextSynthesisBroadcastService.class);
        when(records.save(any(TtsTextSynthesisBroadcast.class))).thenReturn(true);
        GuardianVoiceService voice=spy(new GuardianVoiceService(mock(HeadbandService.class),records));
        HelmetMediaService media=mock(HelmetMediaService.class);doReturn(true).when(voice).isDirect("helmet-a");doReturn(media).when(voice).directMedia();
        when(media.command(eq("operator"),eq("helmet-a"),any())).thenReturn(object("status","sent"));
        JSONArray hats=new JSONArray();hats.add(object("hatNumber","helmet-a","name","原人员","siteId","site-old","areaId","area-old","personId","P-old"));
        voice.broadcast(hats,"请确认状态","operator","操作员");
        ArgumentCaptor<JSONObject> sent=ArgumentCaptor.forClass(JSONObject.class);verify(media).command(eq("operator"),eq("helmet-a"),sent.capture());
        assertEquals("site-old",sent.getValue().getString("siteId"));assertEquals("area-old",sent.getValue().getString("areaId"));assertEquals("P-old",sent.getValue().getString("personId"));
    }
}
