package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Map;

import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminQueryAreaScopeTest {
    private JSONObject state;
    private JSONObject actor;
    private JSONObject grant;
    private AdminLedgerStore ledger;
    private GuardianStore guardian;
    private AdminQueryService queries;

    @BeforeEach void setup() {
        actor = object("id", "area-editor", "enabled", true, "roleIds", JSONArray.of("asset-role"),
                "roleScopes", object("asset-role", object("siteIds", JSONArray.of("site-1"), "areaIds", JSONArray.of("area-A"))));
        grant = object("operations", JSONArray.of("assets:read", "assets:write"), "siteIds", JSONArray.of("site-1"), "areaIds", "*");
        state = object("accounts", JSONArray.of(actor),
                "roles", JSONArray.of(object("id", "asset-role", "enabled", true, "grants", JSONArray.of(grant))),
                "sites", JSONArray.of(object("id", "site-1", "enabled", true)),
                "areas", JSONArray.of(object("id", "area-A", "siteId", "site-1", "enabled", true),
                        object("id", "area-B", "siteId", "site-1", "enabled", true)),
                "devices", JSONArray.of(device("A", "area-A"), device("B", "area-B"), device("UNASSIGNED", null)),
                "assignments", new JSONArray(), "people", new JSONArray(), "maintenanceOrders", new JSONArray());
        ledger = mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(i -> JSONObject.parseObject(state.toJSONString()));
        guardian = mock(GuardianStore.class);
        when(guardian.snapshot()).thenReturn(object("devices", new JSONArray()));
        queries = new AdminQueryService(ledger, guardian, mock(ObjectProvider.class));
    }

    private JSONObject device(String suffix, String areaId) {
        return object("id", "asset-" + suffix, "siteId", "site-1", "areaId", areaId,
                "type", "HELMET", "source", "DIRECT_HELMET", "code", "CODE-" + suffix,
                "deviceNumber", "LOGIN-" + suffix, "portalDeviceId", "LOGIN-" + suffix, "sn", "SERIAL-" + suffix,
                "name", suffix, "modelId", "unknown-HELMET", "lifecycle", "STOCK", "relation", "UNASSIGNED", "version", 1);
    }

    @Test void localRecorderObservationKeepsCapturedScopeAfterAssetTransfer() {
        state.getJSONArray("sites").getJSONObject(0).put("portalStation","S1");
        state.getJSONArray("sites").add(object("id","site-2","enabled",true,"portalStation","S2"));
        JSONObject observation=object("state","RECORDING","rawType","0","source","DIRECT_HELMET",
                "reportAct","toggle_localrecord","receivedAt","2026-11-02T01:00:00Z","timeBasis","RECEIVED_AT",
                "siteId","site-2","personId","former-person","personName","原厂站人员");
        JSONObject remote=object("id","LOGIN-A","source","DIRECT_HELMET","station","S1","siteId","site-1","localRecording",observation);
        JSONObject snapshot=object("devices",JSONArray.of(remote));when(guardian.snapshot()).thenReturn(snapshot);
        assertFalse(queries.query("area-editor","device",object("siteId","site-1","id","asset-A")).containsKey("localRecording"));
        GuardianAccess access=new GuardianAccess(ledger,queries);
        assertFalse(access.context(actor).snapshot(snapshot).getJSONArray("devices").getJSONObject(0).containsKey("localRecording"));
        assertEquals("site-2",remote.getJSONObject("localRecording").getString("siteId"));
        assertFalse(mobileContext(actor).getJSONArray("devices").getJSONObject(0).containsKey("localRecording"));
        // Grant the original scope; never rewrite the saved observation to make it visible.
        grant.put("siteIds",JSONArray.of("site-1","site-2"));
        assertEquals(observation,queries.query("area-editor","device",object("siteId","site-1","id","asset-A")).get("localRecording"));
        assertEquals(observation,access.context(actor).snapshot(snapshot).getJSONArray("devices").getJSONObject(0).get("localRecording"));
        assertEquals(observation,mobileContext(actor).getJSONArray("devices").getJSONObject(0).get("localRecording"));
        grant.put("siteIds",JSONArray.of("site-1"));
        assertFalse(mobileContext(actor).getJSONArray("devices").getJSONObject(0).containsKey("localRecording"));
        assertEquals("former-person",observation.getString("personId"));
        assertEquals("site-2",observation.getString("siteId"));
    }

    private JSONObject mobileContext(JSONObject account) {
        GuardianAccess access=new GuardianAccess(ledger,queries);
        GuardianEvents events=new GuardianEvents(guardian,access,mock(GuardianFiles.class));
        GuardianMobileController mobile=new GuardianMobileController(null,null,access,events,null,ledger);
        org.springframework.mock.web.MockHttpServletRequest request=new org.springframework.mock.web.MockHttpServletRequest();
        request.setAttribute("wearable.actor",account);
        return mobile.context("site-1",request);
    }

    @Test void newWearerCannotSeeTheFormerWearersLocalRecordingButOriginalObservationRemains() {
        state.getJSONArray("sites").getJSONObject(0).put("portalStation","S1");
        JSONObject newWearer=object("id","new-account","enabled",true,"personId","person-new","roleIds",JSONArray.of("self-role"));
        state.getJSONArray("accounts").add(newWearer);
        state.getJSONArray("roles").add(object("id","self-role","enabled",true,"grants",JSONArray.of(
                object("operations",JSONArray.of("self:read"),"siteIds",JSONArray.of("site-1")))));
        state.getJSONArray("people").add(object("id","person-new","portalId","NEW","siteId","site-1","enabled",true));
        state.getJSONArray("people").add(object("id","person-old","portalId","OLD","siteId","site-1","enabled",true));
        JSONObject observation=object("state","STOPPED","rawType","1","source","DIRECT_HELMET",
                "reportAct","toggle_localrecord","receivedAt","2026-11-02T01:00:00Z","timeBasis","RECEIVED_AT",
                "siteId","site-1","personId","OLD","personName","原领用人员");
        JSONObject remote=object("id","LOGIN-A","source","DIRECT_HELMET","station","S1","siteId","site-1","localRecording",observation);
        JSONObject snapshot=object("devices",JSONArray.of(remote),"people",JSONArray.of(object("id","NEW","station","S1")),
                "bindings",JSONArray.of(object("deviceId","LOGIN-A","personId","OLD","siteId","site-1","end","2026-11-02T01:01:00Z"),
                object("deviceId","LOGIN-A","personId","NEW","siteId","site-1","end",null)));
        when(guardian.snapshot()).thenReturn(snapshot);
        GuardianAccess access=new GuardianAccess(ledger,queries);
        JSONObject scoped=access.context(newWearer).snapshot(snapshot);
        assertEquals(1,scoped.getJSONArray("devices").size(),"new wearer may still see their currently issued device");
        assertFalse(scoped.getJSONArray("devices").getJSONObject(0).containsKey("localRecording"));
        assertFalse(mobileContext(newWearer).getJSONArray("devices").getJSONObject(0).containsKey("localRecording"));
        assertEquals(observation,mobileContext(actor).getJSONArray("devices").getJSONObject(0).get("localRecording"));
        assertEquals(observation,queries.query("area-editor","device",object("siteId","site-1","id","asset-A")).get("localRecording"));
        // An observation captured during this user's own issue is visible without assets:read.
        observation.put("personId","NEW");observation.put("personName","现领用人员");
        assertEquals(observation,mobileContext(newWearer).getJSONArray("devices").getJSONObject(0).get("localRecording"));
        observation.put("personId","OLD");observation.put("personName","原领用人员");
        assertEquals("OLD",remote.getJSONObject("localRecording").getString("personId"));
    }

    @Test void deviceManagementAndRemovedSnapshotEndpointCannotForgeLocalRecording() {
        GuardianHatArchive archive=mock(GuardianHatArchive.class);
        AdminDeviceService service=new AdminDeviceService(ledger,archive);
        ReflectionTestUtils.setField(service,"queries",queries);
        JSONObject forged=object("state","RECORDING","rawType","0","source","DIRECT_HELMET");
        for(String action:new String[]{"create","update","configure"}) {
            JSONObject data=object("localRecording",forged);
            JSONObject input=object("siteId","site-1","id","asset-A","expectedVersion",1,
                    "operationId","forge-"+action,"data",data);
            AdminQueryService.QueryFailed failed=assertThrows(AdminQueryService.QueryFailed.class,
                    ()->service.execute("area-editor","devices."+action,input));
            assertEquals(400,failed.code);
            assertTrue(failed.getMessage().contains("不能通过基础资料"));
        }
        verify(ledger,never()).write(any());verifyNoInteractions(archive);
        GuardianAccess access=new GuardianAccess(ledger,queries);
        GuardianController controller=new GuardianController(null,null,guardian,null,access,null);
        org.springframework.mock.web.MockHttpServletRequest request=new org.springframework.mock.web.MockHttpServletRequest();
        request.setAttribute("wearable.actor",actor);
        assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->controller.replace(
                object("devices",JSONArray.of(object("id","LOGIN-A","localRecording",forged))),0,request)).code);
        verify(guardian,never()).replaceScoped(any(),anyInt(),any());
    }

    @Test void legacyAreaScopeNowAllowsEveryDeviceInItsAuthorizedSite() {
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", "area-A"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", "area-B"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", null));
        assertFalse(queries.allows(state, actor, "events:read", "site-1", null));
        JSONObject input = object("siteId", "site-1", "source", "DIRECT_HELMET", "areaId", "area-A");
        List<JSONObject> rows = (List<JSONObject>) queries.query("area-editor", "devices", input).get("rows");
        assertEquals(3, rows.size(), "legacy area filters must not narrow site results");
        assertNotNull(queries.query("area-editor", "device", object("siteId", "site-1", "id", "asset-UNASSIGNED")));
        Map<String, Object> options = queries.query("area-editor", "deviceOptions", input);
        assertFalse(options.containsKey("areas"));
        assertFalse(options.containsKey("writableAreas"));
    }

    @Test void registrationNoLongerRequiresOrAssignsAnAdministrativeArea() {
        GuardianHatArchive archive = mock(GuardianHatArchive.class);
        AdminDeviceService service = new AdminDeviceService(ledger, archive);
        ReflectionTestUtils.setField(service, "queries", queries);
        JSONObject data = object("type", "HELMET", "source", "DIRECT_HELMET", "deviceNumber", "NEW-LOGIN",
                "code", "NEW-ASSET", "sn", "NEW-SERIAL", "name", "测试直连帽", "areaId", "retired-or-foreign-area");
        JSONObject input = object("siteId", "site-1", "operationId", "new-direct", "data", data);
        assertNull(service.execute("area-editor", "devices.create", input).getJSONObject("data").get("areaId"));
        verify(archive).ensureDirectUnassigned("NEW-LOGIN");
        input.put("siteId", "site-2");input.put("operationId", "foreign-direct");
        assertEquals(403, assertThrows(AdminQueryService.QueryFailed.class,
                () -> service.execute("area-editor", "devices.create", input)).code);
    }

    @Test void incompatibleLegacyAreaScopesDoNotRemoveSiteAccess() {
        grant.put("areaIds", JSONArray.of("area-B"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-1", null));
        state.put("areas", new JSONArray());
        assertEquals(3, ((List<?>) queries.query("area-editor", "devices", object("siteId", "site-1")).get("rows")).size());
        GuardianAccess.Context context = new GuardianAccess(ledger, queries).context(actor);
        assertTrue(context.can("assets:write", "site-1", null));
        assertFalse(context.can("assets:write", "site-2", null));
    }

    @Test void roleSitesOverrideLegacyAccountScopesAndRemainDynamic() {
        state.getJSONArray("sites").add(object("id", "site-2", "enabled", true));
        grant.put("siteIds", JSONArray.of("site-1", "site-2"));
        assertTrue(queries.allows(state, actor, "assets:read", "site-2", null));
        assertNotNull(queries.query("area-editor", "devices", object("siteId", "site-2")));
        GuardianAccess.Context context = new GuardianAccess(ledger, queries).context(actor);
        assertTrue(context.can("assets:read", "site-2", null));
        assertTrue(context.site("site-2"));
        assertTrue(actor.containsKey("roleScopes"), "reads must not rewrite legacy records");
        assertTrue(queries.allows(state, actor, "assets:read", "site-2", null));
        grant.put("siteIds", JSONArray.of("site-1"));
        assertFalse(queries.allows(state, actor, "assets:read", "site-2", null));
    }
}
