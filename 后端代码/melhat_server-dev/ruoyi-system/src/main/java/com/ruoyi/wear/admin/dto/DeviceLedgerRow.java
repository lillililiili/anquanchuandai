package com.ruoyi.wear.admin.dto;

import com.ruoyi.common.annotation.Excel;

public class DeviceLedgerRow
{
    @Excel(name = "厂商编码") private String manufacturerCode;
    @Excel(name = "设备序列号") private String sn;
    @Excel(name = "型号编码") private String modelCode;
    @Excel(name = "资产编号") private String externalCode;
    @Excel(name = "厂站ID") private String siteId;
    @Excel(name = "资产状态") private String assetStatus;

    public String getManufacturerCode() { return manufacturerCode; }
    public void setManufacturerCode(String manufacturerCode) { this.manufacturerCode = manufacturerCode; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public String getModelCode() { return modelCode; }
    public void setModelCode(String modelCode) { this.modelCode = modelCode; }
    public String getExternalCode() { return externalCode; }
    public void setExternalCode(String externalCode) { this.externalCode = externalCode; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getAssetStatus() { return assetStatus; }
    public void setAssetStatus(String assetStatus) { this.assetStatus = assetStatus; }
}
