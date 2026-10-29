package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import java.time.Instant;
import java.util.Objects;
import static com.ruoyi.guardian.WearableModel.*;

/** Select one current observation for a person only after the current issue began. */
final class PersonLocationProjection {
    static final String[] FIELDS={"longitude","latitude","coordinateSystem","locationSource","accuracyMeters",
            "locationReportedAt","locationTimeBasis","locationQuality","locationFreshness"};
    private PersonLocationProjection() {}

    static void apply(JSONObject state) {
        for(Object raw:rows(state,"people")) {
            JSONObject person=(JSONObject)raw;
            if(GuardianDemoData.confirmed(person))continue;
            JSONObject chosen=null,binding=null;
            for(Object item:rows(state,"bindings")) {
                JSONObject candidate=(JSONObject)item;
                if(candidate.get("end")!=null||!Objects.equals(person.getString("id"),candidate.getString("personId")))continue;
                JSONObject device=find(state,"devices",candidate.getString("deviceId"));
                if(!eligible(device,candidate)||binding(state,device.getString("id"))!=candidate)continue;
                if(chosen==null||compare(device,chosen,person.getString("locationDeviceId"))>0){chosen=device;binding=candidate;}
            }
            if(chosen==null) {
                if(person.get("longitude")!=null&&person.get("latitude")!=null) {
                    JSONObject previous=new JSONObject();
                    for(String key:FIELDS)previous.put(key,person.get(key));
                    previous.put("deviceId",person.get("locationDeviceId"));
                    previous.put("assignmentId",person.get("locationAssignmentId"));
                    previous.put("locationFreshness","STALE");person.put("lastKnownLocation",previous);
                }
                for(String key:FIELDS)person.remove(key);
                person.remove("locationDeviceId");person.remove("locationAssignmentId");person.remove("locationAssignmentVersion");
                person.remove("position");person.put("locationValid",false);
                person.put("locationFreshness","UNKNOWN");person.put("locationQuality","unknown");
                continue;
            }
            for(String key:FIELDS)person.put(key,chosen.get(key));
            person.remove("position");
            person.put("locationDeviceId",chosen.get("id"));
            person.put("locationAssignmentId",binding.get("assignmentId"));
            person.put("locationAssignmentVersion",binding.get("assignmentVersion"));
            person.put("locationTimeBasis",timeBasis(chosen));
            person.put("locationValid","valid".equals(chosen.getString("locationQuality"))
                    &&knownCoordinateSystem(chosen.getString("coordinateSystem")));
        }
    }
    static boolean eligible(JSONObject device,JSONObject binding) {
        if(device==null||binding==null||binding.get("end")!=null||!device.getBooleanValue("active")
                ||!device.getBooleanValue("online")||!"CURRENT".equals(device.getString("locationFreshness"))
                ||!"valid".equals(device.getString("locationQuality"))||!knownCoordinateSystem(device.getString("coordinateSystem"))
                ||"CACHED".equals(device.getString("locationSource"))||!coordinates(device))return false;
        Instant at=instant(device.getString("locationReportedAt")),start=instant(binding.getString("start"));
        return at!=null&&start!=null&&!at.isBefore(start)&&!at.isAfter(Instant.now().plusSeconds(5));
    }
    static JSONObject binding(JSONObject state,String deviceId) {
        JSONObject found=null;
        for(Object raw:rows(state,"bindings")) {
            JSONObject row=(JSONObject)raw;
            if(row.get("end")==null&&Objects.equals(deviceId,row.getString("deviceId"))) {
                if(found!=null)return null;
                found=row;
            }
        }
        return found;
    }
    static boolean sameBinding(JSONObject state,String deviceId,JSONObject captured,String at) {
        JSONObject current=binding(state,deviceId);
        if(current==null||captured==null||!Objects.equals(current.getString("id"),captured.getString("bindingId"))
                ||!Objects.equals(current.getString("personId"),captured.getString("personId")))return false;
        Instant observed=instant(at),start=instant(current.getString("start"));
        return observed!=null&&start!=null&&!observed.isBefore(start);
    }
    static boolean coordinates(JSONObject value) {
        try {
            Double lon=value.getDouble("longitude"),lat=value.getDouble("latitude");
            return lon!=null&&lat!=null&&Double.isFinite(lon)&&Double.isFinite(lat)&&Math.abs(lon)<=180&&Math.abs(lat)<=90&&(lon!=0||lat!=0);
        } catch(RuntimeException ignored){return false;}
    }
    static String timeBasis(JSONObject value) {
        String basis=value.getString("locationTimeBasis");
        return basis==null?(value.get("collectedAt")!=null?"DEVICE_COLLECTED_AT":"RECEIVED_AT"):basis;
    }
    static boolean knownCoordinateSystem(String system){return "WGS84".equals(system)||"GCJ02".equals(system)||"BD09".equals(system);}
    private static Instant instant(String value){try{return Instant.parse(value);}catch(RuntimeException ignored){return null;}}
    private static int compare(JSONObject first,JSONObject second,String previousSource) {
        int time=instant(first.getString("locationReportedAt")).compareTo(instant(second.getString("locationReportedAt")));
        if(time==0){
            boolean firstWasSource=Objects.equals(first.getString("id"),previousSource),secondWasSource=Objects.equals(second.getString("id"),previousSource);
            if(firstWasSource!=secondWasSource)return firstWasSource?1:-1;
        }
        return time!=0?time:-first.getString("id").compareTo(second.getString("id"));
    }
}
