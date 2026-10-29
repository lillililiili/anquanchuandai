package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Exercises real HTTP/Jackson deserialization rather than constructing Fastjson arrays in tests. */
class AdminAccessHttpTest {
    MockMvc http;AtomicReference<JSONObject> saved;AdminAccessService access;JSONObject actor;ObjectMapper json=new ObjectMapper();
    @BeforeEach void setup() throws Exception {
        JSONObject seed=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(),StandardCharsets.UTF_8));
        migrate(seed);saved=new AtomicReference<>(seed);actor=find(seed,"accounts","demo-system");
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);
        when(ledger.read()).thenAnswer(call->copy(saved.get()));
        doAnswer(call->{saved.set(copy(call.getArgument(0)));return null;}).when(ledger).write(any());
        access=spy(new AdminAccessService(ledger));
        AdminQueryService queries=new AdminQueryService(ledger,mock(GuardianStore.class),mock(ObjectProvider.class));
        AdminLedgerController controller=new AdminLedgerController(ledger,queries,mock(AdminDeviceService.class),
                mock(AdminAssignmentService.class),mock(AdminMaintenanceService.class),mock(AdminMasterService.class),access);
        http=MockMvcBuilders.standaloneSetup(controller).build();
    }
    Map<String,Object> map(Object... entries) {Map<String,Object> result=new LinkedHashMap<>();for(int i=0;i<entries.length;i+=2)result.put((String)entries[i],entries[i+1]);return result;}
    String send(String path,Object body,int code) throws Exception {
        return http.perform(post(path).requestAttr("wearable.actor",actor).contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsBytes(body)))
                .andExpect(status().is(code)).andReturn().getResponse().getContentAsString();
    }
    @Test void legacyAccountAreaListIsIgnoredWhileHttpPreviewPreservesSiteScope() throws Exception {
        JSONObject target=find(saved.get(),"accounts","demo-duty");AtomicBoolean arrayListSeen=new AtomicBoolean();
        doAnswer(call->{
            JSONObject input=call.getArgument(2);
            Object areas=input.getJSONObject("command").getJSONObject("data").getJSONArray("bindings").getJSONObject(0).get("areaIds");
            arrayListSeen.set(areas instanceof ArrayList);return call.callRealMethod();
        }).when(access).query(eq("demo-system"),eq("authorizationPreview"),any(JSONObject.class));
        Map<String,Object> command=map("operationId","http-area-update-001","siteId","site-1","id","demo-duty","expectedVersion",target.getIntValue("version"),
                "data",map("name",target.getString("name"),"loginName",target.getString("loginName"),"personId",null,
                        "bindings",Arrays.asList(map("roleId","duty","siteIds",Arrays.asList("site-1"),"areaIds",Arrays.asList("area-turbine")))));
        JSONObject preview=JSONObject.parseObject(send("/api/admin/v1/query",map("kind","authorizationPreview","input",map("siteId","site-1","type","accounts.update","command",command)),200));
        assertTrue(arrayListSeen.get(),"HTTP body must reproduce the actual ArrayList shape");
        command.put("previewId",preview.getJSONObject("data").getString("previewId"));
        send("/api/admin/v1/execute",map("type","accounts.update","input",command),200);
        assertFalse(preview.getJSONObject("data").getBooleanValue("required"));
        assertFalse(find(saved.get(),"accounts","demo-duty").containsKey("roleScopes"));
    }
    @Test void roleHttpNeedsOperationsAndSitesWithoutAdministrativeAreas() throws Exception {
        Map<String,Object> data=map("name","厂站验收角色","operations",Arrays.asList("events:read"),"siteIds",Arrays.asList("site-1"));
        Map<String,Object> command=map("operationId","http-role-create-001","siteId","site-1","data",data);
        JSONObject created=JSONObject.parseObject(send("/api/admin/v1/execute",map("type","roles.create","input",command),200)).getJSONObject("data");
        assertFalse(created.getJSONArray("grants").getJSONObject(0).containsKey("areaIds"));
        assertEquals(Collections.singletonList("site-1"),created.getJSONArray("grants").getJSONObject(0).getJSONArray("siteIds"));
        command.put("operationId","http-role-legacy-001");data.put("areaIds",Arrays.asList("retired-area"));
        send("/api/admin/v1/execute",map("type","roles.create","input",command),200);
        command.put("operationId","http-role-unknown-site-001");data.put("siteIds",Arrays.asList("unknown-site"));
        send("/api/admin/v1/execute",map("type","roles.create","input",command),400);
    }

    @Test void accountsCanBindARoleUsingOnlyRoleIdAndAreaEndpointsAreRetired() throws Exception {
        JSONObject created=createAccount("site-only-user",Collections.singletonList(map("roleId","duty")));
        assertFalse(created.containsKey("roleScopes"));
        assertFalse(created.toJSONString().contains("areaIds"));
        send("/api/admin/v1/execute",map("type","areas.create","input",map("siteId","site-1")),410);
        send("/api/admin/v1/query",map("kind","master","input",map("entity","areas","siteId","site-1")),410);
    }

    Map<String,Object> deleteCommand(String id) {
        JSONObject row=find(saved.get(),"accounts",id);
        return map("operationId","delete-"+id,"siteId",row.getString("siteId"),"id",id,"expectedVersion",row.getIntValue("version"));
    }
    @Test void deletingAccountPreservesBusinessRecordsClearsPersonLinkAndReplaysOnce() throws Exception {
        JSONObject target=find(saved.get(),"accounts","demo-duty");
        JSONObject person=rows(saved.get(),"people").getJSONObject(0);
        person.put("accountId",target.getString("id"));target.put("personId",person.getString("id"));
        int personVersion=person.getIntValue("version"), auditCount=rows(saved.get(),"audit").size();
        String roles=rows(saved.get(),"roles").toJSONString(), devices=rows(saved.get(),"devices").toJSONString();
        String assignments=rows(saved.get(),"assignments").toJSONString();
        Map<String,Object> command=deleteCommand("demo-duty");
        String response=send("/api/admin/v1/execute",map("type","accounts.delete","input",command),200);
        JSONObject result=JSONObject.parseObject(response).getJSONObject("data");
        assertTrue(result.getBooleanValue("deleted"));assertFalse(result.containsKey("passwordHash"));
        assertNull(find(saved.get(),"accounts","demo-duty"));
        JSONObject retained=find(saved.get(),"people",person.getString("id"));
        assertNotNull(retained);assertNull(retained.get("accountId"));assertEquals(personVersion+1,retained.getIntValue("version"));
        assertEquals(person.getBooleanValue("enabled"),retained.getBooleanValue("enabled"));
        assertEquals(roles,rows(saved.get(),"roles").toJSONString());assertEquals(devices,rows(saved.get(),"devices").toJSONString());
        assertEquals(assignments,rows(saved.get(),"assignments").toJSONString());
        assertEquals(auditCount+1,rows(saved.get(),"audit").size());
        JSONObject audit=rows(saved.get(),"audit").getJSONObject(auditCount);
        assertEquals("accounts.delete",audit.getString("action"));assertEquals("demo-duty",audit.getString("objectId"));
        assertTrue(audit.getJSONObject("after").getBooleanValue("deleted"));
        assertFalse(audit.toJSONString().contains("passwordHash"));
        String replay=send("/api/admin/v1/execute",map("type","accounts.delete","input",command),200);
        assertEquals(JSONObject.parseObject(response),JSONObject.parseObject(replay));assertEquals(auditCount+1,rows(saved.get(),"audit").size());
        assertEquals(401,assertThrows(AdminQueryService.QueryFailed.class,()->access.query("demo-duty","audit",object("siteId","site-1"))).code);
    }
    @Test void accountDeletionEnforcesVersionScopeAndProtectedIdentities() throws Exception {
        String baseline=saved.get().toJSONString();Map<String,Object> command=deleteCommand("demo-duty");
        command.put("expectedVersion",0);
        send("/api/admin/v1/execute",map("type","accounts.delete","input",command),409);
        command=deleteCommand("demo-duty");command.put("siteId","site-2");
        send("/api/admin/v1/execute",map("type","accounts.delete","input",command),404);
        send("/api/admin/v1/execute",map("type","accounts.delete","input",deleteCommand("demo-system")),403);
        actor=find(saved.get(),"accounts","demo-site");
        send("/api/admin/v1/execute",map("type","accounts.delete","input",deleteCommand("demo-site")),403);
        actor=find(saved.get(),"accounts","demo-audit");
        send("/api/admin/v1/execute",map("type","accounts.delete","input",deleteCommand("demo-duty")),403);
        assertEquals(baseline,saved.get().toJSONString());
    }
    @Test void onlyOpenAssignedMaintenanceBlocksAccountDeletionAndAppearsInImpacts() throws Exception {
        rows(saved.get(),"maintenanceOrders").add(object("id","open-order","code","R-01","handlerId","demo-duty","status","OPEN"));
        rows(saved.get(),"maintenanceOrders").add(object("id","closed-order","handlerId","demo-duty","status","CLOSED"));
        rows(saved.get(),"maintenanceOrders").add(object("id","other-order","handlerId","demo-asset","status","OPEN"));
        int orderCount=rows(saved.get(),"maintenanceOrders").size();
        Map<String,Object> impactInput=map("siteId","site-1","entity","accounts","id","demo-duty","all",true);
        JSONObject impacts=JSONObject.parseObject(send("/api/admin/v1/query",map("kind","impacts","input",impactInput),200)).getJSONObject("data");
        assertEquals(1,impacts.getJSONArray("rows").size());assertEquals("open-order",impacts.getJSONArray("rows").getJSONObject(0).getString("id"));
        impactInput.put("all",false);
        assertTrue(JSONObject.parseObject(send("/api/admin/v1/query",map("kind","impacts","input",impactInput),200)).getJSONObject("data").getJSONArray("rows").isEmpty());
        Map<String,Object> command=deleteCommand("demo-duty");String baseline=saved.get().toJSONString();
        JSONObject blocked=JSONObject.parseObject(send("/api/admin/v1/execute",map("type","accounts.delete","input",command),409));
        assertEquals("REFERENCED",blocked.getString("errorCode"));assertEquals(baseline,saved.get().toJSONString());
        find(saved.get(),"maintenanceOrders","open-order").put("status","CLOSED");
        send("/api/admin/v1/execute",map("type","accounts.delete","input",command),200);
        assertNull(find(saved.get(),"accounts","demo-duty"));assertEquals(orderCount,rows(saved.get(),"maintenanceOrders").size());
    }
    @Test void deletionReplayStillRequiresCurrentAccountManagementPermission() throws Exception {
        JSONObject target=copy(find(saved.get(),"accounts","demo-duty"));
        target.put("id","custom-account");target.put("builtin",false);rows(target,"roleIds").clear();target.put("roleScopes",new JSONObject());
        rows(saved.get(),"accounts").add(target);actor=find(saved.get(),"accounts","demo-site");
        Map<String,Object> command=deleteCommand("custom-account");
        send("/api/admin/v1/execute",map("type","accounts.delete","input",command),200);
        rows(find(saved.get(),"accounts","demo-site"),"roleIds").clear();
        send("/api/admin/v1/execute",map("type","accounts.delete","input",command),403);
    }

    Map<String,Object> binding(String roleId) {
        return map("roleId",roleId);
    }
    Map<String,Object> createAccountCommand(String loginName,Object bindings) {
        return map("operationId","create-"+loginName,"siteId","site-1",
                "relatedVersions",map("duty",find(saved.get(),"roles","duty").getIntValue("version"),"audit",find(saved.get(),"roles","audit").getIntValue("version")),
                "data",map("name",loginName,"loginName",loginName,"password","SingleRole@2026","bindings",bindings));
    }
    JSONObject createAccount(String loginName,Object bindings) throws Exception {
        return JSONObject.parseObject(send("/api/admin/v1/execute",map("type","accounts.create","input",createAccountCommand(loginName,bindings)),200)).getJSONObject("data");
    }
    @Test void multipleUsersCanBeCreatedWithTheSameSingleRoleAndUnassignedIsAllowed() throws Exception {
        JSONObject first=createAccount("role-user-one",Collections.singletonList(binding("duty")));
        JSONObject second=createAccount("role-user-two",Collections.singletonList(binding("duty")));
        assertNotEquals(first.getString("id"),second.getString("id"));
        for (JSONObject account:Arrays.asList(first,second)) {
            assertEquals(Collections.singletonList("duty"),account.getJSONArray("roleIds"));
            assertFalse(account.containsKey("roleScopes"));
        }
        JSONObject unassigned=createAccount("role-user-unassigned",Collections.emptyList());
        assertTrue(unassigned.getJSONArray("roleIds").isEmpty());assertFalse(unassigned.containsKey("roleScopes"));
    }
    @Test void changingSingleRoleRequiresPreviewAndReplacesThePreviousBinding() throws Exception {
        JSONObject account=createAccount("role-user-rebind",Collections.singletonList(binding("duty")));
        Map<String,Object> command=map("operationId","rebind-single-role","siteId","site-1","id",account.getString("id"),"expectedVersion",account.getIntValue("version"),
                "relatedVersions",map("audit",find(saved.get(),"roles","audit").getIntValue("version")),
                "data",map("name",account.getString("name"),"loginName",account.getString("loginName"),"bindings",Collections.singletonList(binding("audit"))));
        send("/api/admin/v1/execute",map("type","accounts.update","input",command),409);
        JSONObject preview=JSONObject.parseObject(send("/api/admin/v1/query",map("kind","authorizationPreview","input",map("siteId","site-1","type","accounts.update","command",command)),200)).getJSONObject("data");
        assertTrue(preview.getBooleanValue("required"));command.put("previewId",preview.getString("previewId"));
        send("/api/admin/v1/execute",map("type","accounts.update","input",command),200);
        JSONObject updated=find(saved.get(),"accounts",account.getString("id"));
        assertEquals(Collections.singletonList("audit"),updated.getJSONArray("roleIds"));
        assertFalse(updated.containsKey("roleScopes"));
    }
    @Test void multipleRoleBindingsAreRejectedOnBothCreateAndUpdateWithoutMutation() throws Exception {
        List<Map<String,Object>> multiple=Arrays.asList(binding("duty"),binding("audit"));
        String baseline=saved.get().toJSONString();
        send("/api/admin/v1/execute",map("type","accounts.create","input",createAccountCommand("too-many-roles",multiple)),400);
        JSONObject target=find(saved.get(),"accounts","demo-duty");
        Map<String,Object> command=map("operationId","update-too-many-roles","siteId","site-1","id","demo-duty","expectedVersion",target.getIntValue("version"),
                "data",map("name",target.getString("name"),"loginName",target.getString("loginName"),"bindings",multiple));
        send("/api/admin/v1/execute",map("type","accounts.update","input",command),400);
        send("/api/admin/v1/query",map("kind","authorizationPreview","input",map("siteId","site-1","type","accounts.update","command",command)),400);
        assertEquals(baseline,saved.get().toJSONString());
    }
    @Test void malformedAccountRolePayloadsReturnValidationErrorsInsteadOfServerErrors() throws Exception {
        String baseline=saved.get().toJSONString();int serial=0;
        for(Object malformed:Arrays.<Object>asList(null,false,"bad",map("roleId","duty"),Collections.singletonList(null),Collections.singletonList("duty"),Collections.singletonList(Collections.emptyList()),
                Collections.singletonList(map("roleId",7)),Collections.singletonList(map("roleId"," ")))) {
            JSONObject result=JSONObject.parseObject(send("/api/admin/v1/execute",map("type","accounts.create","input",createAccountCommand("malformed-"+(serial++),malformed)),400));
            assertEquals("VALIDATION_ERROR",result.getString("errorCode"));
        }
        Map<String,Object> command=createAccountCommand("malformed-data",Collections.emptyList());command.put("data","bad");
        send("/api/admin/v1/execute",map("type","accounts.create","input",command),400);
        command=createAccountCommand("malformed-versions",Collections.singletonList(binding("duty")));command.put("relatedVersions","bad");
        send("/api/admin/v1/execute",map("type","accounts.create","input",command),400);
        assertEquals(baseline,saved.get().toJSONString());
    }
    @Test void singleRoleCreationStillChecksRoleVersionAndGrantedScope() throws Exception {
        Map<String,Object> command=createAccountCommand("stale-role",Collections.singletonList(binding("duty")));
        command.put("relatedVersions",map("duty",0));
        send("/api/admin/v1/execute",map("type","accounts.create","input",command),409);
        find(saved.get(),"roles","duty").getJSONArray("grants").getJSONObject(0).put("siteIds",Collections.singletonList("unknown-site"));
        send("/api/admin/v1/execute",map("type","accounts.create","input",createAccountCommand("invalid-role-scope",Collections.singletonList(binding("duty")))),400);
        actor=find(saved.get(),"accounts","demo-site");
        send("/api/admin/v1/execute",map("type","accounts.create","input",createAccountCommand("undelegatable-role",Collections.singletonList(binding("duty")))),400);
    }
    @Test void fullSiteRoleCreationCannotDelegateOperationsTheActorDoesNotHave() throws Exception {
        rows(saved.get(),"roles").add(object("id","account-maintainer-role","enabled",true,"version",1,
                "grants",Collections.singletonList(object("operations",Collections.singletonList("accounts:write"),"siteIds",Collections.singletonList("site-1"),"areaIds","*"))));
        actor=object("id","account-maintainer","siteId","site-1","enabled",true,"roleIds",Collections.singletonList("account-maintainer-role"));
        rows(saved.get(),"accounts").add(actor);
        Map<String,Object> viewer=binding("viewer");viewer.put("areaIds","*");
        String baseline=saved.get().toJSONString();
        send("/api/admin/v1/execute",map("type","accounts.create","input",createAccountCommand("too-broad-viewer",Collections.singletonList(viewer))),400);
        assertEquals(baseline,saved.get().toJSONString());
        rows(find(saved.get(),"roles","account-maintainer-role"),"grants").add(object(
                "operations",rows(find(saved.get(),"roles","viewer"),"grants").getJSONObject(0).getJSONArray("operations"),
                "siteIds",Collections.singletonList("site-1"),"areaIds",Collections.singletonList("area-turbine")));
        createAccount("delegated-site-viewer",Collections.singletonList(binding("viewer")));
        actor=find(saved.get(),"accounts","demo-site");
        createAccount("delegated-viewer",Collections.singletonList(viewer));
    }
}
