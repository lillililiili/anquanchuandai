package com.ruoyi.wear.device.dto;

public class ProductModelDto
{
    private String id;
    private String typeCode;
    private String modelCode;
    private String manufacturerCode;
    private String name;
    private String protocolVersion;
    private CapabilityDto capabilities;
    private String status;
    private Integer version;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
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
    public CapabilityDto getCapabilities() { return capabilities; }
    public void setCapabilities(CapabilityDto capabilities) { this.capabilities = capabilities; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
