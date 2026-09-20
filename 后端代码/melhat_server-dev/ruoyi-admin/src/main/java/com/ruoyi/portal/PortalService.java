package com.ruoyi.portal;

import org.springframework.stereotype.Service;
import java.util.*;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import com.ruoyi.portal.PortalModels.*;

@Service
public class PortalService {
    private final PortalSource source; private final PortalAccess access;
    public PortalService(PortalSource source,PortalAccess access) { this.source=source;this.access=access; }
    private <T> T read(Supplier<T> action) {
        try { return action.get(); } catch(PortalException e) { throw e; }
        catch(Exception e) { throw new PortalException(503,"SOURCE_UNAVAILABLE","数据源暂时不可用"); }
    }
    public Context context() {
        String actor=access.actorId();
        Context c=read(() -> source.context(actor));
        if(c==null) throw new PortalException(503,"SOURCE_UNAVAILABLE","授权上下文不完整");
        c.permissions=new ArrayList<>();
        for(String p:Arrays.asList("portal:person:read","portal:person:history","portal:location:read","portal:track:read","portal:fence:read","portal:material:read","portal:video:read","portal:event:read","portal:event:verification:read")) if(access.has(p)) c.permissions.add(p);
        if(c.selectedSiteId!=null && c.sites.stream().noneMatch(s->c.selectedSiteId.equals(s.siteId))) c.selectedSiteId=null;
        return c;
    }
    private Context authorize(PortalQuery q, boolean history) {
        access.actorId(); access.require("portal:person:read");
        if(history) access.require("portal:person:history");
        Context c=context();
        if(c.sites.stream().noneMatch(s->q.siteId.equals(s.siteId))) throw PortalException.forbidden();
        return c;
    }
    public Page<Person> people(PortalQuery q) {
        Context c=authorize(q,false);
        if(source instanceof PortalPagedSource) {
            Page<Person> result=read(()->((PortalPagedSource)source).peoplePage(access.actorId(),q));
            for(Person p:result.items)requirePerson(p,q.siteId);
            equip(result.items,q.siteId);return result;
        }
        if(q.teamId!=null && c.teams.stream().noneMatch(t->q.teamId.equals(t.teamId)&&q.siteId.equals(t.siteId))) throw PortalException.invalid();
        if(q.shiftId!=null && c.shifts.stream().noneMatch(s->q.shiftId.equals(s.shiftId)&&q.siteId.equals(s.siteId))) throw PortalException.invalid();
        if(q.shiftId==null) {
            List<Shift> shifts=c.shifts.stream().filter(s->s.isCurrent&&q.siteId.equals(s.siteId)).collect(Collectors.toList());
            if(shifts.size()==1) q.shiftId=shifts.get(0).shiftId;
        }
        if(c.availability.get("roster")!=State.AVAILABLE || q.shiftId==null)
            return page(Section.missing(q.shiftId==null?"SHIFT_UNRESOLVED":"ROSTER_NOT_INTEGRATED"),q,false);
        String actor=access.actorId();
        Section<List<Person>> section=read(()->source.roster(actor,q.siteId,q.shiftId));
        requireSection(section);
        if(section.state==State.UNAVAILABLE)throw sourceError();
        if(section.state==State.FORBIDDEN)throw PortalException.forbidden();
        if(section.state!=State.AVAILABLE) return page(section,q,false);
        List<Person> people=new ArrayList<>();
        Set<String> ids=new HashSet<>();
        for(Person p:section.data) {
            requirePerson(p,q.siteId);
            if(!ids.add(p.personId)) throw sourceError();
            if(q.teamId!=null&&(p.team==null||!q.teamId.equals(p.team.teamId)))continue;
            if(q.keyword!=null&&!q.keyword.isEmpty()&&!p.name.contains(q.keyword)&&(p.personCode==null||!p.personCode.contains(q.keyword)))continue;
            String workState=p.works.state==State.AVAILABLE?(p.works.data.isEmpty()?"IDLE":"WORKING"):"UNKNOWN";
            if(q.workState!=null&&!q.workState.equals(workState))continue;
            people.add(p);
        }
        people.sort(Comparator.comparing((Person p)->p.personCode,Comparator.nullsLast(Comparator.naturalOrder())).thenComparing(p->p.personId));
        Page<Person> result=page(Section.available(people),q,false);
        equip(result.items,q.siteId);
        for(Person p:result.items) p.actions=PortalModels.actions();
        return result;
    }
    private Person find(PortalQuery q,String id) {
        if(!PortalQuery.id(id)) throw PortalException.invalid();
        Person p=read(()->source.person(access.actorId(),q.siteId,id));
        if(p==null||!id.equals(p.personId)||!q.siteId.equals(p.siteId)) throw PortalException.missing();
        requirePerson(p,q.siteId); return p;
    }
    public Detail detail(PortalQuery q,String id) {
        authorize(q,false); Person p=find(q,id);
        equip(Collections.singletonList(p),q.siteId);
        Detail d=new Detail(); d.person=p; d.equipment=p.equipment; d.works=p.works;d.duty=p.duty;
        d.actions=PortalModels.actions();p.actions=d.actions;
        if(!access.has("portal:person:history")) {
            d.historySummary=new Section<>(State.FORBIDDEN,null,"SECTION_FORBIDDEN");
            d.actions.put("viewHistory",new Action(false,"SECTION_FORBIDDEN"));
        } else {
            try {
                if(source instanceof PortalPagedSource){d.historySummary=read(()->((PortalPagedSource)source).historySummary(access.actorId(),q.siteId,id));d.actions.put("viewHistory",new Action(true,null));return d;}
                Section<List<History>> h=historySource(q,id);
                if(h.state==State.AVAILABLE) {
                    HistorySummary summary=new HistorySummary();
                    summary.total=h.data.stream().filter(r->"CONFIRMED".equals(r.evidenceQuality)&&!"MIGRATION_SNAPSHOT".equals(r.action)).count();
                    summary.lastOccurredAt=h.data.stream().filter(r->"CONFIRMED".equals(r.evidenceQuality)&&!"MIGRATION_SNAPSHOT".equals(r.action)).map(r->r.occurredAt).filter(Objects::nonNull).max(Comparator.comparing(java.time.Instant::parse)).orElse(null);
                    d.historySummary=Section.available(summary);d.actions.put("viewHistory",new Action(true,null));
                } else d.historySummary=new Section<>(h.state,null,h.reasonCode);
            } catch(PortalException e) {
                d.historySummary=new Section<>(State.UNAVAILABLE,null,"SOURCE_UNAVAILABLE");
            }
        }
        return d;
    }
    public Page<History> history(PortalQuery q,String id) {
        authorize(q,true);find(q,id);
        if(source instanceof PortalPagedSource)return read(()->((PortalPagedSource)source).historyPage(access.actorId(),q,id));
        Section<List<History>> h=historySource(q,id);
        if(h.state==State.UNAVAILABLE)throw sourceError();
        if(h.state==State.FORBIDDEN)throw PortalException.forbidden();
        if(h.state==State.AVAILABLE) {
            List<History> rows=h.data.stream().filter(r->q.deviceType==null||q.deviceType.equals(r.deviceType.name())).collect(Collectors.toList());
            rows.sort(Comparator.comparing((History r)->r.occurredAt==null?null:java.time.Instant.parse(r.occurredAt),Comparator.nullsLast(Comparator.reverseOrder())).thenComparing(r->r.recordId));
            h=Section.available(rows);
        }
        return page(h,q,true);
    }
    private Section<List<History>> historySource(PortalQuery q,String id) {
        Section<List<History>> h=read(()->source.history(access.actorId(),q.siteId,id));requireSection(h);
        if(h.state==State.AVAILABLE) for(History r:h.data) {
            if(r==null||!id.equals(r.personId)||r.recordId==null||r.deviceType==null) throw sourceError();
            if("MIGRATION_SNAPSHOT".equals(r.action)) {
                r.occurredAt=null;r.startedAt=null;r.endedAt=null;r.state="UNKNOWN";r.evidenceQuality="CURRENT_SNAPSHOT_ONLY";
            }
            requireTime(r.occurredAt);requireTime(r.startedAt);requireTime(r.endedAt);
        }
        return h;
    }
    private void equip(List<Person> people,String site) {
        if(people.isEmpty())return;
        try {
            List<String> ids=people.stream().map(p->p.personId).collect(Collectors.toList());
            Map<String,Section<Equipment>> equipment=source.equipment(access.actorId(),site,ids);
            if(equipment==null) throw sourceError();
            Map<String,Person> owner=new HashMap<>();Set<Person> conflicts=new HashSet<>();
            for(Person p:people) {
                p.equipment=equipment.getOrDefault(p.personId,Section.missing("SOURCE_NOT_INTEGRATED"));
                requireSection(p.equipment);
                if(p.equipment.state==State.AVAILABLE) {
                    Equipment e=p.equipment.data;
                    if(e.helmet==null||e.belt==null||e.watch==null||e.helmet.type!=DeviceType.HELMET||e.belt.type!=DeviceType.BELT||e.watch.type!=DeviceType.WATCH)throw sourceError();
                    for(Slot s:Arrays.asList(e.helmet,e.belt,e.watch)) {
                        if(s==null||s.type==null||s.assignmentState==null||s.devices==null)throw sourceError();
                        int n=s.devices.size();
                        if(s.assignmentState==Assignment.ASSIGNED?n!=1:s.assignmentState==Assignment.CONFLICT?n<2:n!=0)throw sourceError();
                        for(Device device:s.devices) {
                            if(device==null||device.deviceId==null||device.type!=s.type)throw sourceError();
                            requireTime(device.communication.sourceTime);requireTime(device.communication.receivedAt);requireTime(device.communication.observedAt);
                            requireTime(device.battery.sourceTime);requireTime(device.battery.receivedAt);
                            if(device.battery.value!=null&&(!Double.isFinite(device.battery.value)||device.battery.value<0||device.battery.value>100))throw sourceError();
                            Person previous=owner.putIfAbsent(device.deviceId,p);
                            if(previous!=null&&previous!=p) { conflicts.add(previous);conflicts.add(p); }
                            if("LEGACY_SNAPSHOT".equals(device.communication.sourceKind)) device.communication.state=CommunicationState.UNKNOWN;
                            if(device.communication.sourceTime==null) device.communication.freshness=device.communication.state==CommunicationState.NOT_INTEGRATED?Freshness.NOT_APPLICABLE:Freshness.UNKNOWN;
                            if(device.battery.sourceTime==null) device.battery.freshness=device.battery.freshness==Freshness.NOT_APPLICABLE?Freshness.NOT_APPLICABLE:Freshness.UNKNOWN;
                            if(device.communication.sourceTime!=null&&java.time.Instant.parse(device.communication.sourceTime).isAfter(java.time.Instant.now()))device.communication.freshness=Freshness.UNKNOWN;
                            if(device.battery.sourceTime!=null&&java.time.Instant.parse(device.battery.sourceTime).isAfter(java.time.Instant.now()))device.battery.freshness=Freshness.UNKNOWN;
                            if(device.type!=DeviceType.HELMET) {
                                device.communication=new Communication();
                                device.communication.state=CommunicationState.NOT_INTEGRATED;
                                device.communication.freshness=Freshness.NOT_APPLICABLE;
                                device.communication.reasonCode="PROTOCOL_PENDING";
                                device.battery=new Reading();device.battery.freshness=Freshness.NOT_APPLICABLE;device.battery.reasonCode="PROTOCOL_PENDING";
                                for(Capability cap:device.capabilities.values()) { cap.state=CapabilityState.UNKNOWN;cap.verification="UNVERIFIED";cap.reasonCode="PROTOCOL_PENDING"; }
                                device.manufacturerExtensions.clear();
                            }
                        }
                    }
                }
            }
            for(Person p:conflicts)p.equipment=new Section<>(State.UNAVAILABLE,null,"ASSIGNMENT_CONFLICT");
        } catch(Exception e) { for(Person p:people)p.equipment=new Section<>(State.UNAVAILABLE,null,"SOURCE_UNAVAILABLE"); }
    }
    private void requirePerson(Person p,String site) {
        if(p==null||!PortalQuery.id(p.personId)||!site.equals(p.siteId)||p.name==null||p.name.trim().isEmpty()) throw sourceError();
        requireSection(p.works); requireSection(p.duty);
        requireTime(p.dataUpdatedAt);
    }
    private void requireTime(String value) {
        if(value==null)return;
        try { if(!value.endsWith("Z"))throw sourceError();java.time.Instant.parse(value); }
        catch(java.time.format.DateTimeParseException e) {throw sourceError();}
    }
    private void requireSection(Section<?> s) {
        if(s==null||s.state==null||(s.state==State.AVAILABLE?s.data==null:s.data!=null||s.reasonCode==null))throw sourceError();
    }
    private PortalException sourceError() {return new PortalException(503,"SOURCE_UNAVAILABLE","数据来源或归属不完整");}
    private <T> Page<T> page(Section<List<T>> section,PortalQuery q,boolean history) {
        requireSection(section);
        Page<T> result=new Page<>();result.state=section.state;result.reasonCode=section.reasonCode;
        result.pageNum=q.pageNum;result.pageSize=q.pageSize;result.scope.put("siteId",q.siteId);
        if(!history)result.scope.put("shiftId",q.shiftId);
        if(section.state==State.AVAILABLE) {
            result.total=(long)section.data.size();
            long start=(long)(q.pageNum-1)*q.pageSize;
            if(start<section.data.size())result.items=new ArrayList<>(section.data.subList((int)start,(int)Math.min(start+q.pageSize,section.data.size())));
        }
        return result;
    }
}
