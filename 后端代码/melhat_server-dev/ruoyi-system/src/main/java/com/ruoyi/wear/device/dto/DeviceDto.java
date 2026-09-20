package com.ruoyi.wear.device.dto;

import java.math.BigDecimal;
import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.ruoyi.wear.assignment.dto.AssignmentDto;

public class DeviceDto
{
    private String id;
    private String manufacturerCode;
    private String sn;
    private String externalCode;
    private String modelId;
    private String modelCode;
    private String modelName;
    private String typeCode;
    private String siteId;
    private String siteName;
    private String assetStatus;
    private String online;
    private BigDecimal battery;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date lastReportedAt;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date lastTelemetryAt;
    private String connectionQuality;
    private String locationQuality;
    private CapabilityDto capabilities;
    private String legacyHatId;
    private String source;
    private boolean demo;
    private boolean simulation;
    private String simulationStatus;
    private String simulationStatusLabel;
    private AssignmentDto currentAssignment;
    private Integer version;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getManufacturerCode() { return manufacturerCode; }
    public void setManufacturerCode(String manufacturerCode) { this.manufacturerCode = manufacturerCode; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public String getExternalCode() { return externalCode; }
    public void setExternalCode(String externalCode) { this.externalCode = externalCode; }
    public String getModelId() { return modelId; }
    public void setModelId(String modelId) { this.modelId = modelId; }
    public String getModelCode() { return modelCode; }
    public void setModelCode(String modelCode) { this.modelCode = modelCode; }
    public String getModelName() { return modelName; }
    public void setModelName(String modelName) { this.modelName = modelName; }
    public String getTypeCode() { return typeCode; }
    public void setTypeCode(String typeCode) { this.typeCode = typeCode; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getSiteName() { return siteName; }
    public void setSiteName(String siteName) { this.siteName = siteName; }
    public String getAssetStatus() { return assetStatus; }
    public void setAssetStatus(String assetStatus) { this.assetStatus = assetStatus; }
    public String getOnline() { return online; }
    public void setOnline(String online) { this.online = online; }
    public BigDecimal getBattery() { return battery; }
    public void setBattery(BigDecimal battery) { this.battery = battery; }
    public Date getLastReportedAt() { return lastReportedAt; }
    public void setLastReportedAt(Date lastReportedAt) { this.lastReportedAt = lastReportedAt; }
    public Date getLastTelemetryAt() { return lastTelemetryAt; }
    public void setLastTelemetryAt(Date lastTelemetryAt) { this.lastTelemetryAt = lastTelemetryAt; }
    public String getConnectionQuality() { return connectionQuality; }
    public void setConnectionQuality(String connectionQuality) { this.connectionQuality = connectionQuality; }
    public String getLocationQuality() { return locationQuality; }
    public void setLocationQuality(String locationQuality) { this.locationQuality = locationQuality; }
    public CapabilityDto getCapabilities() { return capabilities; }
    public void setCapabilities(CapabilityDto capabilities) { this.capabilities = capabilities; }
    public String getLegacyHatId() { return legacyHatId; }
    public void setLegacyHatId(String legacyHatId) { this.legacyHatId = legacyHatId; }
    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }
    public boolean isDemo() { return demo; }
    public boolean isSimulation() { return simulation; }
    public void setSimulation(boolean simulation) { this.simulation = simulation; }
    public String getSimulationStatus() { return simulationStatus; }
    public void setSimulationStatus(String value) { this.simulationStatus = value; }
    public String getSimulationStatusLabel() { return simulationStatusLabel; }
    public void setSimulationStatusLabel(String value) { this.simulationStatusLabel = value; }
    public void setDemo(boolean demo) { this.demo = demo; }
    public AssignmentDto getCurrentAssignment() { return currentAssignment; }
    public void setCurrentAssignment(AssignmentDto currentAssignment) { this.currentAssignment = currentAssignment; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
