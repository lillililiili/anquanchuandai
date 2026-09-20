package com.ruoyi.portal.demo;
import java.util.*;
import java.sql.Timestamp;
import org.springframework.context.annotation.*;
import org.springframework.stereotype.Component;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ruoyi.portal.*;
import com.ruoyi.portal.PortalModels.*;

@Component @Primary @Profile("portal-demo")
public class DemoPeopleSource implements PortalPagedSource {
    private final JdbcTemplate db;
    public DemoPeopleSource(JdbcTemplate db){this.db=db;}
    public void scope(String actor,String site){if(db.queryForObject("SELECT COUNT(*) FROM portal_site_grant WHERE actor_id=? AND site_id=?",Integer.class,actor,site)==0)throw PortalException.forbidden();}
    @Override public Context context(String actor){
        Context c=new Context();
        c.sites=db.query("SELECT s.* FROM portal_site s JOIN portal_site_grant g ON s.id=g.site_id WHERE g.actor_id=? ORDER BY s.id",(r,n)->{Site s=new Site();s.siteId=r.getString("id");s.name=r.getString("name");s.timeZone=r.getString("time_zone");return s;},actor);
        c.selectedSiteId=c.sites.isEmpty()?null:c.sites.get(0).siteId;
        for(Site site:c.sites){
            c.areas.addAll(db.query("SELECT * FROM portal_area WHERE site_id=?",(r,n)->{Area a=new Area();a.areaId=r.getString("id");a.siteId=site.siteId;a.name=r.getString("name");return a;},site.siteId));
            c.teams.addAll(db.query("SELECT * FROM portal_team WHERE site_id=?",(r,n)->{Team t=new Team();t.teamId=r.getString("id");t.siteId=site.siteId;t.name=r.getString("name");return t;},site.siteId));
            c.shifts.addAll(db.query("SELECT * FROM portal_shift WHERE site_id=?",(r,n)->{Shift s=new Shift();s.shiftId=r.getString("id");s.siteId=site.siteId;s.name=r.getString("name");s.isCurrent=r.getBoolean("is_current");return s;},site.siteId));
        }
        c.availability.replaceAll((k,v)->State.AVAILABLE);
        for(String key:Arrays.asList("people","equipmentHistory","devices")){Capability cap=new Capability();cap.state=CapabilityState.SUPPORTED;cap.verification="VERIFIED";cap.reasonCode="SIMULATED";c.capabilities.put(key,cap);}
        return c;
    }
    private Person personRow(java.sql.ResultSet r)throws java.sql.SQLException {
        Person p=new Person();p.personId=r.getString("id");p.personCode=r.getString("code");p.name=r.getString("name");p.siteId=r.getString("site_id");
        p.team=new Team();p.team.teamId=r.getString("team_id");p.team.siteId=p.siteId;p.team.name="模拟检修班组";
        p.area=new Area();p.area.areaId=r.getString("area_id");p.area.siteId=p.siteId;p.area.name="模拟作业区";
        Duty d=new Duty();d.shiftId=r.getString("shift_id");d.state="ON_DUTY";p.duty=Section.available(d);p.works=Section.available(new ArrayList<>());return p;
    }
    @Override public Person person(String actor,String site,String id){scope(actor,site);List<Person> rows=db.query("SELECT * FROM portal_person WHERE site_id=? AND id=?",(r,n)->personRow(r),site,id);return rows.isEmpty()?null:rows.get(0);}
    @Override public Page<Person> peoplePage(String actor,PortalQuery q){
        scope(actor,q.siteId);String where=" FROM portal_person p WHERE site_id=?";List<Object> args=new ArrayList<>();args.add(q.siteId);
        if(q.teamId!=null){if(db.queryForObject("SELECT COUNT(*) FROM portal_team WHERE site_id=? AND id=?",Integer.class,q.siteId,q.teamId)==0)throw PortalException.invalid();where+=" AND team_id=?";args.add(q.teamId);}
        if(q.shiftId!=null){if(db.queryForObject("SELECT COUNT(*) FROM portal_shift WHERE site_id=? AND id=?",Integer.class,q.siteId,q.shiftId)==0)throw PortalException.invalid();where+=" AND shift_id=?";args.add(q.shiftId);}
        if(q.keyword!=null&&!q.keyword.isEmpty()){where+=" AND (LOCATE(?,name)>0 OR LOCATE(?,code)>0)";args.add(q.keyword);args.add(q.keyword);}
        if(q.workState!=null&&!"IDLE".equals(q.workState))where+=" AND 1=0";
        Page<Person> p=page(q,null);p.total=db.queryForObject("SELECT COUNT(*)"+where,Long.class,args.toArray());args.add(q.pageSize);args.add((long)(q.pageNum-1)*q.pageSize);
        p.items=db.query("SELECT p.*"+where+" ORDER BY code,id LIMIT ? OFFSET ?",(r,n)->personRow(r),args.toArray());return p;
    }
    private <T>Page<T> page(PortalQuery q,String person){Page<T> p=new Page<>();p.state=State.AVAILABLE;p.pageNum=q.pageNum;p.pageSize=q.pageSize;p.scope.put("siteId",q.siteId);if(person==null)p.scope.put("shiftId",q.shiftId);return p;}
    @Override public Section<List<Person>> roster(String a,String s,String shift){throw new UnsupportedOperationException("Use database paging");}
    @Override public Map<String,Section<Equipment>> equipment(String actor,String site,List<String> ids){
        scope(actor,site);Map<String,Section<Equipment>> result=new LinkedHashMap<>();
        for(String id:ids){Equipment e=new Equipment();for(DeviceType type:DeviceType.values()){
            Slot slot=new Slot();slot.type=type;slot.assignmentState=Assignment.UNASSIGNED;slot.reasonCode=null;
            slot.devices=db.query("SELECT d.* FROM portal_device d JOIN portal_assignment a ON a.device_id=d.id WHERE a.site_id=? AND a.person_id=? AND a.device_type=? AND a.ended_at IS NULL",(r,n)->{Device d=new Device();d.deviceId=r.getString("id");d.deviceCode=r.getString("code");d.type=type;d.model="模拟装备，厂家协议待确认";d.communication.state=CommunicationState.valueOf(r.getString("communication"));d.communication.sourceKind="SIMULATED";Timestamp t=r.getTimestamp("source_time");d.communication.sourceTime=t==null?null:t.toInstant().toString();d.communication.freshness=Freshness.UNKNOWN;return d;},site,id,type.name());
            if(!slot.devices.isEmpty())slot.assignmentState=slot.devices.size()>1?Assignment.CONFLICT:Assignment.ASSIGNED;
            if(type==DeviceType.HELMET)e.helmet=slot;else if(type==DeviceType.BELT)e.belt=slot;else e.watch=slot;
        }result.put(id,Section.available(e));}return result;
    }
    @Override public Section<List<History>> history(String a,String s,String p){throw new UnsupportedOperationException("Use database paging");}
    @Override public Section<HistorySummary> historySummary(String a,String s,String p){scope(a,s);HistorySummary h=new HistorySummary();h.total=db.queryForObject("SELECT COUNT(*) FROM portal_assignment_history WHERE site_id=? AND person_id=?",Long.class,s,p);Timestamp t=db.queryForObject("SELECT MAX(occurred_at) FROM portal_assignment_history WHERE site_id=? AND person_id=?",Timestamp.class,s,p);h.lastOccurredAt=t==null?null:t.toInstant().toString();return Section.available(h);}
    @Override public Page<History> historyPage(String actor,PortalQuery q,String id){scope(actor,q.siteId);Page<History> p=page(q,id);List<Object>args=new ArrayList<>(Arrays.asList(q.siteId,id));String where=" FROM portal_assignment_history h JOIN portal_assignment a ON a.id=h.assignment_id JOIN portal_device d ON d.id=h.device_id WHERE h.site_id=? AND h.person_id=?";
        if(q.deviceType!=null){where+=" AND d.type=?";args.add(q.deviceType);}p.total=db.queryForObject("SELECT COUNT(*)"+where,Long.class,args.toArray());args.add(q.pageSize);args.add((long)(q.pageNum-1)*q.pageSize);
        p.items=db.query("SELECT h.*,a.started_at,a.ended_at,d.code,d.type"+where+" ORDER BY h.occurred_at DESC,h.id LIMIT ? OFFSET ?",(r,n)->{History h=new History();h.recordId=r.getString("id");h.relationId=r.getString("assignment_id");h.personId=id;h.deviceId=r.getString("device_id");h.deviceCode=r.getString("code");h.deviceType=DeviceType.valueOf(r.getString("type"));h.action=r.getString("action");h.occurredAt=r.getTimestamp("occurred_at").toInstant().toString();h.startedAt=r.getTimestamp("started_at").toInstant().toString();Timestamp end=r.getTimestamp("ended_at");h.endedAt=end==null?null:end.toInstant().toString();h.state=end==null?"OPEN":"CLOSED";h.evidenceQuality="CONFIRMED";return h;},args.toArray());return p;}
}
