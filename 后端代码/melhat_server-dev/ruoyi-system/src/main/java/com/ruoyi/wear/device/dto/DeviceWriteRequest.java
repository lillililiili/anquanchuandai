package com.ruoyi.wear.device.dto;

public class DeviceWriteRequest
{
    private String manufacturerCode;
    private String sn;
    private String externalCode;
    private String modelId;
    private String siteId;
    private String assetStatus;
    private Integer version;

    public String getManufacturerCode() { return manufacturerCode; }
    public void setManufacturerCode(String manufacturerCode) { this.manufacturerCode = manufacturerCode; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public String getExternalCode() { return externalCode; }
    public void setExternalCode(String externalCode) { this.externalCode = externalCode; }
    public String getModelId() { return modelId; }
    public void setModelId(String modelId) { this.modelId = modelId; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getAssetStatus() { return assetStatus; }
    public void setAssetStatus(String assetStatus) { this.assetStatus = assetStatus; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
