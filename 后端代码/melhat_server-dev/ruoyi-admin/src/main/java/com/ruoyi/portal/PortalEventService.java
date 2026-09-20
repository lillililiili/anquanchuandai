package com.ruoyi.portal;
import java.time.Instant;
import java.util.*;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.portal.PortalEventModels.*;
import com.ruoyi.portal.PortalEventModels.Detail;
import com.ruoyi.portal.PortalEventModels.Record;

@Service
public class PortalEventService {
    private static final String READ="portal:event:read",VERIFY="portal:event:verification:read";
    private final PortalAccess access;private final PortalSource context;private final PortalEventSource source;
    public PortalEventService(PortalAccess a,PortalSource c,PortalEventSource s){access=a;context=c;source=s;}
    private PortalException fault(){return new PortalException(503,"SOURCE_UNAVAILABLE","事件来源或范围证据不完整");}
    private PortalException missing(){return new PortalException(404,"OBJECT_NOT_FOUND","事件不存在或不可见");}
    private <T>T read(Supplier<T> fn){try{return fn.get();}catch(PortalException e){throw e;}catch(Exception e){throw fault();}}
    private String authorize(PortalEventQuery q,boolean verification){String a=access.actorId();access.require(READ);if(verification)access.require(VERIFY);Context c=read(()->context.context(a));if(c==null||c.sites==null)throw fault();if(c.sites.stream().noneMatch(s->q.siteId.equals(s.siteId)))throw PortalException.forbidden();return a;}
    private boolean visible(String a,String site,String kind,String id,String p){return PortalQuery.id(id)&&read(()->source.visible(a,site,kind,id,p));}
    private void eventScope(String a,String site,String id){if(!PortalQuery.id(id))throw PortalException.invalid();if(!visible(a,site,"event",id,READ))throw missing();}
    private void time(String t){if(t!=null)try{if(!t.endsWith("Z"))throw fault();Instant.parse(t);}catch(RuntimeException e){throw fault();}}
    private <T>Section<T> section(Section<T>s){if(s==null||s.state==null||(s.state==State.AVAILABLE?s.data==null:s.data!=null||s.reasonCode==null))throw fault();return s;}
    private <T>Section<T> main(Section<T>s){section(s);if(s.state==State.UNAVAILABLE)throw fault();if(s.state==State.FORBIDDEN)throw PortalException.forbidden();return s;}
    private <T>Section<T> denied(){return new Section<>(State.FORBIDDEN,null,"SECTION_FORBIDDEN");}
    private boolean proof(String attribution,String evidence){return "CONFIRMED".equals(attribution)&&evidence!=null&&!evidence.trim().isEmpty();}
    private Section<List<Ref>> refs(Section<List<Ref>>s,String a,String site,String kind,String permission){
        if(!access.has(permission))return denied();section(s);if(s.state!=State.AVAILABLE)return s;List<Ref> out=new ArrayList<>();
        for(Ref r:s.data){if(r==null||!site.equals(r.siteId)||!PortalQuery.id(r.id)||r.name==null)throw fault();time(r.sourceTime);if(!Arrays.asList("UNKNOWN","HISTORICAL","CURRENT").contains(r.snapshotKind))throw fault();if(proof(r.attribution,r.evidenceId)&&visible(a,site,kind,r.id,permission))out.add(r);}
        return !s.data.isEmpty()&&out.isEmpty()?Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN"):Section.available(out);
    }
    private void fact(Fact f,String a,String site){
        if(f==null||!PortalQuery.id(f.eventId)||!site.equals(f.siteId)||f.title==null||f.sourceSystem==null||f.sourceSystem.trim().isEmpty()||f.sourceEventId==null||f.sourceEventId.trim().isEmpty()||!PortalQuery.id(f.eventType)||f.phase==null)throw fault();
        time(f.occurredAt);time(f.receivedAt);time(f.sourceUpdatedAt);if(f.sourceUpdatedAt==null)f.freshness=Freshness.UNKNOWN;
        f.person=refs(f.person,a,site,"person","portal:person:read");
        if(f.deviceId==null||!visible(a,site,"device",f.deviceId,READ)){f.deviceId=null;f.deviceCode=null;}
    }
    private Filters filters(String a,PortalEventQuery q){Filters f=read(()->source.filters(a,q.siteId));if(f==null)throw fault();section(f.eventTypes);
        if(q.keyword!=null&&!q.keyword.isEmpty()&&!f.keyword||q.from!=null&&!f.timeRange||q.phase!=null&&!f.phase||q.eventType!=null&&f.eventTypes.state!=State.AVAILABLE)throw new PortalException(400,"FILTER_NOT_SUPPORTED","该筛选来源尚未接入");
        if(f.eventTypes.state==State.AVAILABLE){Set<String> values=new HashSet<>();for(Option o:f.eventTypes.data)if(o==null||!PortalQuery.id(o.value)||o.label==null||!values.add(o.value))throw fault();if(q.eventType!=null&&!values.contains(q.eventType))throw PortalException.invalid();}return f;
    }
    private Section<List<Fact>> rows(String a,PortalEventQuery q){Section<List<Fact>>s=main(read(()->source.events(a,q.siteId)));if(s.state!=State.AVAILABLE)return s;Map<String,Fact> ids=new TreeMap<>();Map<String,String> origins=new HashMap<>();
        for(Fact f:s.data){fact(f,a,q.siteId);if(!visible(a,q.siteId,"event",f.eventId,READ))continue;String origin=f.sourceSystem.length()+":"+f.sourceSystem+f.sourceEventId;String existing=origins.putIfAbsent(origin,f.eventId);if(existing!=null&&!existing.equals(f.eventId))throw fault();Fact duplicate=ids.putIfAbsent(f.eventId,f);if(duplicate!=null&&(!duplicate.sourceSystem.equals(f.sourceSystem)||!duplicate.sourceEventId.equals(f.sourceEventId)||duplicate.phase!=f.phase))throw fault();}
        return Section.available(ids.values().stream().filter(f->(q.keyword==null||q.keyword.isEmpty()||f.deviceCode!=null&&f.deviceCode.contains(q.keyword))&&(q.eventType==null||q.eventType.equals(f.eventType))&&(q.phase==null||q.phase==f.phase)&&(q.from==null||f.occurredAt!=null&&!Instant.parse(f.occurredAt).isBefore(Instant.parse(q.from))&&Instant.parse(f.occurredAt).isBefore(Instant.parse(q.to)))).sorted(Comparator.comparing((Fact f)->f.occurredAt==null?null:Instant.parse(f.occurredAt),Comparator.nullsLast(Comparator.reverseOrder())).thenComparing(f->f.eventId)).collect(Collectors.toList()));
    }
    private <T>Page<T> page(Section<List<T>>s,PortalEventQuery q,String eventId){Page<T>p=new Page<>();p.state=s.state;p.reasonCode=s.reasonCode;p.pageNum=q.pageNum;p.pageSize=q.pageSize;p.scope.put("siteId",q.siteId);if(eventId!=null)p.scope.put("eventId",eventId);if(s.state==State.AVAILABLE){p.total=(long)s.data.size();long start=(long)(q.pageNum-1)*q.pageSize;if(start<s.data.size())p.items=new ArrayList<>(s.data.subList((int)start,(int)Math.min(start+q.pageSize,s.data.size())));}return p;}
    public EventPage list(PortalEventQuery q){String a=authorize(q,false);Filters f=filters(a,q);Page<Fact>p=page(rows(a,q),q,null);EventPage r=new EventPage();r.state=p.state;r.reasonCode=p.reasonCode;r.pageNum=p.pageNum;r.pageSize=p.pageSize;r.total=p.total;r.items=p.items;r.scope=p.scope;r.filters=f;return r;}
    public Section<Statistics> summary(PortalEventQuery q){String a=authorize(q,false);filters(a,q);Section<List<Fact>>rows=rows(a,q);if(rows.state!=State.AVAILABLE)return Section.missing(rows.reasonCode);Section<StatisticsEvidence>s=main(read(()->source.statistics(a,q)));if(s.state!=State.AVAILABLE)return new Section<>(s.state,null,s.reasonCode);Map<String,Phase>expected=new LinkedHashMap<>();for(Fact f:rows.data)expected.put(f.eventId,f.phase);if(s.data.events==null||!expected.equals(s.data.events))throw fault();time(s.data.sourceTime);Statistics n=new Statistics();n.sourceTime=s.data.sourceTime;n.total=expected.size();for(Phase p:Phase.values())n.counts.put(p,expected.values().stream().filter(v->v==p).count());return Section.available(n);}
    private Section<List<Evidence>> evidence(Section<List<Evidence>>s,String a,String site){if(!access.has("portal:material:read"))return denied();section(s);if(s.state!=State.AVAILABLE)return s;List<Evidence>out=new ArrayList<>();for(Evidence e:s.data){if(e==null||!site.equals(e.siteId)||!PortalQuery.id(e.id)||e.name==null)throw fault();time(e.capturedAt);time(e.receivedAt);if(proof(e.attribution,e.evidenceId)&&visible(a,site,"material",e.id,"portal:material:read"))out.add(e);}return !s.data.isEmpty()&&out.isEmpty()?Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN"):Section.available(out);}
    private void delivery(Section<Delivery>s){section(s);if(s.state==State.AVAILABLE){if(s.data.state==null)throw fault();time(s.data.sourceTime);}}
    public Detail detail(PortalEventQuery q,String id){String a=authorize(q,false);eventScope(a,q.siteId,id);Detail d=read(()->source.detail(a,q.siteId,id));if(d==null||d.event==null||!id.equals(d.event.eventId)||!q.siteId.equals(d.event.siteId))throw missing();fact(d.event,a,q.siteId);
        d.owner=refs(d.owner,a,q.siteId,"person","portal:person:read");d.equipment=refs(d.equipment,a,q.siteId,"device","portal:person:read");d.works=refs(d.works,a,q.siteId,"work","portal:work:read");d.video=refs(d.video,a,q.siteId,"device","portal:video:read");d.materials=evidence(d.materials,a,q.siteId);
        if(!access.has("portal:location:read"))d.location=denied();else{section(d.location);if(d.location.state==State.AVAILABLE){Position p=d.location.data;if(!q.siteId.equals(p.siteId)||!PortalQuery.id(p.id))throw fault();time(p.sourceTime);time(p.receivedAt);if(p.sourceTime==null)p.freshness=Freshness.UNKNOWN;if(!proof(p.attribution,p.evidenceId)||!visible(a,q.siteId,"location",p.id,"portal:location:read"))d.location=Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");}}
        delivery(d.summaryDelivery);if(!access.has(VERIFY))d.verificationDelivery=denied();else delivery(d.verificationDelivery);section(d.originalSystem);if(d.originalSystem.state==State.AVAILABLE)time(d.originalSystem.data.sourceTime);return d;
    }
    private <T extends Record>Section<List<T>> records(Section<List<T>>s,String a,PortalEventQuery q,String id,String kind,String permission){main(s);if(s.state!=State.AVAILABLE)return s;Set<String>ids=new HashSet<>();List<T>out=new ArrayList<>();for(T r:s.data){if(r==null||!PortalQuery.id(r.id)||!q.siteId.equals(r.siteId)||!id.equals(r.eventId)||!ids.add(r.id))throw fault();time(r.sourceTime);if(visible(a,q.siteId,kind,r.id,permission))out.add(r);}return Section.available(out);}
    public Page<Timeline> timeline(PortalEventQuery q,String id){String a=authorize(q,false);eventScope(a,q.siteId,id);Section<List<Timeline>>s=records(read(()->source.timeline(a,q.siteId,id)),a,q,id,"timeline",READ);if(s.state==State.AVAILABLE){for(Timeline t:s.data)if(t.title==null||t.kind==null||t.sequence<0)throw fault();s.data.sort(Comparator.comparingLong((Timeline t)->t.sequence).thenComparing(t->t.id));}return page(s,q,id);}
    public Page<Verification> verifications(PortalEventQuery q,String id){String a=authorize(q,true);eventScope(a,q.siteId,id);Section<List<Verification>>s=records(read(()->source.verifications(a,q.siteId,id)),a,q,id,"verification",VERIFY);if(s.state==State.AVAILABLE){for(Verification v:s.data){if(v.state==null)throw fault();time(v.submittedAt);if(v.state==VerificationState.DRAFT&&v.submittedAt!=null)throw fault();v.evidence=evidence(v.evidence,a,q.siteId);}s.data.sort(Comparator.comparing((Verification v)->v.sourceTime==null?null:Instant.parse(v.sourceTime),Comparator.nullsLast(Comparator.reverseOrder())).thenComparing(v->v.id));}return page(s,q,id);}
}
