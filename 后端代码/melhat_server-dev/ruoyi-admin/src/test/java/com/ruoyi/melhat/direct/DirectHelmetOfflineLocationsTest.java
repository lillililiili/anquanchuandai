package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.HelmetBusinessJournal;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.time.Instant;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class DirectHelmetOfflineLocationsTest {
    @Test void keepsCollectionAndReceptionSeparateWithoutInventingHistoricalOwner(){
        Instant received=Instant.parse("2026-10-23T10:00:00Z");long collected=received.minusSeconds(3600).getEpochSecond();
        JSONObject row=DirectHelmetOfflineLocations.parse("hat-a",collected+",30.5,110.4;",received).get(0);
        assertEquals("30.5",row.getString("latitude"));assertEquals("110.4",row.getString("longitude"));
        assertEquals("",row.getString("personId"));assertNull(row.get("siteId"));assertTrue(row.getBooleanValue("unassigned"));
        assertEquals("UNKNOWN",row.getString("coordinateSystem"));assertEquals("STALE",row.getString("locationFreshness"));
        assertEquals(collected*1000,row.getLongValue("collectedMillis"));assertEquals(received.toEpochMilli(),row.getLongValue("receivedMillis"));
    }
    @Test void invalidPointRejectsWholeBatchBeforeAnyDatabaseWrite(){
        HelmetBusinessJournal journal=org.mockito.Mockito.mock(HelmetBusinessJournal.class);
        DirectHelmetOfflineLocations service=new DirectHelmetOfflineLocations(journal);long time=Instant.now().minusSeconds(60).getEpochSecond();
        assertThrows(IllegalArgumentException.class,()->service.receive("hat-a",time+",30,110;"+time+",91,110;"));
        org.mockito.Mockito.verifyNoInteractions(journal);
        assertThrows(IllegalArgumentException.class,()->service.receive("hat-a",(time+3600)+",30,110;"));
    }
    @Test void retryIsIdempotentAndHistoryUsesCollectionTime(){
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        HelmetBusinessJournal journal=new HelmetBusinessJournal(jdbc);DirectHelmetOfflineLocations service=new DirectHelmetOfflineLocations(journal);
        long seconds=Instant.now().minusSeconds(86400).getEpochSecond();String data=seconds+",30.50,110.40;";
        assertEquals(1,service.receive("hat-a",data));assertEquals(1,service.receive("hat-a",data));
        List<JSONObject> rows=journal.locations(null,"hat-a",seconds*1000,(seconds+1)*1000,seconds*1000-1,"",10);
        assertEquals(1,rows.size());assertEquals(seconds*1000,rows.get(0).getLongValue("queryMillis"));
        assertTrue(rows.get(0).getLongValue("receivedMillis")>rows.get(0).getLongValue("queryMillis"));
    }
}
