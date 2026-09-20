package com.ruoyi.portal;

import java.util.*;
import com.ruoyi.portal.PortalModels.*;

/** Read-only event contract. Fixed metadata fields only; never media addresses or credentials. */
public final class PortalEventModels {
    private PortalEventModels() {}
    public enum Phase { UNCLAIMED, PROCESSING, AWAITING_VERIFICATION, LOCAL_COMPLETED, UNKNOWN }
    public enum VerificationState { DRAFT, SUBMITTED, UNKNOWN }
    public enum DeliveryState { NOT_CONFIGURED, PENDING, SENDING, SUCCESS, FAILED, UNKNOWN }
    public static class Ref {
        public String id,siteId,name,evidenceId,sourceTime;
        public String attribution="UNKNOWN",snapshotKind="UNKNOWN",deviceType,communication="UNKNOWN";
    }
    public static class Fact {
        public String eventId,eventCode,siteId,title,sourceSystem,sourceEventId,eventType="UNKNOWN",rawType,rawLevel;
        public String occurredAt,receivedAt,sourceUpdatedAt,deviceId,deviceCode;
        public Integer legacyHandled;
        public Phase phase=Phase.UNKNOWN;
        public Freshness freshness=Freshness.UNKNOWN;
        public Section<List<Ref>> person=Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");
    }
    public static class Option { public String value,label; }
    public static class Filters {
        public boolean keyword,timeRange,phase;
        public Section<List<Option>> eventTypes=Section.missing("SOURCE_NOT_INTEGRATED");
    }
    public static class EventPage extends Page<Fact> { public Filters filters=new Filters(); }
    /** Independently supplied complete source evidence, not a count of the current page. */
    public static class StatisticsEvidence { public Map<String,Phase> events=new LinkedHashMap<>(); public String sourceTime; }
    public static class Statistics { public long total; public Map<Phase,Long> counts=new LinkedHashMap<>(); public String sourceTime; }
    public static class Position extends PortalS2Models.Position { public String id,siteId,evidenceId,attribution="UNKNOWN"; }
    public static class Evidence {
        public String id,siteId,name,type,version,digest,capturedAt,receivedAt,evidenceId;
        public String attribution="UNKNOWN";
    }
    public static class Delivery { public DeliveryState state=DeliveryState.UNKNOWN; public String sourceTime,receiptId,reason; }
    public static class OriginalState { public String sourceSystem,sourceEventId,status,sourceTime; }
    public static class Detail {
        public Fact event;
        public Section<List<Ref>> owner=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Ref>> equipment=Section.missing("HISTORY_NOT_INTEGRATED");
        public Section<List<Ref>> works=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<Position> location=Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");
        public Section<List<Ref>> video=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Evidence>> materials=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<Delivery> summaryDelivery=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<Delivery> verificationDelivery=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<OriginalState> originalSystem=Section.missing("SOURCE_NOT_INTEGRATED");
    }
    public static class Record { public String id,siteId,eventId,sourceTime; }
    public static class Timeline extends Record {
        public String kind,title; public long sequence;
    }
    public static class Verification extends Record {
        public VerificationState state=VerificationState.UNKNOWN;
        public String conclusion,scene,measures,submittedAt,version;
        public Section<List<Evidence>> evidence=Section.missing("SOURCE_NOT_INTEGRATED");
    }
}
