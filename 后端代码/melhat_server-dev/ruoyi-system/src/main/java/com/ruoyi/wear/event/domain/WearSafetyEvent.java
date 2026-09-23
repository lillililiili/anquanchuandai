package com.ruoyi.wear.event.domain;

import java.math.BigDecimal;
import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_safety_event")
public class WearSafetyEvent
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private String source;
    private String deviceType;
    public String getDeviceType() { return deviceType; }
    public void setDeviceType(String deviceType) { this.deviceType = deviceType; }
    private String alarmCode;
    private String alarmName;
    private String alarmDescription;
    private String sourceEventId;
    private String eventType;
    private String severity;
    private String status;
    private Date occurredAt;
    private Date receivedAt;
    private Long personId;
    private Long reporterUserId;
    public Long getReporterUserId() { return reporterUserId; }
    public void setReporterUserId(Long reporterUserId) { this.reporterUserId = reporterUserId; }
    private String personCode;
    private String personName;
    private Long deviceId;
    private String sn;
    private Long siteId;
    private BigDecimal locationLat;
    private BigDecimal locationLng;
    private String locationQuality;
    private Long claimantUserId;
    private Integer repeatCount;
    private Integer escalated;
    private String ruleVersion;
    private Integer demo;
    private Long taskId;
    private String taskMatch;
    private Long fenceId;
    private String fenceAction;
    private Integer version;
    private String createBy;
    private Date createTime;
    private String updateBy;
    private Date updateTime;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
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
    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }
    public String getSeverity() { return severity; }
    public void setSeverity(String severity) { this.severity = severity; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Date getOccurredAt() { return occurredAt; }
    public void setOccurredAt(Date occurredAt) { this.occurredAt = occurredAt; }
    public Date getReceivedAt() { return receivedAt; }
    public void setReceivedAt(Date receivedAt) { this.receivedAt = receivedAt; }
    public Long getPersonId() { return personId; }
    public void setPersonId(Long personId) { this.personId = personId; }
    public String getPersonCode() { return personCode; }
    public void setPersonCode(String personCode) { this.personCode = personCode; }
    public String getPersonName() { return personName; }
    public void setPersonName(String personName) { this.personName = personName; }
    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public Long getSiteId() { return siteId; }
    public void setSiteId(Long siteId) { this.siteId = siteId; }
    public BigDecimal getLocationLat() { return locationLat; }
    public void setLocationLat(BigDecimal locationLat) { this.locationLat = locationLat; }
    public BigDecimal getLocationLng() { return locationLng; }
    public void setLocationLng(BigDecimal locationLng) { this.locationLng = locationLng; }
    public String getLocationQuality() { return locationQuality; }
    public void setLocationQuality(String locationQuality) { this.locationQuality = locationQuality; }
    public Long getClaimantUserId() { return claimantUserId; }
    public void setClaimantUserId(Long claimantUserId) { this.claimantUserId = claimantUserId; }
    public Integer getRepeatCount() { return repeatCount; }
    public void setRepeatCount(Integer repeatCount) { this.repeatCount = repeatCount; }
    public Integer getEscalated() { return escalated; }
    public void setEscalated(Integer escalated) { this.escalated = escalated; }
    public String getRuleVersion() { return ruleVersion; }
    public void setRuleVersion(String ruleVersion) { this.ruleVersion = ruleVersion; }
    public Integer getDemo() { return demo; }
    public void setDemo(Integer demo) { this.demo = demo; }
    public Long getTaskId() { return taskId; }
    public void setTaskId(Long taskId) { this.taskId = taskId; }
    public String getTaskMatch() { return taskMatch; }
    public void setTaskMatch(String taskMatch) { this.taskMatch = taskMatch; }
    public Long getFenceId() { return fenceId; }
    public void setFenceId(Long fenceId) { this.fenceId = fenceId; }
    public String getFenceAction() { return fenceAction; }
    public void setFenceAction(String fenceAction) { this.fenceAction = fenceAction; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
    public String getCreateBy() { return createBy; }
    public void setCreateBy(String createBy) { this.createBy = createBy; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
    public String getUpdateBy() { return updateBy; }
    public void setUpdateBy(String updateBy) { this.updateBy = updateBy; }
    public Date getUpdateTime() { return updateTime; }
    public void setUpdateTime(Date updateTime) { this.updateTime = updateTime; }
}
