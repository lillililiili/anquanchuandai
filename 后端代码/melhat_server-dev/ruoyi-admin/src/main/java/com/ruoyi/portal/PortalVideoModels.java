package com.ruoyi.portal;

import java.util.*;
import com.ruoyi.portal.PortalModels.*;

/** Metadata only: deliberately no arbitrary maps, media addresses or credentials. */
public final class PortalVideoModels {
    private PortalVideoModels() {}
    public enum StreamState { UNKNOWN, NOT_STARTED, REPORTED_ACTIVE, INTERRUPTED }
    public static class VideoDevice {
        public String deviceId, siteId, name, deviceCode, areaId, workId, sourceTime;
        public DeviceType type;
        public Communication communication=new Communication();
        public Capability video=new Capability();
        public StreamState streamState=StreamState.UNKNOWN;
        public Freshness freshness=Freshness.UNKNOWN;
        public String unavailableReason="MEDIA_ACCESS_NOT_ENABLED";
    }
    public static class Option { public String id, name; }
    public static class Filters {
        public Section<List<Option>> areas=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Option>> works=Section.missing("SOURCE_NOT_INTEGRATED");
    }
    /** Source must supply authoritative unique IDs for the entire filtered authorized scope, never a page. */
    public static class StatisticsEvidence {
        public Set<String> deviceIds=new HashSet<>(), availableIds=new HashSet<>(), interruptedIds=new HashSet<>(), notStartedIds=new HashSet<>();
        public String sourceTime;
    }
    public static class Statistics { public Long devices, available, interrupted, notStarted; public String sourceTime; }
    public static class VideoPage extends Page<VideoDevice> {
        public Filters filters=new Filters();
        public Section<Statistics> statistics=Section.missing("STATISTICS_NOT_INTEGRATED");
    }
    /** Related entries are individually authorized. Evidence describes the association, not current binding inference. */
    public static class Related {
        public String id, siteId, name, type, sourceTime, receivedAt;
        public String attribution="UNKNOWN", evidenceId;
        public Freshness freshness=Freshness.UNKNOWN;
    }
    public static class Detail {
        public VideoDevice device;
        public Section<List<Related>> person=Section.missing("HISTORICAL_ATTRIBUTION_UNKNOWN");
        public Section<List<Related>> equipment=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Related>> works=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Related>> location=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Related>> events=Section.missing("SOURCE_NOT_INTEGRATED");
        public Section<List<Related>> materials=Section.missing("SOURCE_NOT_INTEGRATED");
    }
}
