package com.ruoyi.wear.call.dto;

import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;

public class CommandDto
{
    private String id;
    private String kind;
    private String deviceId;
    private String sn;
    private String eventId;
    private String payload;
    private String status;
    private String vendorMsg;
    private Boolean heard;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date createTime;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getKind() { return kind; }
    public void setKind(String kind) { this.kind = kind; }
    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public String getEventId() { return eventId; }
    public void setEventId(String eventId) { this.eventId = eventId; }
    public String getPayload() { return payload; }
    public void setPayload(String payload) { this.payload = payload; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getVendorMsg() { return vendorMsg; }
    public void setVendorMsg(String vendorMsg) { this.vendorMsg = vendorMsg; }
    public Boolean getHeard() { return heard; }
    public void setHeard(Boolean heard) { this.heard = heard; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
}
