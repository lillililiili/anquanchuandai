package com.ruoyi.guardian;
import com.alibaba.fastjson2.*;
import org.junit.jupiter.api.Test;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;

class PersonLocationProjectionTest {
    JSONObject state(){return object("people",JSONArray.of(object("id","P","active",true)),"devices",new JSONArray(),"bindings",new JSONArray());}
    JSONObject device(JSONObject s,String id,String time){JSONObject d=object("id",id,"active",true,"online",true,"locationFreshness","CURRENT","locationReportedAt",time,"longitude",112.57,"latitude",35.46,"coordinateSystem","GCJ02","locationQuality","valid");rows(s,"devices").add(d);rows(s,"bindings").add(object("id","B-"+id,"deviceId",id,"personId","P","start","2026-10-20T10:00:00Z","end",null,"assignmentId","A-"+id,"assignmentVersion",1));return d;}
    @Test void newestAssignedSourceWinsIndependentlyOfDeviceIterationOrder(){
        JSONObject s=state();device(s,"hat","2026-10-20T12:00:00Z");device(s,"belt","2026-10-20T12:01:00Z");
        PersonLocationProjection.apply(s);JSONObject p=find(s,"people","P");assertEquals("belt",p.getString("locationDeviceId"));assertTrue(p.getBooleanValue("locationValid"));assertEquals("A-belt",p.getString("locationAssignmentId"));assertEquals("RECEIVED_AT",p.getString("locationTimeBasis"));
        find(s,"devices","belt").put("online",false);PersonLocationProjection.apply(s);assertEquals("hat",p.getString("locationDeviceId"));
    }
    @Test void preIssueCachedInvalidAndUnknownStartNeverBecomeCurrentPersonLocations(){
        for(String kind:new String[]{"before","cached","invalid","unknownStart"}){JSONObject s=state(),d=device(s,"hat","2026-10-20T12:00:00Z");
            if(kind.equals("before"))rows(s,"bindings").getJSONObject(0).put("start","2026-10-20T13:00:00Z");
            if(kind.equals("unknownStart"))rows(s,"bindings").getJSONObject(0).remove("start");
            if(kind.equals("cached"))d.put("locationSource","CACHED");if(kind.equals("invalid"))d.put("latitude",1000);
            PersonLocationProjection.apply(s);assertNull(find(s,"people","P").get("locationDeviceId"),kind);assertFalse(find(s,"people","P").getBooleanValue("locationValid"));}
    }
    @Test void returnRetainsLastKnownEvidenceButClearsCurrentPositionAndReissueRequiresNewFix(){
        JSONObject s=state();device(s,"hat","2026-10-20T12:00:00Z");PersonLocationProjection.apply(s);JSONObject p=find(s,"people","P");
        rows(s,"bindings").getJSONObject(0).put("end","2026-10-20T12:01:00Z");PersonLocationProjection.apply(s);
        assertNull(p.get("longitude"));assertEquals("hat",p.getJSONObject("lastKnownLocation").getString("deviceId"));
        JSONObject b=rows(s,"bindings").getJSONObject(0);b.put("end",null);b.put("start","2026-10-20T12:02:00Z");b.put("id","new-binding");
        PersonLocationProjection.apply(s);assertNull(p.get("locationDeviceId"));
        assertFalse(PersonLocationProjection.sameBinding(s,"hat",object("bindingId","B-hat","personId","P"),"2026-10-20T12:03:00Z"));
    }
    @Test void unconfirmedCoordinateSystemRetainsRawCoordinatesWithoutMapOrFenceClaim(){
        JSONObject s=state(),d=device(s,"belt","2026-10-20T12:00:00Z");d.put("coordinateSystem","UNKNOWN");d.put("locationQuality","unknown");
        PersonLocationProjection.apply(s);JSONObject p=find(s,"people","P");assertNull(p.get("locationDeviceId"));assertNull(p.get("longitude"));assertEquals(112.57,d.getDoubleValue("longitude"));assertFalse(p.getBooleanValue("locationValid"));assertFalse(p.containsKey("position"));
    }
    @Test void aNewerInvalidObservationNeverHidesAnOlderValidAssignedSource(){
        JSONObject s=state();device(s,"hat","2026-10-20T12:00:00Z");JSONObject belt=device(s,"belt","2026-10-20T12:01:00Z");belt.put("locationQuality","unknown");
        PersonLocationProjection.apply(s);assertEquals("hat",find(s,"people","P").getString("locationDeviceId"));
        belt.put("locationQuality","valid");belt.put("coordinateSystem","UNKNOWN");PersonLocationProjection.apply(s);
        assertEquals("hat",find(s,"people","P").getString("locationDeviceId"));
    }
    @Test void equalObservationTimesKeepThePreviousValidSource(){
        JSONObject s=state();JSONObject hat=device(s,"hat","2026-10-20T12:01:00Z");device(s,"belt","2026-10-20T12:00:00Z");PersonLocationProjection.apply(s);
        assertEquals("hat",find(s,"people","P").getString("locationDeviceId"));
        find(s,"devices","belt").put("locationReportedAt",hat.get("locationReportedAt"));PersonLocationProjection.apply(s);
        assertEquals("hat",find(s,"people","P").getString("locationDeviceId"));
    }
    @Test void duplicateActiveAssignmentsNeverBecomeAPersonLocation(){
        JSONObject s=state();device(s,"hat","2026-10-20T12:00:00Z");rows(s,"bindings").add(copy(rows(s,"bindings").getJSONObject(0)));
        PersonLocationProjection.apply(s);assertNull(find(s,"people","P").get("locationDeviceId"));
    }
}
