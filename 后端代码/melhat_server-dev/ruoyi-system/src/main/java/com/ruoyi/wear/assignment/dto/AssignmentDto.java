package com.ruoyi.wear.assignment.dto;

import java.util.Date;
import com.fasterxml.jackson.annotation.JsonFormat;

public class AssignmentDto
{
    private String id;
    private String deviceId;
    private String sn;
    private String typeCode;
    private String personId;
    private String personCode;
    private String personName;
    private String siteId;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date issuedAt;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date returnedAt;
    private String issuedBy;
    private String returnedBy;
    private String returnReason;
    private String returnKind;
    private Integer version;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public String getTypeCode() { return typeCode; }
    public void setTypeCode(String typeCode) { this.typeCode = typeCode; }
    public String getPersonId() { return personId; }
    public void setPersonId(String personId) { this.personId = personId; }
    public String getPersonCode() { return personCode; }
    public void setPersonCode(String personCode) { this.personCode = personCode; }
    public String getPersonName() { return personName; }
    public void setPersonName(String personName) { this.personName = personName; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public Date getIssuedAt() { return issuedAt; }
    public void setIssuedAt(Date issuedAt) { this.issuedAt = issuedAt; }
    public Date getReturnedAt() { return returnedAt; }
    public void setReturnedAt(Date returnedAt) { this.returnedAt = returnedAt; }
    public String getIssuedBy() { return issuedBy; }
    public void setIssuedBy(String issuedBy) { this.issuedBy = issuedBy; }
    public String getReturnedBy() { return returnedBy; }
    public void setReturnedBy(String returnedBy) { this.returnedBy = returnedBy; }
    public String getReturnReason() { return returnReason; }
    public void setReturnReason(String returnReason) { this.returnReason = returnReason; }
    public String getReturnKind() { return returnKind; }
    public void setReturnKind(String returnKind) { this.returnKind = returnKind; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
