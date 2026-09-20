package com.ruoyi.portal;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;
import java.util.*;
/** S1 public DTOs. IDs are strings; unknown timestamps/values remain null. */
public final class PortalModels {
    private PortalModels() {}
    public enum State { AVAILABLE, NOT_INTEGRATED, UNAVAILABLE, FORBIDDEN }
    public enum Assignment { ASSIGNED, UNASSIGNED, UNKNOWN, CONFLICT }
    public enum CommunicationState { ONLINE, OFFLINE, UNKNOWN, NOT_INTEGRATED }
    public enum Freshness { FRESH, STALE, UNKNOWN, NOT_APPLICABLE }
    public enum DeviceType { HELMET, BELT, WATCH }
    public enum CapabilityState { SUPPORTED, UNSUPPORTED, UNKNOWN }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Envelope<T> {
        public int code; public String msg, errorCode, requestId, asOf; public T data;
        public Envelope(int code, String msg, String errorCode, T data) {
            this.code=code; this.msg=msg; this.errorCode=errorCode; this.data=data;
            this.requestId=UUID.randomUUID().toString(); this.asOf=Instant.now().toString();
        }
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Section<T> {
        public State state; public T data; public String reasonCode;
        public Section() {}
        public Section(State state, T data, String reason) { this.state=state; this.data=data; this.reasonCode=reason; }
        public static <T> Section<T> missing(String reason) { return new Section<>(State.NOT_INTEGRATED,null,reason); }
        public static <T> Section<T> available(T data) { return new Section<>(State.AVAILABLE,data,null); }
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Page<T> {
        public State state; public String reasonCode; public List<T> items = new ArrayList<>();
        public Long total; public int pageNum, pageSize; public Map<String,String> scope=new LinkedHashMap<>();
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Capability {
        public CapabilityState state=CapabilityState.UNKNOWN; public String reasonCode="SOURCE_NOT_INTEGRATED";
        public String verification="UNVERIFIED";
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Site { public String siteId, name, timeZone; }
    public static class Area { public String areaId, siteId, name; }
    public static class Team { public String teamId, siteId, name; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Shift { public String shiftId, siteId, name, startsAt, endsAt; public boolean isCurrent; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Context {
        public List<Site> sites=new ArrayList<>(); public String selectedSiteId;
        public List<Area> areas=new ArrayList<>(); public List<Team> teams=new ArrayList<>();
        public List<Shift> shifts=new ArrayList<>();
        public Map<String,State> availability=new LinkedHashMap<>();
        public Map<String,Capability> capabilities=new LinkedHashMap<>();
        public List<String> permissions=new ArrayList<>();
        public Context() {
            for(String key:Arrays.asList("roster","areas","teams","shifts")) availability.put(key,State.NOT_INTEGRATED);
            Capability people=new Capability(); people.reasonCode="SITE_SCOPE_NOT_INTEGRATED";
            capabilities.put("people",people);
            Capability history=new Capability(); history.reasonCode="HISTORY_NOT_INTEGRATED";
            capabilities.put("equipmentHistory",history);
            for(String k:Arrays.asList("locations","tracks","fences","materials","devices","video","events","verifications")) capabilities.put(k,new Capability());
        }
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Action {
        public boolean allowed; public String reasonCode;
        public Action() {}
        public Action(boolean allowed,String reason) { this.allowed=allowed;this.reasonCode=reason; }
    }
    public static Map<String,Action> actions() {
        Map<String,Action> result=new LinkedHashMap<>();
        for(String key:Arrays.asList("viewHistory","viewVideo","talk","viewWork","viewEvent")) result.put(key,new Action(false,"MODULE_NOT_ENABLED"));
        result.put("viewHistory",new Action(false,"HISTORY_NOT_INTEGRATED")); return result;
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Duty { public String shiftId, state="UNKNOWN"; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Person {
        public String personId,personCode,name,avatarUrl,phoneMasked,siteId,accountId,dataUpdatedAt;
        public Map<String,String> legacy; public Team team; public Area area;
        public Section<Duty> duty=Section.missing("ROSTER_NOT_INTEGRATED");
        public Section<List<Work>> works=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<Equipment> equipment=Section.missing("SOURCE_NOT_INTEGRATED");
        public Map<String,Action> actions=PortalModels.actions();
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Work {
        public String workId,sourceWorkNo,name,personRole,startsAt,endsAt,source,monitorStatus="UNKNOWN";
        public Area area; public Map<String,String> supervisor,responsible;
        public List<Map<String,String>> members;
    }
    public static class Equipment { public Slot helmet,belt,watch; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Slot {
        public DeviceType type; public Assignment assignmentState=Assignment.UNKNOWN;
        public List<Device> devices=new ArrayList<>(); public String reasonCode="ASSIGNMENT_SOURCE_NOT_INTEGRATED";
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Reading {
        public Double value; public String sourceTime,receivedAt,reasonCode;
        public Freshness freshness=Freshness.UNKNOWN;
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Communication {
        public CommunicationState state=CommunicationState.UNKNOWN;
        public String sourceKind="NONE",sourceTime,receivedAt,observedAt,reasonCode;
        public Freshness freshness=Freshness.UNKNOWN;
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Device {
        public String deviceId,deviceCode,model,legacyHatId; public DeviceType type;
        public Communication communication=new Communication(); public Reading battery=new Reading();
        public Map<String,Capability> capabilities=new LinkedHashMap<>();
        public Map<String,Object> manufacturerExtensions=new LinkedHashMap<>();
        public Device() { for(String k:Arrays.asList("video","talk","location","capture","record")) capabilities.put(k,new Capability()); }
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Event { public String eventId,type,level,title,occurredAt,status,source; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Location {
        public Double longitude,latitude; public String coordinateSystem,sourceTime,receivedAt,quality,sourceDeviceId,attribution;
        public Freshness freshness=Freshness.UNKNOWN;
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Media { public String mediaId,type,createdAt,sourceDeviceId,attribution,previewUrl; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class HistorySummary { public Long total; public String lastOccurredAt; }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Detail {
        public Person person; public Section<Equipment> equipment; public Section<List<Work>> works;
        public Section<Duty> duty;
        public Section<List<Event>> events=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<Location> location=Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");
        public Section<List<Media>> media=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<HistorySummary> historySummary=Section.missing("HISTORY_NOT_INTEGRATED");
        public Map<String,Action> actions;
    }
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class History {
        public String recordId,relationId,personId,deviceId,deviceCode;
        public DeviceType deviceType; public String action,occurredAt,startedAt,endedAt,state,evidenceQuality;
        public Map<String,String> operator,legacy;
    }
}
