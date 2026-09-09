package com.ruoyi.wear.assignment.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_device_site_transfer")
public class WearDeviceSiteTransfer
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long deviceId;
    private Long fromSiteId;
    private Long toSiteId;
    private String operator;
    private Date createTime;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
    public Long getFromSiteId() { return fromSiteId; }
    public void setFromSiteId(Long fromSiteId) { this.fromSiteId = fromSiteId; }
    public Long getToSiteId() { return toSiteId; }
    public void setToSiteId(Long toSiteId) { this.toSiteId = toSiteId; }
    public String getOperator() { return operator; }
    public void setOperator(String operator) { this.operator = operator; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
}
