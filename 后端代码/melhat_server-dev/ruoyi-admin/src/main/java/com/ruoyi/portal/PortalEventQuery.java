package com.ruoyi.portal;
import java.time.Instant;
import java.util.*;
import org.springframework.util.MultiValueMap;
import com.ruoyi.portal.PortalEventModels.Phase;
public class PortalEventQuery {
    public String siteId,keyword,from,to,eventType; public Phase phase;
    public int pageNum=1,pageSize=20;
    public static PortalEventQuery parse(MultiValueMap<String,String> p,String kind){
        Set<String> allowed=new HashSet<>(Arrays.asList("siteId"));
        if(!"detail".equals(kind)&&!"summary".equals(kind))allowed.addAll(Arrays.asList("pageNum","pageSize"));
        if("list".equals(kind)||"summary".equals(kind))allowed.addAll(Arrays.asList("keyword","from","to","eventType","phase"));
        for(String k:p.keySet())if(!allowed.contains(k)||p.get(k).size()!=1)throw PortalException.invalid();
        PortalEventQuery q=new PortalEventQuery();q.siteId=p.getFirst("siteId");q.keyword=p.getFirst("keyword");q.from=p.getFirst("from");q.to=p.getFirst("to");q.eventType=p.getFirst("eventType");
        if(!PortalQuery.id(q.siteId)||(q.keyword!=null&&q.keyword.length()>100)||(q.eventType!=null&&!PortalQuery.id(q.eventType)))throw PortalException.invalid();
        try{if(p.containsKey("phase"))q.phase=Phase.valueOf(p.getFirst("phase"));if(p.containsKey("pageNum"))q.pageNum=Integer.parseInt(p.getFirst("pageNum"));if(p.containsKey("pageSize"))q.pageSize=Integer.parseInt(p.getFirst("pageSize"));
            if(q.pageNum<1||q.pageSize<1||q.pageSize>100||(q.from==null)!=(q.to==null))throw PortalException.invalid();
            if(q.from!=null&&(!q.from.endsWith("Z")||!q.to.endsWith("Z")||!Instant.parse(q.from).isBefore(Instant.parse(q.to))))throw PortalException.invalid();
        }catch(RuntimeException e){throw PortalException.invalid();}return q;
    }
}
