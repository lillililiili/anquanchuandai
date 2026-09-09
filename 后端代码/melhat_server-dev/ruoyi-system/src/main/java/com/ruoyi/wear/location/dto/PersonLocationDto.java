package com.ruoyi.wear.location.dto;

import java.math.BigDecimal;
import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;

public class PersonLocationDto
{
    private String personId;
    private String personCode;
    private String personName;
    private String deviceId;
    private String sn;
    private BigDecimal lat;
    private BigDecimal lng;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date occurredAt;
    private String locationQuality;
    private String connectionQuality;
    private String source;
    private String floor;
    private String floorSource;
    private Boolean demo;

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
    public BigDecimal getLat() { return lat; }
    public void setLat(BigDecimal lat) { this.lat = lat; }
    public BigDecimal getLng() { return lng; }
    public void setLng(BigDecimal lng) { this.lng = lng; }
    public Date getOccurredAt() { return occurredAt; }
    public void setOccurredAt(Date occurredAt) { this.occurredAt = occurredAt; }
    public String getLocationQuality() { return locationQuality; }
    public void setLocationQuality(String locationQuality) { this.locationQuality = locationQuality; }
    public String getConnectionQuality() { return connectionQuality; }
    public void setConnectionQuality(String connectionQuality) { this.connectionQuality = connectionQuality; }
    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }
    public String getFloor() { return floor; }
    public void setFloor(String floor) { this.floor = floor; }
    public String getFloorSource() { return floorSource; }
    public void setFloorSource(String floorSource) { this.floorSource = floorSource; }
    public Boolean getDemo() { return demo; }
    public void setDemo(Boolean demo) { this.demo = demo; }
}
