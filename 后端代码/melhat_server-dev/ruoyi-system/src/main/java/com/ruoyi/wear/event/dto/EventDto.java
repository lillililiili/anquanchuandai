package com.ruoyi.wear.event.dto;

import java.math.BigDecimal;
import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;

public class EventDto
{
    private Boolean reminderOnly;
    public Boolean getReminderOnly() { return reminderOnly; }
    public void setReminderOnly(Boolean value) { reminderOnly = value; }
    private String id;
    private String type;
    private String severity;
    private String status;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date occurredAt;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date receivedAt;
    private String personId;
    private String reporterUserId;
    public String getReporterUserId() { return reporterUserId; }
    public void setReporterUserId(String reporterUserId) { this.reporterUserId = reporterUserId; }
    private String personCode;
    private String personName;
    private String deviceId;
    private String sn;
    private String siteId;
    private BigDecimal locationLat;
    private BigDecimal locationLng;
    private String locationQuality;
    private String claimantUserId;
    private Integer repeatCount;
    private Boolean escalated;
    private Boolean demo;
    private String source;
    private String deviceType;
    public String getDeviceType() { return deviceType; }
    public void setDeviceType(String deviceType) { this.deviceType = deviceType; }
    private String alarmCode;
    private String alarmName;
    private String alarmDescription;
    private String sourceEventId;
    private String ruleVersion;
    private String taskId;
    private String taskMatch;
    private String fenceId;
    private String fenceAction;
    private Integer version;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getSeverity() { return severity; }
    public void setSeverity(String severity) { this.severity = severity; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Date getOccurredAt() { return occurredAt; }
    public void setOccurredAt(Date occurredAt) { this.occurredAt = occurredAt; }
    public Date getReceivedAt() { return receivedAt; }
    public void setReceivedAt(Date receivedAt) { this.receivedAt = receivedAt; }
    public String getPersonId() { return personId; }
    public void setPersonId(String personId) { this.personId = personId; }
    public String getPersonCode() { return personCode; }
    public void setPersonCode(String personCode) { this.personCode = personCode; }
    public String getPersonName() { return personName; }
    public void setPersonName(String personName) { this.personName = personName; }
    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public BigDecimal getLocationLat() { return locationLat; }
    public void setLocationLat(BigDecimal locationLat) { this.locationLat = locationLat; }
    public BigDecimal getLocationLng() { return locationLng; }
    public void setLocationLng(BigDecimal locationLng) { this.locationLng = locationLng; }
    public String getLocationQuality() { return locationQuality; }
    public void setLocationQuality(String locationQuality) { this.locationQuality = locationQuality; }
    public String getClaimantUserId() { return claimantUserId; }
    public void setClaimantUserId(String claimantUserId) { this.claimantUserId = claimantUserId; }
    public Integer getRepeatCount() { return repeatCount; }
    public void setRepeatCount(Integer repeatCount) { this.repeatCount = repeatCount; }
    public Boolean getEscalated() { return escalated; }
    public void setEscalated(Boolean escalated) { this.escalated = escalated; }
    public Boolean getDemo() { return demo; }
    public void setDemo(Boolean demo) { this.demo = demo; }
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
    public String getRuleVersion() { return ruleVersion; }
    public void setRuleVersion(String ruleVersion) { this.ruleVersion = ruleVersion; }
    public String getTaskId() { return taskId; }
    public void setTaskId(String taskId) { this.taskId = taskId; }
    public String getTaskMatch() { return taskMatch; }
    public void setTaskMatch(String taskMatch) { this.taskMatch = taskMatch; }
    public String getFenceId() { return fenceId; }
    public void setFenceId(String fenceId) { this.fenceId = fenceId; }
    public String getFenceAction() { return fenceAction; }
    public void setFenceAction(String fenceAction) { this.fenceAction = fenceAction; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
