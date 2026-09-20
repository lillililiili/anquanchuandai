package com.ruoyi.portal;
import java.util.*;
import org.springframework.util.MultiValueMap;
public class PortalQuery {
    public String siteId,shiftId,teamId,keyword,workState,deviceType;
    public int pageNum=1,pageSize=20;
    public static boolean id(String value) { return value!=null && value.matches("[A-Za-z0-9_-]{1,64}"); }
    public static PortalQuery parse(MultiValueMap<String,String> params,String kind) {
        Set<String> allowed=new HashSet<>();
        if(!"context".equals(kind)) allowed.add("siteId");
        if("people".equals(kind)) allowed.addAll(Arrays.asList("pageNum","pageSize","shiftId","teamId","keyword","workState"));
        if("history".equals(kind)) allowed.addAll(Arrays.asList("pageNum","pageSize","deviceType"));
        for(String key:params.keySet()) if(!allowed.contains(key)||params.get(key).size()!=1) throw PortalException.invalid();
        PortalQuery q=new PortalQuery();
        if("context".equals(kind)) return q;
        q.siteId=params.getFirst("siteId");
        if(!id(q.siteId)) throw PortalException.invalid();
        q.shiftId=params.getFirst("shiftId");q.teamId=params.getFirst("teamId");
        for(String value:Arrays.asList(q.shiftId,q.teamId)) if(value!=null&&!id(value)) throw PortalException.invalid();
        q.keyword=params.getFirst("keyword"); if(q.keyword!=null) { q.keyword=q.keyword.trim(); if(q.keyword.length()>100) throw PortalException.invalid(); }
        q.workState=params.getFirst("workState"); if(q.workState!=null&&!Arrays.asList("WORKING","IDLE","UNKNOWN").contains(q.workState)) throw PortalException.invalid();
        q.deviceType=params.getFirst("deviceType"); if(q.deviceType!=null&&!Arrays.asList("HELMET","BELT","WATCH").contains(q.deviceType)) throw PortalException.invalid();
        q.pageNum=positive(params.getFirst("pageNum"),1,Integer.MAX_VALUE);
        q.pageSize=positive(params.getFirst("pageSize"),20,100);
        return q;
    }
    private static int positive(String raw,int fallback,int max) {
        if(raw==null) return fallback;
        try { if(!raw.matches("[1-9][0-9]*")) throw PortalException.invalid(); int n=Integer.parseInt(raw); if(n>max)throw PortalException.invalid();return n; }
        catch(NumberFormatException e) { throw PortalException.invalid(); }
    }
}

