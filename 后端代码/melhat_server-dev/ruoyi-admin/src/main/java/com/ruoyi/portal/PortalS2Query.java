package com.ruoyi.portal;
import java.time.Instant;
import java.util.*;
import org.springframework.util.MultiValueMap;
public class PortalS2Query {
    public String siteId,deviceId,personId,keyword,type,status,from,to;
    public int pageNum=1,pageSize=20;
    public static PortalS2Query parse(MultiValueMap<String,String> params,String kind) {
        Set<String> allowed=new HashSet<>(Arrays.asList("siteId"));
        if(Arrays.asList("devices","locations","fences","materials").contains(kind)) allowed.addAll(Arrays.asList("pageNum","pageSize","keyword"));
        if(kind.equals("materials"))allowed.addAll(Arrays.asList("deviceId","personId","type","from","to"));
        if(kind.equals("tracks"))allowed.addAll(Arrays.asList("deviceId","personId","from","to"));
        if(kind.equals("fences"))allowed.add("status");
        for(String k:params.keySet()) if(!allowed.contains(k)||params.get(k).size()!=1)throw PortalException.invalid();
        PortalS2Query q=new PortalS2Query(); q.siteId=params.getFirst("siteId");
        q.deviceId=params.getFirst("deviceId");q.personId=params.getFirst("personId");
        if(!PortalQuery.id(q.siteId)||(q.deviceId!=null&&!PortalQuery.id(q.deviceId))||(q.personId!=null&&!PortalQuery.id(q.personId)))throw PortalException.invalid();
        q.keyword=params.getFirst("keyword");if(q.keyword!=null&&q.keyword.length()>100)throw PortalException.invalid();
        q.type=params.getFirst("type");q.status=params.getFirst("status");
        if(q.type!=null&&!Arrays.asList("PHOTO","VIDEO","AUDIO").contains(q.type))throw PortalException.invalid();
        if(q.status!=null&&!Arrays.asList("ENABLED","DISABLED","UNKNOWN").contains(q.status))throw PortalException.invalid();
        try {
            if(params.containsKey("pageNum"))q.pageNum=Integer.parseInt(params.getFirst("pageNum"));
            if(params.containsKey("pageSize"))q.pageSize=Integer.parseInt(params.getFirst("pageSize"));
            if(q.pageNum<1||q.pageSize<1||q.pageSize>100)throw PortalException.invalid();
            q.from=params.getFirst("from");q.to=params.getFirst("to");
            if((q.from==null)!=(q.to==null))throw PortalException.invalid();
            if(q.from!=null&&(!q.from.endsWith("Z")||!q.to.endsWith("Z")||!Instant.parse(q.from).isBefore(Instant.parse(q.to))))throw PortalException.invalid();
            if(kind.equals("tracks")&&(q.deviceId==null||q.from==null))throw PortalException.invalid();
        } catch(RuntimeException e) {throw PortalException.invalid();}
        return q;
    }
}
