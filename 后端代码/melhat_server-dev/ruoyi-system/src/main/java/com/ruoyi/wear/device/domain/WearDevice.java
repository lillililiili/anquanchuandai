package com.ruoyi.wear.device.domain;

import java.math.BigDecimal;
import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.ruoyi.common.core.domain.BaseEntity;

@TableName("wear_device")
public class WearDevice extends BaseEntity
{
    private static final long serialVersionUID = 1L;

    @TableId(type = IdType.AUTO)
    private Long id;
    private String manufacturerCode;
    private String sn;
    private Long modelId;
    private Long siteId;
    private String assetStatus;
    private Long currentAssignmentId;
    private String externalCode;
    private String online;
    private BigDecimal battery;
    private Date lastReportedAt;
    private Date lastTelemetryAt;
    private Integer version;
    @TableLogic(value = "0", delval = "2")
    private String delFlag;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getManufacturerCode() { return manufacturerCode; }
    public void setManufacturerCode(String manufacturerCode) { this.manufacturerCode = manufacturerCode; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public Long getModelId() { return modelId; }
    public void setModelId(Long modelId) { this.modelId = modelId; }
    public Long getSiteId() { return siteId; }
    public void setSiteId(Long siteId) { this.siteId = siteId; }
    public String getAssetStatus() { return assetStatus; }
    public void setAssetStatus(String assetStatus) { this.assetStatus = assetStatus; }
    public Long getCurrentAssignmentId() { return currentAssignmentId; }
    public void setCurrentAssignmentId(Long currentAssignmentId) { this.currentAssignmentId = currentAssignmentId; }
    public String getExternalCode() { return externalCode; }
    public void setExternalCode(String externalCode) { this.externalCode = externalCode; }
    public String getOnline() { return online; }
    public void setOnline(String online) { this.online = online; }
    public BigDecimal getBattery() { return battery; }
    public void setBattery(BigDecimal battery) { this.battery = battery; }
    public Date getLastReportedAt() { return lastReportedAt; }
    public void setLastReportedAt(Date lastReportedAt) { this.lastReportedAt = lastReportedAt; }
    public Date getLastTelemetryAt() { return lastTelemetryAt; }
    public void setLastTelemetryAt(Date lastTelemetryAt) { this.lastTelemetryAt = lastTelemetryAt; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
    public String getDelFlag() { return delFlag; }
    public void setDelFlag(String delFlag) { this.delFlag = delFlag; }
}
