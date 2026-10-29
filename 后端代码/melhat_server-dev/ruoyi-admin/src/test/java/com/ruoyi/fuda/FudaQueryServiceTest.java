package com.ruoyi.fuda;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.*;
import com.ruoyi.helmet.service.DirectHelmetAccess;
import com.ruoyi.melhat.direct.DirectHelmetProperties;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import org.junit.jupiter.api.Test;
import java.util.*;
import static com.ruoyi.fuda.FudaMapping.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class FudaQueryServiceTest {
    private final AdminLedgerStore ledger=mock(AdminLedgerStore.class);
    private final GuardianStore guardian=mock(GuardianStore.class);
    private final DirectHelmetAccess access=mock(DirectHelmetAccess.class);
    private final DirectBeltAccess beltAccess=mock(DirectBeltAccess.class);
    private final FudaAlarmJournal journal=mock(FudaAlarmJournal.class);
    private final FudaProperties p=FudaAuthTest.properties();
    private FudaQueryService service(){return new FudaQueryService(p,ledger,guardian,journal,new DirectHelmetProperties(),new DirectBeltProperties(),access,beltAccess,FudaAuthTest.CLOCK);}
    private FudaAuth.Principal principal(){return new FudaAuth.Principal("fuda-test",p.getApplications().get("fuda-test"),FudaAuthTest.KEY);}
    private void register(){
        when(ledger.read()).thenReturn(object("devices",JSONArray.of(object("id","device-12","type","HELMET","source","DIRECT_HELMET","deviceNumber","real-1","portalDeviceId","real-1","lifecycle","IN_STOCK"))));
        when(guardian.snapshot()).thenReturn(object("devices",JSONArray.of(object("id","real-1","source","DIRECT_HELMET","online",true,"battery",80,"batteryReportedAt","2026-10-27T07:59:50Z","batteryFreshness","CURRENT"))));
        when(access.status("real-1")).thenReturn(object("online",false));
    }
    @Test void entireUnauthorizedBatchIsRejectedBeforeTelemetryRead(){
        register();JSONObject input=object("devices",JSONArray.of(object("deviceType","HELMET","deviceId","real-1"),object("deviceType","HELMET","deviceId","other")));
        assertEquals(40301,assertThrows(FudaException.class,()->service().query("statuses",principal(),input)).code);verifyNoInteractions(guardian);
    }
    @Test void externalIdIsUsedAndLiveDisconnectOverridesPausedSnapshot(){
        register();JSONObject result=service().query("statuses",principal(),object("devices",JSONArray.of(object("deviceType","HELMET","deviceId","real-1"))));
        JSONObject item=(JSONObject)((List<?>)result.get("items")).get(0);assertEquals("real-1",item.getString("deviceId"));assertEquals("OFFLINE",item.getString("onlineStatus"));assertEquals("STALE",item.getJSONObject("battery").getString("validity"));assertNull(item.get("deviceModel"));
        assertEquals(40301,assertThrows(FudaException.class,()->service().query("positions",principal(),object("devices",JSONArray.of(object("deviceType","HELMET","deviceId","device-12"))))).code);
    }
    @Test void simulatedOrDuplicateReferencesAreNeverExported(){
        register();JSONObject input=object("devices",JSONArray.of(object("deviceType","HELMET","deviceId","real-1"),object("deviceType","HELMET","deviceId","real-1")));
        assertEquals(40001,assertThrows(FudaException.class,()->service().query("statuses",principal(),input)).code);
        ledger.read().getJSONArray("devices").getJSONObject(0).put("demo",true);
        assertEquals(40301,assertThrows(FudaException.class,()->service().query("statuses",principal(),input)).code);
    }
    @Test void alarmsDefaultTo100AndPreserveCommittedEmptyWatermark(){
        register();when(journal.highWatermark()).thenReturn(23L);when(journal.scan(eq(0L),eq(100),anySet())).thenReturn(new FudaAlarmJournal.AlarmPage(Collections.emptyList(),23L,false));
        JSONObject page=service().query("alarms",principal(),object("cursor",null));
        assertEquals(23,FudaCursor.decode(principal(),Collections.singleton("HELMET:real-1"),page.getString("nextCursor")));assertFalse(page.getBooleanValue("hasMore"));
        verify(journal).scan(0L,100,Collections.singleton("HELMET:real-1"));verifyNoInteractions(guardian);
        assertEquals(40001,assertThrows(FudaException.class,()->service().query("alarms",principal(),object("cursor",null,"limit",501))).code);
    }
    @Test void expiredOrAheadCursorIsAnExplicitRecoveryError(){
        register();when(journal.retainedFloor()).thenReturn(10L);
        assertEquals(41001,assertThrows(FudaException.class,()->service().query("alarms",principal(),object("cursor",null))).code);
        when(journal.retainedFloor()).thenReturn(0L);when(journal.highWatermark()).thenReturn(10L);
        String cursor=FudaCursor.encode(principal(),Collections.singleton("HELMET:real-1"),11);
        assertEquals(40903,assertThrows(FudaException.class,()->service().query("alarms",principal(),object("cursor",cursor))).code);
    }
    @Test void disabledAssetStaysAuthorizedForHistoryButCannotAppearOnline(){
        register();ledger.read().getJSONArray("devices").getJSONObject(0).put("lifecycle","DISABLED");when(access.status("real-1")).thenReturn(object("online",true));
        JSONObject result=service().query("statuses",principal(),object("devices",JSONArray.of(object("deviceType","HELMET","deviceId","real-1"))));
        assertEquals("OFFLINE",((JSONObject)((List<?>)result.get("items")).get(0)).getString("onlineStatus"));
    }
}
