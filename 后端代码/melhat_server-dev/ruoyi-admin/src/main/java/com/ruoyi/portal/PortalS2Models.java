package com.ruoyi.portal;

import java.util.*;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.ruoyi.portal.PortalModels.*;

/** Read-only metadata. Intentionally contains no storage URL or device command. */
public final class PortalS2Models {
    private PortalS2Models() {}
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public static class Item {
        public String id, siteId, name;
    }
    public static class DeviceOption extends Item { public DeviceType type; public String deviceCode; }
    public static class Position {
        public Double longitude, latitude;
        public String coordinateSystem, source, sourceTime, receivedAt, quality="UNKNOWN";
        public Freshness freshness=Freshness.UNKNOWN;
    }
    public static class LocatedDevice extends Item {
        public String deviceId, deviceCode, personId, personName, attribution="UNKNOWN";
        public CommunicationState communication=CommunicationState.UNKNOWN;
        public Position position;
    }
    public static class Segment {
        public String segmentId, continuity="UNKNOWN";
        public List<Position> points=new ArrayList<>();
    }
    public static class Gap { public String from,to,reason; }
    public static class Track extends Item {
        public String deviceId, personId, attribution="UNKNOWN", from,to;
        public boolean complete;
        public String incompleteReason;
        public List<Segment> segments=new ArrayList<>();
        public List<Gap> gaps=new ArrayList<>();
    }
    public static class Fence extends Item {
        public String status="UNKNOWN", coordinateSystem, rule, version, sourceTime, effectiveAt;
        public List<List<Double>> ring=new ArrayList<>();
    }
    public static class Material extends Item {
        public String type,deviceId,deviceCode,source,capturedAt,receivedAt;
        public String personId,personName,workId,eventId,attribution="UNKNOWN";
        public String workAttribution="UNKNOWN",eventAttribution="UNKNOWN";
        public String accessReason="FILE_ACCESS_NOT_ENABLED";
    }
}
