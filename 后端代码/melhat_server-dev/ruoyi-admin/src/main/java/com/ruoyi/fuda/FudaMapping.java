package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.belt.DirectBeltProperties;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.util.*;

/** Only explicitly understood observations become interoperable measurements. */
public final class FudaMapping {
    private static final DateTimeFormatter UTC=new DateTimeFormatterBuilder().appendInstant(3).toFormatter();
    private FudaMapping(){}
    public static JSONObject object(Object... pairs){JSONObject o=new JSONObject();for(int i=0;i<pairs.length;i+=2)o.put((String)pairs[i],pairs[i+1]);return o;}
    public static String time(Object value){try{return value==null?null:UTC.format(Instant.parse(value.toString()));}catch(Exception e){return null;}}
    public static String now(Clock clock){return UTC.format(clock.instant());}
    static boolean simulated(JSONObject row){
        if(row==null)return false;
        String origin=row.getString("dataOrigin");
        return row.getBooleanValue("demo")||row.getBooleanValue("simulated")||row.getBooleanValue("isSimulated")||row.get("seedProvenance")!=null
                ||origin!=null&&(origin.toUpperCase(Locale.ROOT).contains("SIMULAT")||origin.toUpperCase(Locale.ROOT).contains("MOCK")||origin.toUpperCase(Locale.ROOT).contains("SEED"));
    }
    static String text(JSONObject o,String key){if(o==null)return null;String s=o.getString(key);return s==null||s.trim().isEmpty()?null:s;}
    public static JSONObject common(String platform,String type,String id,String model){return object("sourcePlatform",platform,"deviceType",type,"deviceId",id,"deviceModel",model);}
    public static JSONObject position(JSONObject d){
        if(d==null)return null;
        Double lng=number(d.get("longitude")),lat=number(d.get("latitude"));
        String coordinates=text(d,"coordinateSystem"),at=time(d.get("locationReportedAt"));
        if(lng==null||lat==null||Math.abs(lng)>180||Math.abs(lat)>90||(lng==0&&lat==0)||at==null
                ||!Arrays.asList("WGS84","GCJ02").contains(coordinates)||!"valid".equalsIgnoreCase(d.getString("locationQuality")))return null;
        String method=text(d,"locationSource");method=method==null?"UNKNOWN":method.toUpperCase(Locale.ROOT);if("GPS".equals(method))method="GNSS";if(!Arrays.asList("GNSS","WIFI","CELL","OTHER").contains(method))method="UNKNOWN";
        // Current protocol fields are receipt timestamps. Do not relabel them as device sample times.
        return object("longitude",lng,"latitude",lat,"coordinateSystem",coordinates,"altitude",null,
                "relativeHeight",null,"heightReference","UNKNOWN","speed",null,"direction",null,
                "positionTime",at,"timeSource","PLATFORM","positionMethod",method,"historical",d.getBooleanValue("historical"));
    }
    public static JSONObject positionItem(JSONObject base,JSONObject d,int maximumAge,Clock clock){
        JSONObject p=position(d);base.put("position",p);
        base.put("validity",p==null?"UNKNOWN":validity(d,d.get("locationReportedAt"),"locationFreshness",maximumAge,clock,true));return base;
    }
    public static JSONObject statusItem(JSONObject base,JSONObject d,int timeout,DirectBeltProperties belt,Clock clock){
        boolean helmet="HELMET".equals(base.getString("deviceType"));
        base.put("onlineStatus",d.getBooleanValue("online")?"ONLINE":"OFFLINE");base.put("lastSeenAt",time(d.get("lastSeenAt")));
        base.put("offlineTimeoutSeconds",timeout);base.put("telemetryMaxAgeSeconds",timeout);
        Object batteryAt=d.get(helmet?"batteryReportedAt":"telemetryReportedAt");Double percent=number(d.get("battery"));
        if(percent!=null&&(percent<0||percent>100))percent=null;
        String batteryValidity=validity(d,batteryAt,helmet?"batteryFreshness":"telemetryFreshness",timeout,clock,percent!=null);
        if("UNKNOWN".equals(batteryValidity))percent=null;
        base.put("battery",object("percent",percent,"voltageMv",null,"observedAt",time(batteryAt),"validity",batteryValidity));
        // Raw strength values currently have no verified universal mapping to the V1 0..5 scale.
        base.put("network",object("type","UNKNOWN","signalLevel",null,"observedAt",time(d.get(helmet?"networkStrengthReportedAt":"telemetryReportedAt")),"validity","UNKNOWN"));
        Object wearAt=d.get(helmet?"isWearedReportedAt":"telemetryReportedAt");
        String wear=helmet?("2".equals(d.getString("isWeared"))?"WORN":"1".equals(d.getString("isWeared"))?"NOT_WORN":"UNKNOWN"):"UNKNOWN";
        String wearValidity=validity(d,wearAt,helmet?"isWearedFreshness":"telemetryFreshness",timeout,clock,!"UNKNOWN".equals(wear));
        if("UNKNOWN".equals(wearValidity))wear="UNKNOWN";
        base.put("wear",object("status",wear,"observedAt",time(wearAt),"validity",wearValidity));
        for(String suffix:new String[]{"A","B"}){
            if(helmet){base.put("hook"+suffix,object("status","UNSUPPORTED","observedAt",null,"validity","UNSUPPORTED"));continue;}
            Boolean attached=d.getBooleanValue("hookMappingConfirmed")&&belt.hookMappingConfirmed()?belt.hooked(d.getString("hanger"+suffix+"Status")):null;
            Object at=d.get("telemetryReportedAt");String v=validity(d,at,"telemetryFreshness",timeout,clock,attached!=null);
            base.put("hook"+suffix,object("status",attached==null||"UNKNOWN".equals(v)?"UNKNOWN":attached?"ATTACHED":"DETACHED","observedAt",time(at),"validity",v));
        }
        return base;
    }
    static String validity(JSONObject d,Object observedAt,String freshness,int maximumAge,Clock clock,boolean known){
        String at=time(observedAt);if(!known||at==null)return "UNKNOWN";
        Instant instant=Instant.parse(at);if(instant.isAfter(clock.instant().plusSeconds(300)))return "UNKNOWN";
        return d.getBooleanValue("online")&&"CURRENT".equals(d.getString(freshness))&&instant.plusSeconds(maximumAge).isAfter(clock.instant())?"VALID":"STALE";
    }
    static Double number(Object raw){try{double d=Double.parseDouble(String.valueOf(raw));return Double.isFinite(d)?d:null;}catch(Exception e){return null;}}
    static void applyLocationProfile(JSONObject d,FudaProperties.LocationProfile p){
        if(p==null||!p.isVerified()||p.getEvidence()==null||p.getEvidence().trim().isEmpty()||!Arrays.asList("WGS84","GCJ02").contains(p.getCoordinateSystem()))return;
        String quality=text(d,"locationQuality"),coordinates=text(d,"coordinateSystem");
        if(quality!=null&&!Arrays.asList("unknown","valid").contains(quality.toLowerCase(Locale.ROOT)))return;
        // A conflicting known reference requires investigation, never silent replacement.
        if(Arrays.asList("WGS84","GCJ02").contains(coordinates))return;
        String firmware=text(d,"firmware");if(firmware==null)firmware=text(d,"sourceFirmware");
        if(p.getFirmware()!=null&&!p.getFirmware().isEmpty()&&firmware!=null&&!p.getFirmware().equals(firmware))return;
        if(d.get("longitude")==null||d.get("latitude")==null||time(d.get("locationReportedAt"))==null)return;
        d.put("coordinateSystem",p.getCoordinateSystem());d.put("locationQuality","valid");
        if(Arrays.asList("GNSS","WIFI","CELL","OTHER").contains(p.getPositionMethod()))d.put("locationSource",p.getPositionMethod());
    }
    public static JSONObject alarm(String platform,JSONObject row){
        JSONObject event=row.getJSONObject("rawEvent");if(event==null)event=new JSONObject();
        JSONObject out=common(platform,row.getString("deviceType"),row.getString("deviceId"),row.getString("deviceModel"));
        String rawType=limited(text(event,"rawAlarmType"),64);
        boolean sos="sos_alarm_record".equals(event.getString("sourceRecordType"))||"人员求助".equals(event.getString("type"));
        out.put("eventId",row.getString("eventId"));out.put("occurredAt",time(row.get("occurredAt")));out.put("receivedAt",time(row.get("receivedAt")));
        out.put("alarmType",sos?"SOS":"UNKNOWN");out.put("alarmContent",sos?"设备发起 SOS":"设备报警"+(rawType==null?"":"（原始码："+rawType+"）"));
        out.put("rawAlarmType",rawType);out.put("rawAlarmName",limited(text(event,"rawAlarmName"),200));
        out.put("alarmOrigin","platform".equalsIgnoreCase(event.getString("source"))?"PLATFORM":"DEVICE");
        // Legacy events may carry a corroborated last position, which is not proof of an event-time fix.
        JSONObject psource=new JSONObject(event);
        if(psource.get("longitude")==null)psource.put("longitude",event.get("locationLng"));
        if(psource.get("latitude")==null)psource.put("latitude",event.get("locationLat"));
        JSONObject p=position(psource);if(p==null)p=position(row.getJSONObject("device"));
        Double age=null;
        if(p!=null&&out.getString("occurredAt")!=null){age=(Instant.parse(out.getString("occurredAt")).toEpochMilli()-Instant.parse(p.getString("positionTime")).toEpochMilli())/1000.0;if(age<0||age>300){p=null;age=null;}}
        else {p=null;age=null;}
        out.put("positionSource",p==null?"NONE":"LAST_KNOWN");out.put("position",p);out.put("positionAgeSeconds",age);
        return out;
    }
    private static String limited(String s,int max){return s==null?null:s.substring(0,Math.min(max,s.length()));}
}
