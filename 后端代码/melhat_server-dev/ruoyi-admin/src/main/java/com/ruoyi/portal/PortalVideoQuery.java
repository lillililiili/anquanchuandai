package com.ruoyi.portal;
import java.util.*;
import org.springframework.util.MultiValueMap;
public class PortalVideoQuery {
    public String siteId,keyword,areaId,workId;
    public int pageNum=1,pageSize=8;
    public static PortalVideoQuery parse(MultiValueMap<String,String> p,boolean detail){
        Set<String> allowed=new HashSet<>(Arrays.asList("siteId"));
        if(!detail)allowed.addAll(Arrays.asList("keyword","areaId","workId","pageNum","pageSize"));
        for(String k:p.keySet())if(!allowed.contains(k)||p.get(k).size()!=1)throw PortalException.invalid();
        PortalVideoQuery q=new PortalVideoQuery();q.siteId=p.getFirst("siteId");q.keyword=p.getFirst("keyword");q.areaId=p.getFirst("areaId");q.workId=p.getFirst("workId");
        if(!PortalQuery.id(q.siteId)||(q.areaId!=null&&!PortalQuery.id(q.areaId))||(q.workId!=null&&!PortalQuery.id(q.workId))||(q.keyword!=null&&q.keyword.length()>100))throw PortalException.invalid();
        try{if(p.containsKey("pageNum"))q.pageNum=Integer.parseInt(p.getFirst("pageNum"));if(p.containsKey("pageSize"))q.pageSize=Integer.parseInt(p.getFirst("pageSize"));}catch(RuntimeException e){throw PortalException.invalid();}
        if(q.pageNum<1||q.pageSize<1||q.pageSize>100)throw PortalException.invalid();return q;
    }
}
