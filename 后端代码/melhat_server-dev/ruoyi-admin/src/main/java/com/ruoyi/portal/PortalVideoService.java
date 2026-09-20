package com.ruoyi.portal;
import java.time.Instant;
import java.util.*;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.portal.PortalVideoModels.*;
import com.ruoyi.portal.PortalVideoModels.Detail;

@Service
public class PortalVideoService {
    private final PortalAccess access; private final PortalSource context; private final PortalVideoSource source;
    private static final String READ="portal:video:read";
    public PortalVideoService(PortalAccess a,PortalSource c,PortalVideoSource s){access=a;context=c;source=s;}
    private PortalException fault(){return new PortalException(503,"SOURCE_UNAVAILABLE","视频来源或授权证据不完整");}
    private <T> T read(Supplier<T> call){try{return call.get();}catch(PortalException e){throw e;}catch(Exception e){throw fault();}}
    private String authorize(PortalVideoQuery q){String a=access.actorId();access.require(READ);Context c=read(()->context.context(a));if(c==null||c.sites==null)throw fault();if(c.sites.stream().noneMatch(s->q.siteId.equals(s.siteId)))throw PortalException.forbidden();return a;}
    private boolean visible(String a,String site,String kind,String id,String p){return PortalQuery.id(id)&&read(()->source.visible(a,site,kind,id,p));}
    private <T> Section<T> section(Section<T> s){if(s==null||s.state==null||(s.state==State.AVAILABLE?s.data==null:s.data!=null||s.reasonCode==null))throw fault();if(s.state==State.UNAVAILABLE)throw fault();return s;}
    private void time(String t){if(t!=null)try{if(!t.endsWith("Z"))throw fault();Instant.parse(t);}catch(RuntimeException e){throw fault();}}
    private void device(VideoDevice d,String site){
        if(d==null||!PortalQuery.id(d.deviceId)||!site.equals(d.siteId)||d.name==null||d.type==null||d.communication==null||d.communication.state==null||d.video==null||d.video.state==null||!Arrays.asList("VERIFIED","UNVERIFIED").contains(d.video.verification)||d.streamState==null)throw fault();
        time(d.sourceTime);time(d.communication.sourceTime);time(d.communication.receivedAt);time(d.communication.observedAt);
        if(d.sourceTime==null||Instant.parse(d.sourceTime).isAfter(Instant.now()))d.freshness=Freshness.UNKNOWN;
        if(d.communication.sourceTime==null)d.communication.freshness=Freshness.UNKNOWN;
        if("LEGACY_SNAPSHOT".equals(d.communication.sourceKind))d.communication.state=CommunicationState.UNKNOWN;
        d.unavailableReason="MEDIA_ACCESS_NOT_ENABLED";
    }
    private void filter(Section<List<Option>> s,String value,String a,String site,String kind){section(s);if(s.state==State.AVAILABLE){Set<String> ids=new HashSet<>();for(Option o:s.data)if(o==null||!PortalQuery.id(o.id)||o.name==null||!ids.add(o.id))throw fault();s.data=s.data.stream().filter(o->visible(a,site,kind,o.id,READ)).collect(Collectors.toList());}
        if(value!=null){if(s.state!=State.AVAILABLE)throw new PortalException(400,"FILTER_NOT_SUPPORTED","该筛选来源尚未接入");if(s.data.stream().noneMatch(o->value.equals(o.id)))throw PortalException.invalid();}}
    public VideoPage list(PortalVideoQuery q){
        String a=authorize(q);Filters f=read(()->source.filters(a,q.siteId));if(f==null)throw fault();filter(f.areas,q.areaId,a,q.siteId,"area");filter(f.works,q.workId,a,q.siteId,"work");
        Section<List<VideoDevice>> s=section(read(()->source.devices(a,q.siteId)));if(s.state==State.FORBIDDEN)throw PortalException.forbidden();
        VideoPage p=new VideoPage();p.state=s.state;p.reasonCode=s.reasonCode;p.pageNum=q.pageNum;p.pageSize=q.pageSize;p.scope.put("siteId",q.siteId);p.filters=f;
        if(s.state!=State.AVAILABLE)return p;
        Map<String,VideoDevice> unique=new TreeMap<>();for(VideoDevice d:s.data){device(d,q.siteId);if(visible(a,q.siteId,"device",d.deviceId,READ))unique.putIfAbsent(d.deviceId,d);}
        List<VideoDevice> rows=unique.values().stream().filter(d->(q.areaId==null||q.areaId.equals(d.areaId))&&(q.workId==null||q.workId.equals(d.workId))&&(q.keyword==null||d.name.contains(q.keyword)||d.deviceId.contains(q.keyword))).collect(Collectors.toList());
        // Area/work identifiers themselves must not leak independently of their object scope.
        for(VideoDevice d:rows){if(d.areaId!=null&&!visible(a,q.siteId,"area",d.areaId,READ))d.areaId=null;if(d.workId!=null&&(!access.has("portal:work:read")||!visible(a,q.siteId,"work",d.workId,"portal:work:read")))d.workId=null;}
        p.total=(long)rows.size();long start=(long)(q.pageNum-1)*q.pageSize;if(start<rows.size())p.items=new ArrayList<>(rows.subList((int)start,(int)Math.min(start+q.pageSize,rows.size())));
        Section<StatisticsEvidence> stats=section(read(()->source.statistics(a,q)));p.statistics=new Section<>(stats.state,null,stats.reasonCode);
        if(stats.state==State.AVAILABLE){StatisticsEvidence e=stats.data;Set<String> ids=rows.stream().map(d->d.deviceId).collect(Collectors.toSet());if(e.deviceIds==null||!e.deviceIds.equals(ids)||e.availableIds==null||e.interruptedIds==null||e.notStartedIds==null||!ids.containsAll(e.availableIds)||!ids.containsAll(e.interruptedIds)||!ids.containsAll(e.notStartedIds)||!Collections.disjoint(e.availableIds,e.interruptedIds)||!Collections.disjoint(e.availableIds,e.notStartedIds)||!Collections.disjoint(e.interruptedIds,e.notStartedIds))throw fault();time(e.sourceTime);Statistics n=new Statistics();n.devices=(long)e.deviceIds.size();n.available=(long)e.availableIds.size();n.interrupted=(long)e.interruptedIds.size();n.notStarted=(long)e.notStartedIds.size();n.sourceTime=e.sourceTime;p.statistics=Section.available(n);}
        return p;
    }
    private Section<List<Related>> related(Section<List<Related>> s,String a,String site,String kind,String permission){
        if(!access.has(permission))return new Section<>(State.FORBIDDEN,null,"SECTION_FORBIDDEN");
        // Related-source failures remain local to this section, never become empty success.
        if(s!=null&&s.state==State.UNAVAILABLE&&s.data==null&&s.reasonCode!=null)return s;
        section(s);if(s.state!=State.AVAILABLE)return s;List<Related> allowed=new ArrayList<>();
        for(Related r:s.data){if(r==null||!PortalQuery.id(r.id)||!site.equals(r.siteId)||r.name==null)throw fault();time(r.sourceTime);time(r.receivedAt);if(!"CONFIRMED".equals(r.attribution)||r.evidenceId==null)continue;if(visible(a,site,kind,r.id,permission)){if(r.sourceTime==null)r.freshness=Freshness.UNKNOWN;allowed.add(r);}}
        if(!s.data.isEmpty()&&allowed.isEmpty())return Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");return Section.available(allowed);
    }
    public Detail detail(PortalVideoQuery q,String id){String a=authorize(q);if(!PortalQuery.id(id))throw PortalException.invalid();if(!visible(a,q.siteId,"device",id,READ))throw new PortalException(404,"OBJECT_NOT_FOUND","设备不存在或不可见");Detail d=read(()->source.detail(a,q.siteId,id));if(d==null||d.device==null||!id.equals(d.device.deviceId)||!q.siteId.equals(d.device.siteId))throw new PortalException(404,"OBJECT_NOT_FOUND","设备不存在或不可见");device(d.device,q.siteId);
        d.device.areaId=null;d.device.workId=null;
        d.person=related(d.person,a,q.siteId,"person","portal:person:read");d.equipment=related(d.equipment,a,q.siteId,"equipment","portal:person:read");d.works=related(d.works,a,q.siteId,"work","portal:work:read");d.location=related(d.location,a,q.siteId,"location","portal:location:read");d.events=related(d.events,a,q.siteId,"event","portal:event:read");d.materials=related(d.materials,a,q.siteId,"material","portal:material:read");return d;
    }
}
