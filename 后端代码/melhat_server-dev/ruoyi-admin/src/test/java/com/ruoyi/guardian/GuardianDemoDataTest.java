package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class GuardianDemoDataTest {
    @TempDir Path directory;
    JSONObject master, actor;
    GuardianStore store;
    GuardianAccess access;
    GuardianEvents events;
    AdminQueryService queries;
    AdminMasterService masters;
    MockMvc http;

    private JSONObject seed(String resource) throws Exception {
        return JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource(resource).getInputStream(), StandardCharsets.UTF_8));
    }
    @BeforeEach void setup() throws Exception {
        master=seed("admin-seed.json");migrate(master);actor=find(master,"accounts","demo-system");
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(call->copy(master));
        store=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(store,"file",directory.resolve("guardian-state.json"));
        queries=new AdminQueryService(ledger,store,null);masters=new AdminMasterService(ledger,store,queries);
        access=new GuardianAccess(ledger,queries);
        GuardianFiles files=new GuardianFiles();ReflectionTestUtils.setField(files,"root",directory.resolve("photos"));
        events=new GuardianEvents(store,access,files);
        JSONObject state=seed("guardian-seed.json");GuardianMasterProjection.apply(state,master);store.replace(state);
        GuardianController pc=new GuardianController(null,null,store,events,access,null);
        GuardianMobileController mobile=new GuardianMobileController(null,null,access,events,null,ledger);
        http=MockMvcBuilders.standaloneSetup(pc,mobile).setControllerAdvice(new GuardianError()).build();
    }
    private JSONObject read(String path) throws Exception {
        return JSONObject.parseObject(http.perform(get(path).requestAttr("wearable.actor",actor)).andExpect(status().isOk()).andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
    private Set<String> ids(JSONArray records) {
        Set<String> result=new HashSet<>();for(Object raw:records)result.add(((JSONObject)raw).getString("id"));return result;
    }
    private void addRealRecords() throws Exception {
        JSONObject event=copy(seed("guardian-seed.json").getJSONArray("events").getJSONObject(0));event.put("id","historic-no-source");
        JSONObject device=copy(event);device.put("id","real-device");device.put("source","DEVICE");device.put("protocol","direct-helmet");device.put("sourceRecordId",9123);
        JSONObject work=copy(seed("guardian-seed.json").getJSONArray("works").getJSONObject(0));work.put("id","historic-work");work.remove("source");
        store.update(state->{rows(state,"events").add(event);rows(state,"events").add(device);rows(state,"works").add(work);return true;});
    }

    @Test void onlyExactSeedIdentityIsMarkedAndReviewEvidenceSurvivesRestart() throws Exception {
        JSONObject state=seed("guardian-seed.json");
        JSONObject reviewed=rows(state,"events").getJSONObject(0);reviewed.put("source","device");reviewed.put("status","已核验");
        JSONObject verification=object("conclusion","设备通信异常","situation","保留现场核验原文","actorId","reviewer");reviewed.put("verification",verification);
        rows(reviewed,"timeline").add(object("text","后来人工核验","actorId","reviewer"));String timeline=rows(reviewed,"timeline").toJSONString();
        JSONObject explicit=rows(state,"events").getJSONObject(1);explicit.put("source","DEVICE");
        JSONObject backed=rows(state,"events").getJSONObject(2);backed.put("protocol","direct-helmet");backed.put("sourceRecordId",33);
        JSONObject changed=rows(state,"events").getJSONObject(3);changed.put("title","同编号但属于真实历史的求助");
        JSONObject changedWork=rows(state,"works").getJSONObject(0);changedWork.put("date","2026-10-23");
        store.replace(state);JSONObject saved=store.snapshot();
        JSONObject marked=rows(saved,"events").getJSONObject(0);
        assertTrue(GuardianDemoData.confirmed(marked));assertEquals("device",marked.getJSONObject("seedProvenance").getString("originalSource"));
        assertEquals(verification,marked.getJSONObject("verification"));assertEquals(timeline,rows(marked,"timeline").toJSONString());assertEquals("已核验",marked.getString("status"));
        assertFalse(GuardianDemoData.confirmed(rows(saved,"events").getJSONObject(1)));assertEquals("DEVICE",rows(saved,"events").getJSONObject(1).getString("source"));
        assertFalse(GuardianDemoData.confirmed(rows(saved,"events").getJSONObject(2)));assertFalse(GuardianDemoData.confirmed(rows(saved,"events").getJSONObject(3)));
        assertEquals("unknown",rows(saved,"events").getJSONObject(3).getString("source"));assertFalse(GuardianDemoData.confirmed(rows(saved,"works").getJSONObject(0)));
        assertEquals(7,rows(saved,"events").size());assertEquals(3,rows(saved,"works").size());
        GuardianStore restarted=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(restarted,"file",directory.resolve("guardian-state.json"));
        assertEquals(marked,rows(restarted.snapshot(),"events").getJSONObject(0));
        assertFalse(GuardianEvents.normalize(saved),"Provenance migration must be idempotent");
    }

    @Test void pcMobileAndListExcludeSeedButKeepUnknownHistoryAndRealDeviceEvents() throws Exception {
        addRealRecords();Set<String> expected=new HashSet<>(Arrays.asList("historic-no-source","real-device"));
        JSONObject pc=read("/api/guardian/v1/snapshot").getJSONObject("state"),mobile=read("/api/guardian/v1/mobile/context?siteId=site-1");
        assertEquals(expected,ids(rows(pc,"events")));assertEquals(expected,ids(rows(mobile,"events")));
        assertEquals(Collections.singleton("historic-work"),ids(rows(pc,"works")));assertEquals(ids(rows(pc,"works")),ids(rows(mobile,"works")));
        assertEquals(expected,ids(read("/api/guardian/v1/events?siteId=site-1").getJSONArray("rows")));
        JSONObject home=read("/api/guardian/v1/mobile/home?siteId=site-1");assertEquals(2,home.getJSONObject("counts").getIntValue("pendingEvents"));assertEquals(1,home.getJSONObject("counts").getIntValue("works"));
        assertFalse(pc.getBooleanValue("demoMode"));assertNull(pc.get("sos"));assertTrue(pc.getJSONObject("assistance").isEmpty());
        assertEquals(9,rows(store.snapshot(),"events").size());assertEquals(4,rows(store.snapshot(),"works").size());
        JSONObject unknown=find(pc,"events","historic-no-source");assertEquals("unknown",unknown.getString("source"));
        assertEquals("DEVICE",find(pc,"events","real-device").getString("source"));
        JSONObject archived=read("/api/guardian/v1/events/RL-E-0915-001");assertTrue(GuardianDemoData.confirmed(archived));assertFalse(rows(archived,"timeline").isEmpty());
    }

    @Test void archivedReviewPhotoRemainsReadableOnlyUnderOriginalEventPermission() throws Exception {
        String blob="upload-11111111-1111-4111-8111-111111111111";
        byte[] png=new byte[]{(byte)137,80,78,71,13,10,26,10};Files.createDirectories(directory.resolve("photos"));Files.write(directory.resolve("photos").resolve(blob+".png"),png);
        store.update(state->{rows(state,"media").add(object("id","review-photo","blobId",blob,"eventId","RL-E-0915-001","personId","P1","source","核验上传"));return true;});
        assertArrayEquals(png,events.file(actor,blob).bytes);
        JSONObject foreign=object("id","limited","enabled",true,"personId","person-1-1","roleIds",JSONArray.parseArray("[\"mobile-user\"]"));rows(master,"accounts").add(foreign);
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->events.file(foreign,blob)).code);
        assertFalse(ids(rows(events.snapshot(actor),"media")).contains("review-photo"));
    }

    @Test void explicitDemoModeRestoresSeedAcrossTheSameReadModels() throws Exception {
        ReflectionTestUtils.setField(access,"demoMode",true);ReflectionTestUtils.setField(store,"demoMode",true);
        JSONObject pc=read("/api/guardian/v1/snapshot").getJSONObject("state"),mobile=read("/api/guardian/v1/mobile/context?siteId=site-1");
        assertTrue(pc.getBooleanValue("demoMode"));assertEquals(7,rows(pc,"events").size());assertEquals(3,rows(pc,"works").size());
        assertEquals(ids(rows(pc,"events")),ids(rows(mobile,"events")));assertEquals(7,read("/api/guardian/v1/events").getIntValue("total"));
        assertEquals(3,read("/api/guardian/v1/mobile/home?siteId=site-1").getJSONObject("counts").getIntValue("works"));
        assertTrue(rows(pc,"events").stream().allMatch(raw->GuardianDemoData.confirmed((JSONObject)raw)));
        assertTrue((Boolean)ReflectionTestUtils.invokeMethod(masters,"openWork",find(master,"people","person-1-0")));
    }

    @Test void realModeKeepsOneWatchSimulationAcrossThreeClientsAndItsCurrentWearerVitals() throws Exception {
        JSONObject pc=read("/api/guardian/v1/snapshot").getJSONObject("state"),mobile=read("/api/guardian/v1/mobile/context?siteId=site-1");
        assertEquals(Collections.singleton("RL-W001"), ids(rows(pc,"devices")));
        assertEquals(1, rows(mobile,"devices").size());
        assertTrue(ids(rows(pc,"devices")).containsAll(ids(rows(mobile,"devices"))));
        assertTrue(rows(pc,"devices").stream().allMatch(raw -> "DEMO_WATCH".equals(((JSONObject)raw).getString("source"))));
        assertTrue(rows(mobile,"devices").stream().allMatch(raw -> "DEMO_WATCH".equals(((JSONObject)raw).getString("source"))));
        assertTrue(rows(pc,"vitals").stream().allMatch(raw -> ((JSONObject)raw).getBooleanValue("demo") && "DEMO_WATCH".equals(((JSONObject)raw).getString("source"))));
        assertEquals(1, rows(pc,"vitals").size());assertEquals("RL-W001",rows(pc,"vitals").getJSONObject(0).getString("deviceId"));
        assertEquals("P1",rows(pc,"vitals").getJSONObject(0).getString("personId"));
        Set<String> deviceIds=ids(rows(pc,"devices"));
        assertTrue(rows(pc,"bindings").stream().allMatch(raw -> deviceIds.contains(((JSONObject)raw).getString("deviceId"))));
        JSONObject admin=JSONObject.parseObject(JSONObject.toJSONString(queries.query("demo-system","devices",object("siteId","site-1","pageSize",100))));
        assertEquals(1, admin.getIntValue("total"));
        assertTrue(rows(admin,"rows").stream().allMatch(raw -> "DEMO_WATCH".equals(((JSONObject)raw).getString("source"))));
        assertEquals(35, rows(store.snapshot(),"devices").size(), "Durable history is not deleted");
        assertEquals(35, rows(master,"devices").size(), "Reading must not mutate the authoritative ledger");
    }

    @Test void realWatchAndVitalsAreNotHiddenAndReturnedSampleWatchStopsShowingSeedVitals() throws Exception {
        JSONObject real=find(master,"devices","RL-W002");real.put("source","DEVICE");real.put("manufacturer","真实厂家");
        store.update(state->{
            GuardianMasterProjection.apply(state,master);
            JSONObject vital=rows(state,"vitals").getJSONObject(1);vital.put("source","DEVICE");vital.remove("demo");vital.remove("dataOrigin");
            return true;
        });
        JSONObject visible=read("/api/guardian/v1/snapshot").getJSONObject("state");
        assertEquals(new HashSet<>(Arrays.asList("RL-W001","RL-W002")),ids(rows(visible,"devices")));
        assertFalse(find(visible,"devices","RL-W002").getBooleanValue("demo"));assertEquals(2,rows(visible,"vitals").size());
        JSONObject returned=find(master,"assignments","assignment-RL-W001");returned.put("active",false);
        store.update(state->{GuardianMasterProjection.apply(state,master);return true;});
        visible=read("/api/guardian/v1/snapshot").getJSONObject("state");
        assertEquals(1,rows(visible,"vitals").size());assertEquals("DEVICE",rows(visible,"vitals").getJSONObject(0).getString("source"));
    }

    @Test void matchingIdsOrModelsDoNotHideRegisteredOrEditedRealAssets() {
        JSONObject modified=copy(find(master,"devices","RL-H001"));modified.put("manufacturer","实际厂家");
        JSONObject registered=copy(find(master,"devices","RL-B001"));registered.put("source","DIRECT_BELT");
        JSONObject manual=copy(find(master,"devices","RL-H002"));manual.put("id","new-manual");
        JSONObject imported=copy(find(master,"devices","RL-H003"));imported.put("protocol","real-import");
        for(JSONObject row:Arrays.asList(modified, registered, manual, imported)) assertFalse(GuardianDemoData.seedAsset(row));
        JSONObject state=copy(master);state.put("devices",JSONArray.of(modified,registered,manual,imported));
        assertEquals(4,rows(GuardianDemoData.operationalLedger(state,false),"devices").size());
        JSONObject explicit=GuardianDemoData.operationalLedger(master,true);
        assertEquals(35,rows(explicit,"devices").size());
        assertTrue(GuardianDemoData.confirmed(find(explicit,"devices","RL-H001")));
    }

    @Test void registeringFormerSeedAssetClearsItsSimulationWithoutReusingMockTelemetry() throws Exception {
        find(master,"devices","RL-H001").put("manufacturer","真实厂家");
        store.update(state->{GuardianMasterProjection.apply(state,master);return true;});
        JSONObject pc=read("/api/guardian/v1/snapshot").getJSONObject("state"),device=find(pc,"devices","RL-H001");
        assertNotNull(device);assertFalse(device.getBooleanValue("demo"));assertEquals("ASSET",device.getString("source"));
        assertNull(device.get("online"));assertNull(device.get("battery"));assertNull(device.get("updated"));
    }

    @Test void rejectedFilteredSnapshotPreservesArchivedSeedAndCannotAddOrRemoveFence() throws Exception {
        JSONObject archived=store.snapshot();
        JSONObject visible=read("/api/guardian/v1/snapshot").getJSONObject("state");
        JSONObject expectedVisible=access.context(actor).snapshot(store.snapshot());
        for(String key:Arrays.asList("events","assistance","sos","works","stations","people","devices","bindings","mapAreas","platformSync","vitals","locations"))
            assertEquals(expectedVisible.get(key),visible.get(key),"HTTP round trip: "+key);
        assertTrue(rows(visible,"fences").isEmpty());assertTrue(rows(visible,"media").isEmpty());
        JSONObject fence=copy(rows(archived,"fences").getJSONObject(0));
        fence.put("id","real-fence");fence.put("name","真实围栏");fence.remove("demo");fence.remove("dataOrigin");fence.remove("seedProvenance");fence.put("source","MANUAL");
        rows(visible,"fences").add(fence);int revision=visible.getIntValue("seq");visible.put("seq",revision+1);
        http.perform(put("/api/guardian/v1/snapshot").requestAttr("wearable.actor",actor).header("X-Wearable-Revision",revision)
                .contentType("application/json").content(visible.toJSONString())).andExpect(status().isGone());
        JSONObject saved=store.snapshot();
        for(String collection:Arrays.asList("devices","bindings","events","works","media","fences")) assertEquals(archived.get(collection),saved.get(collection));
        assertEquals(archived.getIntValue("seq"),saved.getIntValue("seq"));
        visible=read("/api/guardian/v1/snapshot").getJSONObject("state");assertTrue(rows(visible,"fences").isEmpty());
        visible.put("fences",new JSONArray());revision=visible.getIntValue("seq");visible.put("seq",revision+1);
        http.perform(put("/api/guardian/v1/snapshot").requestAttr("wearable.actor",actor).header("X-Wearable-Revision",revision)
                .contentType("application/json").content(visible.toJSONString())).andExpect(status().isGone());
        assertEquals(archived.get("fences"),store.snapshot().get("fences"));
    }

    @Test void administrativeAreasAreRetiredWhileIndependentFenceGeometryIsPreserved() {
        String previous=master.toJSONString();
        for(String action:Arrays.asList("create","update","status","delete")) {
            assertEquals(410,assertThrows(AdminQueryService.QueryFailed.class,()->masters.execute("demo-system","areas."+action,
                    object("siteId","site-1","operationId","retired-"+action,"data",object("name","区域")))).code);
        }
        assertEquals(previous,master.toJSONString());
        ReflectionTestUtils.setField(access,"demoMode",true);
        JSONObject before=store.snapshot(),visible=access.context(actor).snapshot(before);
        assertFalse(visible.containsKey("mapAreas"));
        for(Object raw:rows(visible,"people")) {JSONObject person=(JSONObject)raw;assertFalse(person.containsKey("area"));assertFalse(person.containsKey("areaId"));}
        assertEquals(before.getJSONArray("fences"),visible.getJSONArray("fences"));
        JSONObject created=masters.execute("demo-system","organizations.create",object("siteId","site-1","operationId","org-without-region",
                "data",object("name","新班组","code","no-region","areaId","retired-region"))).getJSONObject("data");
        assertNull(created.get("areaId"));
        assertFalse(store.snapshot().containsKey("mapAreas"));
        assertEquals(before.getJSONArray("fences"),store.snapshot().getJSONArray("fences"));
    }

    @Test void seedWorkDoesNotBlockAdministrationOrCaptureRealDeviceAlarmOwnership() throws Exception {
        JSONObject person=find(master,"people","person-1-0"),state=store.snapshot();
        assertFalse((Boolean)ReflectionTestUtils.invokeMethod(masters,"openWork",person));
        JSONObject impact=JSONObject.parseObject(JSONObject.toJSONString(queries.query("demo-system","impacts",object("entity","people","siteId","site-1","id",person.getString("id")))));
        assertFalse(impact.toJSONString().contains("GL-20260915-018"));
        assertNull(ReflectionTestUtils.invokeMethod(GuardianIngest.class,"currentWork",state,"P1","2026-09-15"));
        addRealRecords();
        assertTrue((Boolean)ReflectionTestUtils.invokeMethod(masters,"openWork",person));
        JSONObject work=ReflectionTestUtils.invokeMethod(GuardianIngest.class,"currentWork",store.snapshot(),"P1","2026-09-15");assertEquals("historic-work",work.getString("id"));
        impact=JSONObject.parseObject(JSONObject.toJSONString(queries.query("demo-system","impacts",object("entity","people","siteId","site-1","id",person.getString("id")))));
        assertTrue(impact.toJSONString().contains("historic-work"));assertFalse(impact.toJSONString().contains("GL-20260915-018"));
    }

    @Test void realWorkValidationSkipsOnlyConfirmedSeedAndRetainsRealConflictChecks() throws Exception {
        addRealRecords();
        store.update(state->{find(state,"works","historic-work").put("name","更新真实历史作业");return true;});
        assertEquals("更新真实历史作业",find(store.snapshot(),"works","historic-work").getString("name"));
        assertThrows(IllegalArgumentException.class,()->store.update(state->{
            JSONObject duplicate=copy(find(state,"works","historic-work"));duplicate.put("id","real-overlap");
            rows(state,"works").add(duplicate);return true;
        }),"An unknown-origin live work must still reserve its participants");
        assertNull(find(store.snapshot(),"works","real-overlap"));
        JSONObject fullImport=seed("guardian-seed.json");
        JSONObject real=copy(rows(fullImport,"works").getJSONObject(0));real.put("id","imported-real-work");real.remove("source");rows(fullImport,"works").add(real);
        assertDoesNotThrow(()->store.replace(fullImport),"Legacy seeds must be identified before full-import validation");
        ReflectionTestUtils.setField(store,"demoMode",true);
        assertThrows(IllegalArgumentException.class,()->store.update(state->{state.put("clock",state.getIntValue("clock")+1);return true;}),
                "Explicit demo mode includes demo work in the same conflict checks as its read model");
    }
}
