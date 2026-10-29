package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.guardian.HelmetBusinessJournal;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import static com.ruoyi.melhat.direct.HelmetMediaService.obj;

/** Firmware backup fixes have collection times but no historical owner, precision or coordinate-system label. */
@Service
public class DirectHelmetOfflineLocations {
    private final HelmetBusinessJournal journal;
    public DirectHelmetOfflineLocations(HelmetBusinessJournal journal){this.journal=journal;}
    @Transactional
    public synchronized int receive(String deviceId,String encoded){
        List<JSONObject> points=parse(deviceId,encoded,Instant.now());
        for(JSONObject point:points)journal.offlineLocation(point);
        // No GuardianIngest or Sessions calls: backup packets cannot update live position or trigger a fence.
        return points.size();
    }
    static List<JSONObject> parse(String deviceId,String encoded,Instant received){
        if(encoded==null||encoded.isEmpty()||encoded.length()>512*1024)throw new IllegalArgumentException("离线轨迹长度无效");
        String[] rows=encoded.split(";",-1);if(rows.length>10001)throw new IllegalArgumentException("单次最多10000个轨迹点");
        List<JSONObject> result=new ArrayList<>();
        for(int i=0;i<rows.length;i++){
            if(rows[i].isEmpty()&&i==rows.length-1)continue;
            String[] fields=rows[i].split(",",-1);if(fields.length!=3||!fields[0].matches("[0-9]{10}"))throw new IllegalArgumentException("离线轨迹点格式无效");
            long seconds=Long.parseLong(fields[0]);if(seconds<946684800L||seconds>received.getEpochSecond()+300)throw new IllegalArgumentException("轨迹采集时间无效");
            BigDecimal lat=coordinate(fields[1],90),lon=coordinate(fields[2],180);
            if(lat.signum()==0&&lon.signum()==0)continue;
            String collected=Instant.ofEpochSecond(seconds).toString();
            String identity=deviceId+"|"+seconds+"|"+lat.toPlainString()+"|"+lon.toPlainString();
            result.add(obj("id","HL-"+UUID.nameUUIDFromBytes(identity.getBytes(StandardCharsets.UTF_8)),"deviceId",deviceId,
                    "personId","","siteId",null,"areaId",null,"unassigned",true,"source","direct-helmet","offline",true,
                    "latitude",lat.toPlainString(),"longitude",lon.toPlainString(),"rawLatitude",fields[1],"rawLongitude",fields[2],
                    "coordinateSystem","UNKNOWN","locationSource","OFFLINE_UNKNOWN","locationQuality","unknown","locationFreshness","STALE",
                    "collectedMillis",seconds*1000,"collectedAt",collected,"deviceReportedAt",collected,"reportedAt",collected,
                    "receivedMillis",received.toEpochMilli(),"receivedAt",received.toString(),"accuracyMeters",null));
        }
        if(result.isEmpty())throw new IllegalArgumentException("没有有效离线轨迹点");return result;
    }
    private static BigDecimal coordinate(String raw,int bound){
        if(!raw.matches("-?[0-9]{1,3}(\\.[0-9]{1,12})?"))throw new IllegalArgumentException("轨迹坐标无效");
        BigDecimal value=new BigDecimal(raw).stripTrailingZeros();
        if(value.abs().compareTo(BigDecimal.valueOf(bound))>0)throw new IllegalArgumentException("轨迹坐标超出范围");return value;
    }
}
