package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.helmet.service.DirectHelmetAccess;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianGeographicFenceTest {
    @TempDir Path directory;
    GuardianStore store;
    GuardianIngest ingest;
    JSONObject status;

    @BeforeEach void setup() {
        store=new GuardianStore(mock(GuardianHatArchive.class));
        ReflectionTestUtils.setField(store,"file",directory.resolve("state.json"));
        JSONObject state=object("version",1,"seq",0,"stations",JSONArray.of(object("id","station-a","name","隔离厂站")),
                "people",JSONArray.of(object("id","person-a","name","验收人员","active",true,"siteId","site-a","station","station-a")),
                "devices",JSONArray.of(object("id","helmet-a","type","H","source","DIRECT_HELMET","active",true,"siteId","site-a","station","station-a")),
                "bindings",JSONArray.of(object("id","binding-a","deviceId","helmet-a","personId","person-a","start","2026-10-20T09:00:00Z","end",null,"assignmentId","assignment-a","assignmentVersion",1)),
                "fences",JSONArray.of(object("id","fence-a","name","隔离测试围栏","station","station-a","coordinateSystem","GCJ02","enabled",true,"enter",true,"leave",true,
                        "members",JSONArray.of("person-a"),"points",JSONArray.parseArray("[[116.40,39.90],[116.41,39.90],[116.41,39.91],[116.40,39.91]]"))));
        for(String name:new String[]{"works","events","media","groups","calls","broadcasts","locations","fenceRecords","vitals","audit"})state.put(name,new JSONArray());
        store.replace(state);
        status=object("online",true,"freshness","CURRENT","locationFreshness","CURRENT");
        DirectHelmetAccess access=mock(DirectHelmetAccess.class);
        when(access.status("helmet-a")).thenAnswer(i->copy(status));
        ObjectProvider<DirectHelmetAccess> provider=mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(access);
        ReflectionTestUtils.setField(store,"directAccess",provider);
        ingest=new GuardianIngest(store);
    }

    JSONObject observe(String id,double longitude,String time) {return observe(id,longitude,time,new JSONObject());}
    JSONObject observe(String id,double longitude,String time,JSONObject changes) {
        // Match the real receive order: the runtime telemetry is current before durable delivery.
        status.putAll(object("longitude",longitude,"latitude",39.905,"coordinateSystem","GCJ02","locationQuality","valid",
                "accuracyMeters",5,"locationSource","GPS","locationReportedAt",time,"lastSeenAt",time));
        status.putAll(changes);
        JSONObject point=ingest.captureDirect("helmet-a");
        point.putAll(object("id",id,"deviceId","helmet-a","longitude",longitude,"latitude",39.905,"coordinateSystem","GCJ02",
                "locationQuality","valid","accuracyMeters",5,"locationSource","GPS","receivedAt",time,"source","direct-helmet"));
        point.putAll(changes);
        ingest.directLocation(point);
        return point;
    }

    @Test void crossingUsesPreviousObservationEvenWhenRuntimeAlreadyShowsNewPosition() {
        observe("point-outside",116.399,"2026-10-20T12:00:00Z");
        JSONObject inside=observe("point-inside",116.405,"2026-10-20T12:00:10Z");
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());
        JSONObject record=rows(store.snapshot(),"fenceRecords").getJSONObject(0);
        assertEquals("进入",record.getString("type"));assertEquals("PLATFORM_GEOFENCE",record.getString("source"));
        assertEquals("point-outside",record.getString("previousLocationId"));assertEquals("point-inside",record.getString("locationId"));
        assertEquals("helmet-a",record.getString("deviceId"));assertEquals("binding-a",record.getString("bindingId"));
        JSONObject alarm=find(store.snapshot(),"events",record.getString("eventId"));
        assertNotNull(alarm);assertEquals("电子围栏",alarm.getString("type"));
        assertEquals("进入围栏：隔离测试围栏",alarm.getString("title"));
        assertEquals("待认领",alarm.getString("status"));assertEquals("platform-geofence",alarm.getString("protocol"));
        assertEquals("PLATFORM_GEOFENCE",alarm.getString("source"));assertEquals("site-a",alarm.getString("siteId"));
        assertEquals("person-a",alarm.getString("personId"));assertEquals("binding-a",alarm.getString("bindingId"));
        assertEquals("验收人员",alarm.getJSONObject("snapshot").getString("personName"));
        assertEquals(116.405,alarm.getDoubleValue("locationLng"));assertEquals("valid",alarm.getString("locationQuality"));
        assertEquals("2026-10-20T12:00:10Z",alarm.getString("occurredAt"));assertEquals("20:00:10",alarm.getString("time"));
        assertEquals(record.getString("id"),alarm.getString("fenceRecordId"));
        assertEquals("point-outside",alarm.getString("previousLocationId"));
        ingest.directLocation(inside);
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size(),"a repeated report must not duplicate the crossing");
        assertEquals(1,rows(store.snapshot(),"events").size());
        observe("point-outside-again",116.399,"2026-10-20T12:00:20Z");
        assertEquals(2,rows(store.snapshot(),"fenceRecords").size());
        assertEquals("离开",rows(store.snapshot(),"fenceRecords").getJSONObject(0).getString("type"));
        assertEquals(2,rows(store.snapshot(),"events").size());
        assertEquals("离开围栏：隔离测试围栏",rows(store.snapshot(),"events").getJSONObject(0).getString("title"));
    }

    @Test void delayedAndEqualTimestampReportsNeverInventAnotherCrossing() {
        observe("outside",116.399,"2026-10-20T12:00:00Z");
        observe("inside",116.405,"2026-10-20T12:00:20Z");
        observe("late-outside",116.399,"2026-10-20T12:00:10Z");
        observe("same-time-outside",116.399,"2026-10-20T12:00:20Z");
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());
        assertEquals(1,rows(store.snapshot(),"events").size());
    }

    @Test void firstFixAndLongGapsDoNotEstablishCrossings() {
        observe("first",116.405,"2026-10-20T12:00:00Z");
        observe("after-gap",116.399,"2026-10-20T12:00:46Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        assertTrue(rows(store.snapshot(),"events").isEmpty());
    }

    @Test void uncertainOrDifferentCoordinateEvidenceCannotEstablishCrossings() {
        observe("outside",116.399,"2026-10-20T12:00:00Z");
        observe("different-system",116.405,"2026-10-20T12:00:10Z",object("coordinateSystem","WGS84"));
        observe("coarse",116.399,"2026-10-20T12:00:20Z",object("accuracyMeters",300));
        observe("after-coarse",116.405,"2026-10-20T12:00:30Z");
        observe("unknown-quality",116.399,"2026-10-20T12:00:40Z",object("locationQuality","unknown"));
        observe("after-unknown",116.405,"2026-10-20T12:00:50Z");
        observe("touching-boundary",116.40001,"2026-10-20T12:01:00Z");
        observe("after-boundary",116.399,"2026-10-20T12:01:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        assertTrue(rows(store.snapshot(),"events").isEmpty());
    }

    @Test void renewedIssueDoesNotCrossFromThePreviousIssueEvenForSamePerson() {
        observe("old-issue",116.399,"2026-10-20T12:00:00Z");
        store.update(s->{JSONObject old=rows(s,"bindings").getJSONObject(0);old.put("end","2026-10-20T12:00:05Z");
            JSONObject current=copy(old);current.put("id","binding-b");current.put("end",null);current.put("start","2026-10-20T12:00:05Z");current.put("assignmentId","assignment-b");rows(s,"bindings").add(current);return true;});
        observe("new-issue",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        assertTrue(rows(store.snapshot(),"events").isEmpty());
    }

    @Test void reassignmentCannotAttributeThePreviousWearersCrossingToTheNewPerson() {
        observe("old-wearer",116.399,"2026-10-20T12:00:00Z");
        store.update(s->{JSONObject person=copy(rows(s,"people").getJSONObject(0));person.put("id","person-b");rows(s,"people").add(person);
            JSONObject old=rows(s,"bindings").getJSONObject(0);old.put("end","2026-10-20T12:00:05Z");
            JSONObject current=copy(old);current.put("id","binding-b");current.put("personId","person-b");current.put("end",null);current.put("start","2026-10-20T12:00:05Z");rows(s,"bindings").add(current);
            rows(s,"fences").getJSONObject(0).getJSONArray("members").add("person-b");return true;});
        observe("new-wearer",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        assertTrue(rows(store.snapshot(),"events").isEmpty());
        assertEquals("person-a",rows(store.snapshot(),"locations").getJSONObject(1).getString("personId"));
    }

    JSONObject belt(double longitude,String time) {
        JSONObject telemetry=object("online",true,"freshness","CURRENT","locationFreshness","CURRENT","lastSeenAt",time,
                "longitude",longitude,"latitude",39.905,"coordinateSystem","GCJ02","locationQuality","valid","accuracyMeters",5,
                "locationSource","GPS","locationReportedAt",time);
        JSONObject captured=ingest.captureBelt("belt-a");
        store.update(s->GuardianIngest.directBeltReport(s,"belt-a",telemetry,true,captured));
        return telemetry;
    }
    void addBelt() {
        store.update(s->{rows(s,"devices").add(object("id","belt-a","type","B","source","DIRECT_BELT","active",true,"siteId","site-a","station","station-a"));
            rows(s,"bindings").add(object("id","belt-binding","deviceId","belt-a","personId","person-a","start","2026-10-20T09:00:00Z","end",null,"assignmentId","belt-assignment","assignmentVersion",1));return true;});
    }
    @Test void activeHelmetAndBeltSourcesShareActualObservationHistory() {
        addBelt();observe("helmet-outside",116.399,"2026-10-20T12:00:00Z");
        JSONObject telemetry=belt(116.405,"2026-10-20T12:00:10Z");
        JSONArray records=rows(store.snapshot(),"fenceRecords");assertEquals(1,records.size());
        assertEquals("belt-a",records.getJSONObject(0).getString("deviceId"));assertEquals("helmet-a",records.getJSONObject(0).getString("previousDeviceId"));
        assertEquals("platform-geofence",rows(store.snapshot(),"events").getJSONObject(0).getString("protocol"));
        assertEquals("belt-a",rows(store.snapshot(),"events").getJSONObject(0).getString("deviceId"));
        JSONObject captured=ingest.captureBelt("belt-a");store.update(s->GuardianIngest.directBeltReport(s,"belt-a",telemetry,true,captured));
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());
        assertEquals(1,rows(store.snapshot(),"events").size());
        observe("helmet-outside-again",116.399,"2026-10-20T12:00:20Z");
        assertEquals(2,rows(store.snapshot(),"fenceRecords").size());
        assertEquals(2,rows(store.snapshot(),"events").size());
    }

    @Test void secondDeviceAtSameTimeAndRetiredPercentageFencesDoNotCreateEvents() {
        addBelt();observe("helmet-outside",116.399,"2026-10-20T12:00:00Z");
        belt(116.405,"2026-10-20T12:00:00Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        assertTrue(rows(store.snapshot(),"events").isEmpty());
        observe("after-ambiguous-pair",116.399,"2026-10-20T12:00:05Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty(),"different simultaneous source positions cannot imply an earlier crossing");
        store.update(s->{JSONObject fence=rows(s,"fences").getJSONObject(0);fence.put("coordinateSystem","PERCENT");fence.put("points",JSONArray.parseArray("[[1,1],[10,1],[1,10]]"));return true;});
        observe("helmet-inside",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        assertTrue(rows(store.snapshot(),"events").isEmpty());
    }

    @Test void sqlReloadRetainsObservationEvidenceAndDoesNotDuplicateCrossings() {
        JSONObject state=store.snapshot();Object provider=ReflectionTestUtils.getField(store,"directAccess");
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE","sa",""));
        String key=Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.UTF_8));
        WearableBusinessStore business=new WearableBusinessStore(jdbc,key);
        store=new GuardianStore(mock(GuardianHatArchive.class),business);ReflectionTestUtils.setField(store,"file",directory.resolve("sql-state.json"));
        ReflectionTestUtils.setField(store,"directAccess",provider);store.replace(state);ingest=new GuardianIngest(store);
        observe("sql-outside",116.399,"2026-10-20T12:00:00Z");
        JSONObject inside=observe("sql-inside",116.405,"2026-10-20T12:00:10Z");
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());
        store=new GuardianStore(mock(GuardianHatArchive.class),business);ReflectionTestUtils.setField(store,"file",directory.resolve("sql-state.json"));
        ReflectionTestUtils.setField(store,"directAccess",provider);ingest=new GuardianIngest(store);ingest.directLocation(inside);
        JSONObject record=rows(store.snapshot(),"fenceRecords").getJSONObject(0);
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());assertEquals("sql-outside",record.getString("previousLocationId"));
        assertEquals(1,rows(store.snapshot(),"events").size());
        assertEquals(record.getString("eventId"),rows(store.snapshot(),"events").getJSONObject(0).getString("id"));
        observe("sql-leave",116.399,"2026-10-20T12:00:20Z");assertEquals(2,rows(store.snapshot(),"fenceRecords").size());
        assertEquals(2,rows(store.snapshot(),"events").size());
    }

    @Test void onlyEnabledMatchingFencesAndMembersProduceAlarms() {
        for(String field:new String[]{"enabled","archived","station","members"}) {
            setup();
            store.update(s->{JSONObject fence=rows(s,"fences").getJSONObject(0);
                fence.put(field,"enabled".equals(field)?false:"archived".equals(field)?true:"station".equals(field)?"another-station":new JSONArray());return true;});
            observe("outside",116.399,"2026-10-20T12:00:00Z");observe("inside",116.405,"2026-10-20T12:00:10Z");
            assertTrue(rows(store.snapshot(),"events").isEmpty(),field);
            assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty(),field);
        }
    }

    @Test void enterAndLeaveSwitchesControlTheMatchingAlarms() {
        store.update(s->{rows(s,"fences").getJSONObject(0).put("enter",false);return true;});
        observe("outside",116.399,"2026-10-20T12:00:00Z");observe("inside",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"events").isEmpty());
        observe("leave",116.399,"2026-10-20T12:00:20Z");
        assertEquals(1,rows(store.snapshot(),"events").size());
        assertEquals("离开",rows(store.snapshot(),"events").getJSONObject(0).getString("fenceDirection"));
        store.update(s->{JSONObject fence=rows(s,"fences").getJSONObject(0);fence.put("enter",true);fence.put("leave",false);return true;});
        observe("enter",116.405,"2026-10-20T12:00:30Z");observe("leave-disabled",116.399,"2026-10-20T12:00:40Z");
        assertEquals(2,rows(store.snapshot(),"events").size());
        assertEquals("进入",rows(store.snapshot(),"events").getJSONObject(0).getString("fenceDirection"));
    }

    @Test void alarmReplayAndLaterFenceEditsPreserveTheCapturedCrossing() {
        observe("outside",116.399,"2026-10-20T12:00:00Z");JSONObject point=observe("inside",116.405,"2026-10-20T12:00:10Z");
        store.update(s->{JSONObject record=rows(s,"fenceRecords").getJSONObject(0),fence=rows(s,"fences").getJSONObject(0);
            GeofenceAlarms.append(s,record,point,rows(s,"devices").getJSONObject(0),fence);
            fence.put("name","修改后的围栏");fence.getJSONArray("points").remove(3);rows(s,"people").getJSONObject(0).put("name","新姓名");return true;});
        JSONArray alarms=rows(store.snapshot(),"events");assertEquals(1,alarms.size());
        JSONObject captured=alarms.getJSONObject(0).getJSONObject("snapshot");
        assertEquals("隔离测试围栏",captured.getString("fenceName"));assertEquals("验收人员",captured.getString("personName"));
        assertEquals(4,captured.getJSONArray("fencePoints").size());
    }

    @Test void fenceAlarmsUseTheSameEventPermissionsForPortalAndMobile() {
        observe("outside",116.399,"2026-10-20T12:00:00Z");observe("inside",116.405,"2026-10-20T12:00:10Z");
        JSONObject master=object("sites",JSONArray.of(object("id","site-a","enabled",true,"portalStation","station-a"),object("id","site-b","enabled",true)),
                "roles",JSONArray.of(object("id","duty","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-a"),"operations",JSONArray.of("events:read","events:claim")))),
                        object("id","other","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-b"),"operations",JSONArray.of("events:read")))),
                        object("id","self","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-a"),"operations",JSONArray.of("self:read"))))),
                "people",JSONArray.of(object("id","ledger-person-a","enabled",true,"portalId","person-a","siteId","site-a"),object("id","ledger-person-b","enabled",true,"portalId","person-b","siteId","site-a")),
                "accounts",JSONArray.of(object("id","duty-a","enabled",true,"roleIds",JSONArray.of("duty")),object("id","other-site","enabled",true,"roleIds",JSONArray.of("other")),
                        object("id","wearer","enabled",true,"personId","ledger-person-a","roleIds",JSONArray.of("self")),object("id","other-person","enabled",true,"personId","ledger-person-b","roleIds",JSONArray.of("self"))));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenReturn(master);
        GuardianEvents api=new GuardianEvents(store,new GuardianAccess(ledger,mock(AdminQueryService.class)),mock(GuardianFiles.class));
        assertEquals(1,api.list(object("id","duty-a"),null,null,"电子围栏",1,10).getIntValue("total"));
        assertEquals(1,api.list(object("id","wearer"),null,null,"电子围栏",1,10).getIntValue("total"));
        assertEquals(0,api.list(object("id","other-site"),null,null,"电子围栏",1,10).getIntValue("total"));
        assertEquals(0,api.list(object("id","other-person"),null,null,"电子围栏",1,10).getIntValue("total"));
        String id=rows(store.snapshot(),"events").getJSONObject(0).getString("id");
        assertTrue(api.detail(object("id","duty-a"),id).getJSONObject("permissions").getBooleanValue("events:claim"));
        assertFalse(api.detail(object("id","wearer"),id).getJSONObject("permissions").getBooleanValue("events:claim"));
        assertEquals(404,assertThrows(AdminQueryService.QueryFailed.class,()->api.detail(object("id","other-site"),id)).code);
    }
}
