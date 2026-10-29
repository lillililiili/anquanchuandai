package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.util.StreamUtils;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianLocationsTest {
    JSONObject master,admin,member,duty;HelmetBusinessJournal journal;GuardianLocations service;GuardianAccess access;
    long time=Instant.parse("2026-10-23T01:00:00Z").toEpochMilli();
    @BeforeEach void setup() throws Exception {
        master=JSONObject.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(),StandardCharsets.UTF_8));migrate(master);
        admin=find(master,"accounts","demo-system");duty=find(master,"accounts","demo-duty");
        member=object("id","mobile-one","name","测试员工","enabled",true,"personId","person-1-0","roleIds",JSONArray.parseArray("[\"mobile-user\"]"));rows(master,"accounts").add(member);
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));
        access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        journal=new HelmetBusinessJournal(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","")));
        service=new GuardianLocations(access,mock(GuardianStore.class),journal);
    }
    JSONObject point(String person,String area,int n) {
        return object("id","HL-00000000-0000-0000-0000-"+String.format("%012d",n),"personId",person,"deviceId","test-helmet",
                "siteId","site-1","areaId",area,"receivedMillis",time,"receivedAt",Instant.ofEpochMilli(time).toString(),
                "reportedAt",Instant.ofEpochMilli(time).toString(),"latitude",30,"longitude",110,"coordinateSystem","UNKNOWN","locationQuality","unknown");
    }
    JSONObject history(JSONObject actor,String person,String cursor,int limit) {
        return service.history(actor,person,null,"2026-10-23T00:00:00Z","2026-10-24T00:00:00Z",cursor,limit);
    }
    @Test void selfScopeAndCapturedSiteAreCheckedForEveryHistoricalPoint() {
        journal.location(point("P1","area-boiler",1));journal.location(point("P1","another-area",2));
        assertEquals(2,history(member,"P1",null,50).getJSONArray("rows").size());
        assertThrows(AdminQueryService.QueryFailed.class,()->history(member,"P2",null,50));
        JSONObject scope=object("duty",object("siteIds",JSONArray.parseArray("[\"site-1\"]"),"areaIds",JSONArray.parseArray("[\"area-boiler\"]")));
        duty.put("roleScopes",scope);
        // Retired area scopes no longer hide observations in the authorized site.
        assertTrue(GuardianLocations.visible(access.context(duty),point("P1","area-boiler",3),false));
        assertTrue(GuardianLocations.visible(access.context(duty),point("P1","another-area",4),false));
        assertTrue(GuardianLocations.visible(access.context(duty),point("P1",null,5),false));
        JSONObject foreign=point("P1","area-boiler",6);foreign.put("siteId","site-2");
        assertFalse(GuardianLocations.visible(access.context(duty),foreign,false));
        assertFalse(history(duty,"P1",null,50).toJSONString().contains("areaId"));
    }
    @Test void keysetPaginationDoesNotLoseSameTimestampPointsAndUnknownCoordinatesRemainRaw() {
        for(int n=1;n<=3;n++) journal.location(point("P1","area-boiler",n));
        JSONObject first=history(admin,"P1",null,2),second=history(admin,"P1",first.getString("nextCursor"),2);
        assertEquals(2,first.getJSONArray("rows").size());assertEquals(1,second.getJSONArray("rows").size());
        assertNull(second.get("nextCursor"));
        JSONObject raw=first.getJSONArray("rows").getJSONObject(0);
        assertEquals("UNKNOWN",raw.getString("coordinateSystem"));assertEquals(110,raw.getIntValue("longitude"));
        assertFalse(raw.containsKey("receivedMillis"));
        assertThrows(IllegalArgumentException.class,()->history(admin,"P1","invalid",2));
    }

    @Test void unifiedHistoryIncludesBeltAndHelmetWithOldCursorCompatibility() {
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        WearableBusinessStore business=new WearableBusinessStore(jdbc);
        WearableBusinessStore.Snapshot snapshot=business.load("guardian",null,()->object("version",1,"stations",new JSONArray(),"locations",new JSONArray()));
        JSONObject helmet=point("P1","area-boiler",1),belt=point("P1","area-boiler",2);belt.put("id","LOC42");belt.put("deviceId","test-belt");belt.put("source","direct-belt");
        snapshot.state.getJSONArray("locations").add(helmet);snapshot.state.getJSONArray("locations").add(belt);business.save("guardian",snapshot.revision,snapshot.state,null);
        journal.location(helmet); // The legacy journal and new store contain the same point only once in the API.
        org.springframework.test.util.ReflectionTestUtils.setField(service,"business",business);
        JSONObject first=history(admin,"P1",null,1),second=history(admin,"P1",first.getString("nextCursor"),10);
        assertEquals(helmet.getString("id"),first.getJSONArray("rows").getJSONObject(0).getString("id"));
        assertEquals(1,second.getJSONArray("rows").size());assertEquals("LOC42",second.getJSONArray("rows").getJSONObject(0).getString("id"));
        assertNull(second.get("nextCursor"));
    }
}
