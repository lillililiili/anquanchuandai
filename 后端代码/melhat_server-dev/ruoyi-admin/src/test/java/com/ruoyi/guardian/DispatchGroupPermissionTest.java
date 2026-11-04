package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DispatchGroupPermissionTest {
    @TempDir Path directory;
    JSONObject role(String id,boolean builtin,String... operations) {
        return object("id",id,"builtin",builtin,"enabled",true,"version",1,"grants",JSONArray.of(
                object("siteIds",JSONArray.of("site-1"),"operations",JSONArray.of((Object[])operations))));
    }
    JSONArray operations(JSONObject role) { return role.getJSONArray("grants").getJSONObject(0).getJSONArray("operations"); }
    JSONObject master() {
        return object("sharedBusinessV2",true,"sites",JSONArray.of(
                object("id","site-1","portalStation","S1","enabled",true),object("id","site-2","portalStation","S2","enabled",true)),
                "people",JSONArray.of(object("id","person-1","portalId","P1","siteId","site-1","enabled",true),object("id","person-2","portalId","P2","siteId","site-2","enabled",true)),
                "accounts",JSONArray.of(object("id","duty-user","name","值守员","enabled",true,"roleIds",JSONArray.of("duty"))),
                "roles",JSONArray.of(role("duty",true,"people:read","events:read","communications:broadcast"),role("site",true,"people:read","events:read","communications:broadcast")));
    }
    @Test void upgradesOnlyBuiltInDispatchGrantsAndPreservesTheirSites() {
        JSONObject state=master();
        rows(state,"roles").add(role("custom-dispatch",false,"people:read","events:read","communications:broadcast"));
        rows(state,"roles").add(role("viewer",true,"people:read","events:read"));
        JSONObject scoped=object("siteIds",JSONArray.of("site-2"),"operations",JSONArray.of("people:read"));
        find(state,"roles","duty").getJSONArray("grants").add(scoped);
        assertTrue(migrate(state));
        for(String id:new String[]{"duty","site"}) {
            JSONObject r=find(state,"roles",id);assertTrue(operations(r).contains("groups:write"));assertEquals(2,r.getIntValue("version"));
            assertEquals(JSONArray.of("site-1"),r.getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds"));
        }
        assertFalse(operations(find(state,"roles","custom-dispatch")).contains("groups:write"));
        assertFalse(operations(find(state,"roles","viewer")).contains("groups:write"));
        assertFalse(scoped.getJSONArray("operations").contains("groups:write"));
        assertFalse(migrate(state));
        operations(find(state,"roles","duty")).remove("groups:write");
        assertFalse(migrate(state)); // A later explicit revocation must remain revoked.
    }
    @Test void customRoleReusingBuiltInIdIsNotGrantedPermissions() {
        JSONObject state=master();find(state,"roles","duty").put("builtin",false);migrate(state);
        assertFalse(operations(find(state,"roles","duty")).contains("groups:write"));
    }
    @Test void dutyCanCreateAndEditOfflineMembersButCannotCrossSitesOrMaintainFences() {
        JSONObject master=master();migrate(master);
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        GuardianStore store=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(store,"file",directory.resolve("groups.json"));
        JSONObject state=object("version",1,"seq",0,"people",JSONArray.of(
                object("id","P1","station","S1","active",true),object("id","P2","station","S2","active",true)));
        for(String key:new String[]{"stations","devices","works","events","media","fences","groups","bindings","calls","broadcasts","locations","vitals","audit"})state.put(key,new JSONArray());
        store.replace(state);GuardianBusinessCommands service=new GuardianBusinessCommands(store,access);JSONObject actor=object("id","duty-user");
        JSONObject input=object("type","groups.save","operationId","duty-group-create","expectedSeq",store.snapshot().getIntValue("seq"),"payload",object("station","S1","name","广播组","members",JSONArray.of("P1")));
        JSONObject created=service.execute(actor,input).getJSONObject("result");
        assertEquals(created.getString("id"),service.execute(actor,input).getJSONObject("result").getString("id"));
        input.put("expectedSeq",store.snapshot().getIntValue("seq"));input.put("operationId","duty-group-update");
        input.getJSONObject("payload").put("id",created.getString("id"));input.getJSONObject("payload").put("name","更新广播组");
        assertEquals("更新广播组",service.execute(actor,input).getJSONObject("result").getString("name"));
        input.put("expectedSeq",store.snapshot().getIntValue("seq"));input.put("operationId","duty-group-cross-site");
        input.getJSONObject("payload").remove("id");input.getJSONObject("payload").put("station","S2");input.getJSONObject("payload").put("members",JSONArray.of("P2"));
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,input)).code);
        input.getJSONObject("payload").put("station","S1");input.put("operationId","duty-group-cross-member");
        assertEquals(400,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,input)).code);
        input.put("type","fences.save");input.put("payload",object("fields",object("station","S1")));input.put("operationId","duty-fence-denied");
        assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,input)).code);
        assertEquals(1,store.snapshot().getJSONArray("groups").size());
    }
}
