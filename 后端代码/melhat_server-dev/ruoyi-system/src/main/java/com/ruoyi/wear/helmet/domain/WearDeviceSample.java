package com.ruoyi.wear.helmet.domain;

import java.math.BigDecimal;
import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_device_sample")
public class WearDeviceSample
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long deviceId;
    private Date occurredAt;
    private Date receivedAt;
    private BigDecimal lat;
    private BigDecimal lng;
    private String altitude;
    private String speed;
    private BigDecimal battery;
    private String online;
    private String locationQuality;
    private Date createTime;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
    public Date getOccurredAt() { return occurredAt; }
    public void setOccurredAt(Date occurredAt) { this.occurredAt = occurredAt; }
    public Date getReceivedAt() { return receivedAt; }
    public void setReceivedAt(Date receivedAt) { this.receivedAt = receivedAt; }
    public BigDecimal getLat() { return lat; }
    public void setLat(BigDecimal lat) { this.lat = lat; }
    public BigDecimal getLng() { return lng; }
    public void setLng(BigDecimal lng) { this.lng = lng; }
    public String getAltitude() { return altitude; }
    public void setAltitude(String altitude) { this.altitude = altitude; }
    public String getSpeed() { return speed; }
    public void setSpeed(String speed) { this.speed = speed; }
    public BigDecimal getBattery() { return battery; }
    public void setBattery(BigDecimal battery) { this.battery = battery; }
    public String getOnline() { return online; }
    public void setOnline(String online) { this.online = online; }
    public String getLocationQuality() { return locationQuality; }
    public void setLocationQuality(String locationQuality) { this.locationQuality = locationQuality; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
}
