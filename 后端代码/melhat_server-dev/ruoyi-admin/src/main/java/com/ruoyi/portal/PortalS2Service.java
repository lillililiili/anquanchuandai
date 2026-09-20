package com.ruoyi.portal;
import java.util.*;
import java.time.Instant;
import java.util.function.*;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.portal.PortalS2Models.*;

@Service
public class PortalS2Service {
    private final PortalAccess access; private final PortalSource context;
    private final PortalSpatialSource spatial; private final PortalMaterialSource media;
    public PortalS2Service(PortalAccess a,PortalSource c,PortalSpatialSource s,PortalMaterialSource m) {access=a;context=c;spatial=s;media=m;}
    private PortalException badSource() {return new PortalException(503,"SOURCE_UNAVAILABLE","数据来源或范围不完整");}
    private PortalException missing() {return new PortalException(404,"OBJECT_NOT_FOUND","对象不存在或不可见");}
    private <T> T read(Supplier<T> call) {try {return call.get();}catch(PortalException e){throw e;}catch(Exception e){throw badSource();}}
    private String authorize(PortalS2Query q,String permission) {
        String actor=access.actorId(); if(permission!=null)access.require(permission);
        Context c=read(()->context.context(actor));
        if(c==null||c.sites==null)throw badSource();
        if(c.sites.stream().noneMatch(s->q.siteId.equals(s.siteId)))throw PortalException.forbidden();
        return actor;
    }
    private void object(String actor,String site,String kind,String id,String permission) {
        if(!PortalQuery.id(id))throw PortalException.invalid();
        if(!read(()->spatial.visible(actor,site,kind,id,permission)))throw missing();
    }
    private <T> Section<T> section(Section<T> s) {
        if(s==null||s.state==null||(s.state==State.AVAILABLE?s.data==null:s.data!=null||s.reasonCode==null))throw badSource();
        if(s.state==State.UNAVAILABLE)throw badSource();
        if(s.state==State.FORBIDDEN)throw PortalException.forbidden();return s;
    }
    private void item(Item i,String site) {if(i==null||!PortalQuery.id(i.id)||!site.equals(i.siteId)||i.name==null)throw badSource();}
    private void time(String t) {if(t!=null)try {if(!t.endsWith("Z"))throw badSource();Instant.parse(t);}catch(Exception e){throw badSource();}}
    private void position(Position p) {
        if(p==null)return;time(p.sourceTime);time(p.receivedAt);
        if(p.sourceTime==null||Instant.parse(p.sourceTime).isAfter(Instant.now()))p.freshness=Freshness.UNKNOWN;
        if(p.freshness==null) p.freshness=Freshness.UNKNOWN;
    }
    private <T extends Item> Page<T> page(Section<List<T>> s,PortalS2Query q,Predicate<T> filter) {
        section(s);Page<T> p=new Page<>();p.state=s.state;p.reasonCode=s.reasonCode;p.pageNum=q.pageNum;p.pageSize=q.pageSize;p.scope.put("siteId",q.siteId);
        if(s.state==State.AVAILABLE) {
            Set<String> ids=new HashSet<>();for(T i:s.data){item(i,q.siteId);if(!ids.add(i.id))throw badSource();}
            List<T> rows=s.data.stream().filter(filter).filter(i->q.keyword==null||i.name.contains(q.keyword)||i.id.contains(q.keyword)).sorted(Comparator.comparing(i->i.id)).collect(Collectors.toList());
            p.total=(long)rows.size();long start=(long)(q.pageNum-1)*q.pageSize;
            if(start<rows.size())p.items=new ArrayList<>(rows.subList((int)start,(int)Math.min(start+q.pageSize,rows.size())));
        }return p;
    }
    public Page<DeviceOption> devices(PortalS2Query q) {
        String a=authorize(q,null);Set<String> permissions=new HashSet<>();
        for(String p:Arrays.asList("portal:location:read","portal:track:read","portal:material:read"))if(access.has(p))permissions.add(p);
        if(permissions.isEmpty())throw PortalException.forbidden();
        Section<List<DeviceOption>> s=section(read(()->spatial.devices(a,q.siteId,permissions)));
        if(s.state==State.AVAILABLE)for(DeviceOption d:s.data){item(d,q.siteId);if(d.type==null)throw badSource();}
        return page(s,q,i->permissions.stream().anyMatch(p->read(()->spatial.visible(a,q.siteId,"device",i.id,p))));
    }
    public Page<LocatedDevice> locations(PortalS2Query q) {
        String p="portal:location:read",a=authorize(q,p);
        Section<List<LocatedDevice>> s=section(read(()->spatial.locations(a,q.siteId)));
        if(s.state==State.AVAILABLE) for(LocatedDevice i:s.data) {
            item(i,q.siteId);if(!PortalQuery.id(i.deviceId))throw badSource();position(i.position);
            if(!"CONFIRMED".equals(i.attribution)||i.personId==null||!read(()->spatial.visible(a,q.siteId,"person",i.personId,p))){i.personId=null;i.personName=null;i.attribution="UNKNOWN";}
        }
        return page(s,q,i->read(()->spatial.visible(a,q.siteId,"device",i.deviceId,p)));
    }
    public Section<Track> tracks(PortalS2Query q) {
        String p="portal:track:read",a=authorize(q,p);object(a,q.siteId,"device",q.deviceId,p);
        if(q.personId!=null)object(a,q.siteId,"person",q.personId,p);
        Section<Track> s=section(read(()->spatial.tracks(a,q.siteId,q.deviceId,q.from,q.to)));
        if(s.state!=State.AVAILABLE)return s;
        Track t=s.data;item(t,q.siteId);
        if(!q.deviceId.equals(t.deviceId)||!q.from.equals(t.from)||!q.to.equals(t.to)||t.segments==null||t.gaps==null||(!t.complete&&t.incompleteReason==null))throw badSource();
        if(!"CONFIRMED".equals(t.attribution)||t.personId==null||!read(()->spatial.visible(a,q.siteId,"person",t.personId,p))){t.personId=null;t.attribution="UNKNOWN";}
        if(q.personId!=null&&!q.personId.equals(t.personId))return Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");
        int count=0;Instant previous=null;
        for(Segment segment:t.segments) {
            if(segment==null||!PortalQuery.id(segment.segmentId)||segment.points==null||!Arrays.asList("CONFIRMED","UNKNOWN").contains(segment.continuity))throw badSource();
            for(Position point:segment.points) {
                if(point==null)throw badSource();position(point);count++;
                if(point.sourceTime!=null) {Instant at=Instant.parse(point.sourceTime);if(at.isBefore(Instant.parse(q.from))||at.isAfter(Instant.parse(q.to))||(previous!=null&&at.isBefore(previous)))throw badSource();previous=at;}
            }
        }
        if(count>10000)throw new PortalException(422,"RESULT_TOO_LARGE","轨迹点超过 10000，请缩小查询时间范围");
        for(Gap gap:t.gaps){if(gap==null||gap.from==null||gap.to==null)throw badSource();time(gap.from);time(gap.to);if(!Instant.parse(gap.from).isBefore(Instant.parse(gap.to))||Instant.parse(gap.from).isBefore(Instant.parse(q.from))||Instant.parse(gap.to).isAfter(Instant.parse(q.to)))throw badSource();}
        return s;
    }
    private void fenceFields(Fence f){time(f.sourceTime);time(f.effectiveAt);if(!Arrays.asList("ENABLED","DISABLED","UNKNOWN").contains(f.status)||f.ring==null)throw badSource();}
    public Page<Fence> fences(PortalS2Query q) {
        String p="portal:fence:read",a=authorize(q,p);Section<List<Fence>> s=section(read(()->spatial.fences(a,q.siteId)));
        if(s.state==State.AVAILABLE)for(Fence f:s.data){item(f,q.siteId);fenceFields(f);}
        return page(s,q,i->read(()->spatial.visible(a,q.siteId,"fence",i.id,p))&&(q.status==null||q.status.equals(i.status)));
    }
    public Fence fence(PortalS2Query q,String id) {
        String p="portal:fence:read",a=authorize(q,p);object(a,q.siteId,"fence",id,p);
        Fence f=read(()->spatial.fence(a,q.siteId,id));if(f==null||!id.equals(f.id)||!q.siteId.equals(f.siteId))throw missing();item(f,q.siteId);fenceFields(f);return f;
    }
    private void mediaObject(String a,String site,String kind,String id) {
        if(!PortalQuery.id(id))throw PortalException.invalid();if(!read(()->media.visible(a,site,kind,id)))throw missing();
    }
    private void materialFields(Material m,String a,String site) {
        item(m,site);time(m.capturedAt);time(m.receivedAt);
        if(!Arrays.asList("PHOTO","VIDEO","AUDIO").contains(m.type))throw badSource();
        if(m.deviceId!=null&&!read(()->media.visible(a,site,"device",m.deviceId))){m.deviceId=null;m.deviceCode=null;}
        if(!"CONFIRMED".equals(m.attribution)||m.personId==null||!read(()->media.visible(a,site,"person",m.personId))){m.personId=null;m.personName=null;m.attribution="UNKNOWN";}
        if(!"CONFIRMED".equals(m.workAttribution)||m.workId==null||!read(()->media.visible(a,site,"work",m.workId))){m.workId=null;m.workAttribution="UNKNOWN";}
        if(!"CONFIRMED".equals(m.eventAttribution)||m.eventId==null||!read(()->media.visible(a,site,"event",m.eventId))){m.eventId=null;m.eventAttribution="UNKNOWN";}
        m.accessReason="FILE_ACCESS_NOT_ENABLED";
    }
    public Page<Material> materials(PortalS2Query q) {
        String a=authorize(q,"portal:material:read");
        if(q.deviceId!=null)mediaObject(a,q.siteId,"device",q.deviceId);
        if(q.personId!=null)mediaObject(a,q.siteId,"person",q.personId);
        Section<List<Material>> s=section(read(()->media.materials(a,q.siteId)));
        if(s.state==State.AVAILABLE)for(Material m:s.data)materialFields(m,a,q.siteId);
        return page(s,q,m->read(()->media.visible(a,q.siteId,"material",m.id))&&(q.deviceId==null||q.deviceId.equals(m.deviceId))&&(q.personId==null||q.personId.equals(m.personId))&&(q.type==null||q.type.equals(m.type))&&(q.from==null||(m.capturedAt!=null&&!Instant.parse(m.capturedAt).isBefore(Instant.parse(q.from))&&!Instant.parse(m.capturedAt).isAfter(Instant.parse(q.to)))));
    }
    public Material material(PortalS2Query q,String id) {
        String a=authorize(q,"portal:material:read");mediaObject(a,q.siteId,"material",id);
        Material m=read(()->media.material(a,q.siteId,id));if(m==null||!id.equals(m.id)||!q.siteId.equals(m.siteId))throw missing();materialFields(m,a,q.siteId);return m;
    }
}
