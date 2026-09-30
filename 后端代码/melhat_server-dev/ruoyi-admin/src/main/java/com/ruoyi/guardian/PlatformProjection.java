package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.util.Objects;

final class PlatformProjection {
    private PlatformProjection() {}
    static boolean apply(JSONObject snapshot, JSONObject admin) {
        if(admin==null)return false;
        String before=snapshot.toJSONString();
        JSONArray target=snapshot.getJSONArray("devices");
        for(Object item:admin.getJSONArray("devices")) {
            JSONObject row=(JSONObject)item;if(!"PLATFORM".equals(row.getString("source")))continue;
            String id=row.getString("portalDeviceId");
            JSONObject device=AdminPlatformService.find(target,"id",id);
            if(device==null){device=new JSONObject();device.put("id",id);target.add(device);}
            device.put("type","H");device.put("source","PLATFORM");device.put("station",row.getString("portalStation"));
            device.put("active",!"DISABLED".equals(row.getString("lifecycle"))&&!"SCRAPPED".equals(row.getString("lifecycle")));
            String status=row.getString("communication");
            boolean fresh=false;
            try { fresh=java.time.Instant.parse(row.getString("sourceTime")).isAfter(java.time.Instant.now().minusSeconds(300)); }catch(Exception ignored){}
            device.put("online",!fresh?null:"ONLINE".equals(status)?Boolean.TRUE:"OFFLINE".equals(status)?Boolean.FALSE:null);
            device.put("battery",null);device.put("video","unavailable");device.put("updated",row.getString("sourceTime"));
            device.put("freshness",fresh?row.getString("freshness"):"STALE");device.put("name",row.getString("name"));
        }
        if(admin.get("platformSync")!=null)snapshot.put("platformSync",JSONObject.parseObject(admin.getJSONObject("platformSync").toJSONString()));
        return !Objects.equals(before,snapshot.toJSONString());
    }
}
