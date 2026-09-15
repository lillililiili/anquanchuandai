package com.ruoyi.wear.admin.dto;

import com.ruoyi.common.annotation.Excel;

public class ProductModelLedgerRow
{
    @Excel(name = "产品类型", prompt = "helmet 或 belt") private String typeCode;
    @Excel(name = "型号编码") private String modelCode;
    @Excel(name = "厂商编码") private String manufacturerCode;
    @Excel(name = "型号名称") private String name;
    @Excel(name = "协议版本") private String protocolVersion;
    @Excel(name = "属性能力", prompt = "多个值以英文逗号分隔") private String attributes;
    @Excel(name = "事件能力", prompt = "多个值以英文逗号分隔") private String events;
    @Excel(name = "动作能力", prompt = "多个值以英文逗号分隔") private String actions;
    @Excel(name = "状态", readConverterExp = "0=启用,1=停用") private String status;

    public String getTypeCode() { return typeCode; }
    public void setTypeCode(String typeCode) { this.typeCode = typeCode; }
    public String getModelCode() { return modelCode; }
    public void setModelCode(String modelCode) { this.modelCode = modelCode; }
    public String getManufacturerCode() { return manufacturerCode; }
    public void setManufacturerCode(String manufacturerCode) { this.manufacturerCode = manufacturerCode; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getProtocolVersion() { return protocolVersion; }
    public void setProtocolVersion(String protocolVersion) { this.protocolVersion = protocolVersion; }
    public String getAttributes() { return attributes; }
    public void setAttributes(String attributes) { this.attributes = attributes; }
    public String getEvents() { return events; }
    public void setEvents(String events) { this.events = events; }
    public String getActions() { return actions; }
    public void setActions(String actions) { this.actions = actions; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
}
