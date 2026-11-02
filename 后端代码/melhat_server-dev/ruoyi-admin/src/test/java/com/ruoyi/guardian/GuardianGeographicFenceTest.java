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
        ingest.directLocation(inside);
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size(),"a repeated report must not duplicate the crossing");
        observe("point-outside-again",116.399,"2026-10-20T12:00:20Z");
        assertEquals(2,rows(store.snapshot(),"fenceRecords").size());
        assertEquals("离开",rows(store.snapshot(),"fenceRecords").getJSONObject(0).getString("type"));
    }

    @Test void delayedAndEqualTimestampReportsNeverInventAnotherCrossing() {
        observe("outside",116.399,"2026-10-20T12:00:00Z");
        observe("inside",116.405,"2026-10-20T12:00:20Z");
        observe("late-outside",116.399,"2026-10-20T12:00:10Z");
        observe("same-time-outside",116.399,"2026-10-20T12:00:20Z");
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());
    }

    @Test void firstFixAndLongGapsDoNotEstablishCrossings() {
        observe("first",116.405,"2026-10-20T12:00:00Z");
        observe("after-gap",116.399,"2026-10-20T12:00:46Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
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
    }

    @Test void renewedIssueDoesNotCrossFromThePreviousIssueEvenForSamePerson() {
        observe("old-issue",116.399,"2026-10-20T12:00:00Z");
        store.update(s->{JSONObject old=rows(s,"bindings").getJSONObject(0);old.put("end","2026-10-20T12:00:05Z");
            JSONObject current=copy(old);current.put("id","binding-b");current.put("end",null);current.put("start","2026-10-20T12:00:05Z");current.put("assignmentId","assignment-b");rows(s,"bindings").add(current);return true;});
        observe("new-issue",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
    }

    @Test void reassignmentCannotAttributeThePreviousWearersCrossingToTheNewPerson() {
        observe("old-wearer",116.399,"2026-10-20T12:00:00Z");
        store.update(s->{JSONObject person=copy(rows(s,"people").getJSONObject(0));person.put("id","person-b");rows(s,"people").add(person);
            JSONObject old=rows(s,"bindings").getJSONObject(0);old.put("end","2026-10-20T12:00:05Z");
            JSONObject current=copy(old);current.put("id","binding-b");current.put("personId","person-b");current.put("end",null);current.put("start","2026-10-20T12:00:05Z");rows(s,"bindings").add(current);
            rows(s,"fences").getJSONObject(0).getJSONArray("members").add("person-b");return true;});
        observe("new-wearer",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
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
        JSONObject captured=ingest.captureBelt("belt-a");store.update(s->GuardianIngest.directBeltReport(s,"belt-a",telemetry,true,captured));
        assertEquals(1,rows(store.snapshot(),"fenceRecords").size());
        observe("helmet-outside-again",116.399,"2026-10-20T12:00:20Z");
        assertEquals(2,rows(store.snapshot(),"fenceRecords").size());
    }

    @Test void secondDeviceAtSameTimeAndRetiredPercentageFencesDoNotCreateEvents() {
        addBelt();observe("helmet-outside",116.399,"2026-10-20T12:00:00Z");
        belt(116.405,"2026-10-20T12:00:00Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
        observe("after-ambiguous-pair",116.399,"2026-10-20T12:00:05Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty(),"different simultaneous source positions cannot imply an earlier crossing");
        store.update(s->{JSONObject fence=rows(s,"fences").getJSONObject(0);fence.put("coordinateSystem","PERCENT");fence.put("points",JSONArray.parseArray("[[1,1],[10,1],[1,10]]"));return true;});
        observe("helmet-inside",116.405,"2026-10-20T12:00:10Z");
        assertTrue(rows(store.snapshot(),"fenceRecords").isEmpty());
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
        observe("sql-leave",116.399,"2026-10-20T12:00:20Z");assertEquals(2,rows(store.snapshot(),"fenceRecords").size());
    }
}
