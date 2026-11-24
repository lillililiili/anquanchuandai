package com.ruoyi.melhat.split;

import com.alibaba.fastjson2.*;
import com.ruoyi.guardian.AdminQueryService;
import java.time.Instant;
import java.math.BigDecimal;
import java.util.*;

public final class SplitTelemetry {
    private SplitTelemetry(){}
    public static JSONObject obj(Object...p){JSONObject o=new JSONObject();for(int i=0;i<p.length;i+=2)o.put(String.valueOf(p[i]),p[i+1]);return o;}
    public static JSONObject copy(JSONObject o){return JSONObject.parseObject(o.toJSONString());}
    public static AdminQueryService.QueryFailed fail(int status,String code,String message){return AdminQueryService.fail(status,code,message);}
    public static String sn(Object value){if(!(value instanceof String)||!((String)value).matches("[A-Za-z0-9._-]{1,64}"))throw fail(400,"SPLIT_INVALID_DEVICE","安全帽标识格式无效");return (String)value;}
    public static String normalizeTimestamp(Object value,long received){
        if(value==null||String.valueOf(value).trim().isEmpty())return Instant.ofEpochMilli(received).toString();
        long millis;
        try{String text=String.valueOf(value).trim();if(text.matches("[0-9]{10,13}")){millis=Long.parseLong(text);if(text.length()==10)millis*=1000;else if(text.length()!=13)throw new IllegalArgumentException();}else millis=Instant.parse(text).toEpochMilli();}
        catch(RuntimeException invalid){return Instant.ofEpochMilli(received).toString();}
        if(millis<946684800000L)return Instant.ofEpochMilli(received).toString();
        return Instant.ofEpochMilli(millis>received+300000?received:millis).toString();
    }
    public static void validate(String kind,JSONObject p,long received){
        sn(p.get("helmetSn"));normalizeTimestamp(p.get("timestamp"),received);
        if("gnss".equals(kind)){double x=number(p.get("longitude"),-180,180,true),y=number(p.get("latitude"),-90,90,true);if(x==0&&y==0)throw fail(400,"SPLIT_INVALID_COORDINATE","零点坐标不能作为定位");}
        if("deviceStatus".equals(kind)){Object battery=p.containsKey("power")?p.get("power"):p.get("battery");if(battery!=null&&!String.valueOf(battery).isEmpty())number(battery,0,100,true);}
        if("sos".equals(kind)&&!Arrays.asList("silent","sos","removal","fall","proximity").contains(p.getString("type")))throw fail(400,"SPLIT_INVALID_EVENT","分体帽事件类型无效");
    }
    public static Double number(Object value,double min,double max,boolean required){
        if(value==null||String.valueOf(value).isEmpty()){if(required)throw fail(400,"SPLIT_INVALID_VALUE","设备上报字段缺失");return null;}
        try{double n=new BigDecimal(String.valueOf(value)).doubleValue();if(!Double.isFinite(n)||n<min||n>max)throw new IllegalArgumentException();return n;}catch(RuntimeException bad){throw fail(400,"SPLIT_INVALID_VALUE","设备上报数值无效");}
    }
    public static JSONObject merge(JSONObject s,JSONObject envelope){
        JSONObject p=envelope.getJSONObject("payload");String kind=envelope.getString("kind"),at=envelope.getString("observedAt");
        long received=envelope.getLongValue("receivedMillis");s.put("deviceId",envelope.getString("deviceId"));
        if(received>=s.getLongValue("lastReceivedMillis")){s.put("lastReceivedMillis",received);s.put("lastSeenAt",Instant.ofEpochMilli(received).toString());}
        if("gnss".equals(kind)){
            String previous=s.getString("locationReportedAt");if(previous!=null&&Instant.parse(at).isBefore(Instant.parse(previous)))return s;
            field(s,"longitude",number(p.get("longitude"),-180,180,true),at);field(s,"latitude",number(p.get("latitude"),-90,90,true),at);
            field(s,"location",true,at);s.put("coordinateSystem","WGS84");s.put("locationQuality","valid");s.put("locationSource","GNSS");s.put("locationTimeBasis",envelope.containsKey("timeAnomaly")||p.get("timestamp")==null?"RECEIVED_AT":"DEVICE_TIME");
            optional(s,p,"speed","speed",at);optional(s,p,"altitude","gpsAltitude",at);
        }else if("deviceStatus".equals(kind)){
            Object b=p.containsKey("power")?p.get("power"):p.containsKey("battery")?p.get("battery"):p.containsKey("electricity")?p.get("electricity"):p.get("batteryLevel");if(b!=null&&!String.valueOf(b).isEmpty())field(s,"battery",number(b,0,100,true),at);
            optional(s,p,"voltage","voltage",at);
            for(String[] keys:new String[][]{{"storageUsed","used"},{"storageAvailable","available"},{"storageTotal","total"},{"tfEnable","tf_enable"}}){Object v=p.containsKey(keys[0])?p.get(keys[0]):p.get(keys[1]);if(v!=null&&!String.valueOf(v).isEmpty())field(s,keys[0],String.valueOf(v),at);}
        }else if("baro".equals(kind)){optional(s,p,"pressure","pressure",at);optional(s,p,"temperature","temperature",at);optional(s,p,"altitude","barometricAltitude",at);}
        // removal has no matching wear-on notification: it cannot establish current wear state.
        if("sos".equals(kind)&&"removal".equals(p.getString("type")))field(s,"lastRemovalAt",at,at);
        return s;
    }
    private static void optional(JSONObject s,JSONObject p,String from,String to,String at){Object v=p.get(from);if(v!=null&&!String.valueOf(v).isEmpty())field(s,to,String.valueOf(v),at);}
    public static void field(JSONObject s,String key,Object value,String at){String previous=s.getString(key+"ReportedAt");if(previous==null||!Instant.parse(at).isBefore(Instant.parse(previous))){s.put(key,value);s.put(key+"ReportedAt",at);}}
    public static JSONObject view(JSONObject stored,int freshSeconds,long now){
        JSONObject s=copy(stored);String onlineAt=s.getString("onlineReportedAt");boolean onlineFresh=fresh(onlineAt,now,freshSeconds);
        s.put("online",onlineFresh&&!s.getBooleanValue("onlineUnknown")?s.getBoolean("vendorOnline"):null);s.put("freshness",s.getBooleanValue("onlineUnknown")?"UNKNOWN":onlineFresh?"CURRENT":onlineAt==null?"UNKNOWN":"STALE");
        for(String key:Arrays.asList("battery","location","pressure","temperature","barometricAltitude","storageUsed","storageAvailable","storageTotal","tfEnable"))s.put(key+"Freshness",fresh(s.getString(key+"ReportedAt"),now,freshSeconds)?"CURRENT":s.get(key+"ReportedAt")==null?"UNKNOWN":"STALE");
        s.put("worn",null);s.put("isWearedFreshness","UNKNOWN");s.put("communicationProtocol","ZLM_WEBRTC");s.put("mediaProtocol","ZLM_WEBRTC");s.put("recordingOrigin","device");s.put("source","SPLIT_HELMET");
        s.put("sourceTime",onlineAt);s.put("locationReportedAt",s.get("locationReportedAt"));s.remove("location");return s;
    }
    private static boolean fresh(String at,long now,int seconds){try{return at!=null&&now-Instant.parse(at).toEpochMilli()<=seconds*1000L;}catch(RuntimeException e){return false;}}
}
