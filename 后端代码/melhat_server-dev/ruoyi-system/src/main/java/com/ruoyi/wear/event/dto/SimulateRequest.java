package com.ruoyi.wear.event.dto;

import java.math.BigDecimal;

public class SimulateRequest
{
    private String sourceEventId;
    private String scenarioCode;
    private java.util.Map<String, BigDecimal> measurements;
    public String getScenarioCode() { return scenarioCode; }
    public void setScenarioCode(String value) { scenarioCode = value; }
    public java.util.Map<String, BigDecimal> getMeasurements() { return measurements; }
    public void setMeasurements(java.util.Map<String, BigDecimal> value) { measurements = value; }
    private String type;
    private String siteId;
    private String deviceId;
    private String personId;
    private String occurredAt;
    private BigDecimal lat;
    private BigDecimal lng;

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
    public String getOccurredAt() { return occurredAt; }
    public void setOccurredAt(String occurredAt) { this.occurredAt = occurredAt; }
    public BigDecimal getLat() { return lat; }
    public void setLat(BigDecimal lat) { this.lat = lat; }
    public BigDecimal getLng() { return lng; }
    public void setLng(BigDecimal lng) { this.lng = lng; }
}
