package com.ruoyi.wear.event.dto;

import java.math.BigDecimal;
import java.util.Date;

public class IngestRequest
{
    private String source;
    private String alarmCode;
    private String alarmName;
    private String alarmDescription;
    private String simulationDetail;
    public String getSimulationDetail() { return simulationDetail; }
    public void setSimulationDetail(String value) { simulationDetail = value; }
    private String sourceEventId;
    private String type;
    private String siteId;
    private String deviceId;
    private String personId;
    private Date occurredAt;
    private BigDecimal lat;
    private BigDecimal lng;
    private String locationQuality;
    private boolean demo;
    private String actor;
    private Long fenceId;
    private String fenceAction;
    private String ruleVersion;

    public String getAlarmCode() { return alarmCode; }
    public void setAlarmCode(String alarmCode) { this.alarmCode = alarmCode; }
    public String getAlarmName() { return alarmName; }
    public void setAlarmName(String alarmName) { this.alarmName = alarmName; }
    public String getAlarmDescription() { return alarmDescription; }
    public void setAlarmDescription(String alarmDescription) { this.alarmDescription = alarmDescription; }
    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }
    public String getSourceEventId() { return sourceEventId; }
    public void setSourceEventId(String sourceEventId) { this.sourceEventId = sourceEventId; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }
    public String getPersonId() { return personId; }
    public void setPersonId(String personId) { this.personId = personId; }
    public Date getOccurredAt() { return occurredAt; }
    public void setOccurredAt(Date occurredAt) { this.occurredAt = occurredAt; }
    public BigDecimal getLat() { return lat; }
    public void setLat(BigDecimal lat) { this.lat = lat; }
    public BigDecimal getLng() { return lng; }
    public void setLng(BigDecimal lng) { this.lng = lng; }
    public String getLocationQuality() { return locationQuality; }
    public void setLocationQuality(String locationQuality) { this.locationQuality = locationQuality; }
    public boolean isDemo() { return demo; }
    public void setDemo(boolean demo) { this.demo = demo; }
    public String getActor() { return actor; }
    public void setActor(String actor) { this.actor = actor; }
    public Long getFenceId() { return fenceId; }
    public void setFenceId(Long fenceId) { this.fenceId = fenceId; }
    public String getFenceAction() { return fenceAction; }
    public void setFenceAction(String fenceAction) { this.fenceAction = fenceAction; }
    public String getRuleVersion() { return ruleVersion; }
    public void setRuleVersion(String ruleVersion) { this.ruleVersion = ruleVersion; }
}
