package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static com.ruoyi.guardian.WearableModel.*;

class WearableBusinessPolicyTest {
    @Test void hiddenWatchIsRemovedFromMobileContextAndAssignmentHistoryWithoutMutatingLedger(){
        WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());policy.configure(object("simulatedWatchVisible",false),admin());
        JSONObject source=object("accounts",JSONArray.of(object("id","demo-system","enabled",true)),"devices",JSONArray.of(object("id","watch-ledger","portalDeviceId","RL-W001","source","DEMO_WATCH")),"people",JSONArray.of(object("id","demo-person","source","DEMO_WATCH")),"assignments",JSONArray.of(object("deviceId","watch-ledger")),"history",JSONArray.of(object("deviceId","watch-ledger")));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(source));
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));org.springframework.test.util.ReflectionTestUtils.setField(access,"businessPolicy",policy);
        JSONObject view=access.context(object("id","demo-system")).data;
        assertTrue(rows(view,"devices").isEmpty());assertTrue(rows(view,"people").isEmpty());assertTrue(rows(view,"assignments").isEmpty());assertTrue(rows(view,"history").isEmpty());assertEquals(1,rows(source,"devices").size());
        assertFalse(safe(object("businessOperations",object("private",true))).containsKey("businessOperations"));
    }
    JdbcTemplate jdbc(){return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));}
    GuardianAccess.Context admin(){JSONObject data=object("sites",JSONArray.of(object("id","site-1","enabled",true)),"accounts",JSONArray.of(object("id","demo-system","enabled",true)),"roles",new JSONArray());AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(data);return new GuardianAccess(ledger,mock(AdminQueryService.class)).context(object("id","demo-system"));}
    @Test void verifiedVideoSurvivesOfflineWhilePendingPhotoIsNotAvailable(){WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());JSONObject hat=object("id","866652021714127","source","DIRECT_HELMET","online",true,"mediaAvailable",true);JSONObject features=policy.features(hat);
        assertTrue(features.getJSONObject("video").getBooleanValue("available"));assertTrue(features.getJSONObject("photo").getBooleanValue("supported"));assertFalse(features.getJSONObject("photo").getBooleanValue("verified"));assertFalse(features.getJSONObject("vitals").getBooleanValue("supported"));
        hat.put("online",false);features=policy.features(hat);assertTrue(features.getJSONObject("video").getBooleanValue("supported"));assertTrue(features.getJSONObject("video").getBooleanValue("verified"));assertFalse(features.getJSONObject("video").getBooleanValue("available"));}
    @Test void beltOnlyUsesConfirmedHookMappingAndNeverOffersVideo(){WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());JSONObject belt=object("id","866652023095053","source","DIRECT_BELT","online",true,"telemetryFreshness","CURRENT","hookMappingConfirmed",true);
        JSONObject states=policy.features(belt);assertTrue(states.getJSONObject("hooks").getBooleanValue("available"));assertFalse(states.getJSONObject("wear").getBooleanValue("verified"));assertFalse(states.getJSONObject("video").getBooleanValue("supported"));assertFalse(states.getJSONObject("proximity").getBooleanValue("supported"));
        belt.put("telemetryFreshness","STALE");assertFalse(policy.features(belt).getJSONObject("hooks").getBooleanValue("available"));}
    @Test void visibilityIsPersistedAndNeverDeletesUnderlyingDataOrUnassignedEvents(){JdbcTemplate db=jdbc();WearableBusinessPolicy policy=new WearableBusinessPolicy(db);JSONObject source=object("devices",JSONArray.of(object("id","RL-W001","source","DEMO_WATCH"),object("id","hat","source","DIRECT_HELMET")),"events",JSONArray.of(object("id","real","source","device")),"vitals",JSONArray.of(object("deviceId","RL-W001")));
        policy.configure(object("simulatedWatchVisible",false),admin());JSONObject view=policy.decorate(copy(source),false);assertEquals(1,rows(view,"devices").size());assertEquals(1,rows(view,"events").size());assertTrue(rows(view,"vitals").isEmpty());assertEquals(2,rows(source,"devices").size());assertFalse(new WearableBusinessPolicy(db).config().getBooleanValue("simulatedWatchVisible"));}
    @Test void businessCallsCannotBypassAcceptanceButAdminMayExplicitlyTest(){WearableBusinessPolicy policy=new WearableBusinessPolicy(jdbc());JSONObject hat=object("id","866652021714127","source","DIRECT_HELMET","online",true,"mediaAvailable",true);assertEquals("FEATURE_PENDING_ACCEPTANCE",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"photo",false,admin())).errorCode);assertDoesNotThrow(()->policy.require(hat,"photo",true,admin()));assertEquals("FEATURE_UNSUPPORTED",assertThrows(AdminQueryService.QueryFailed.class,()->policy.require(hat,"vitals",true,admin())).errorCode);}
}
