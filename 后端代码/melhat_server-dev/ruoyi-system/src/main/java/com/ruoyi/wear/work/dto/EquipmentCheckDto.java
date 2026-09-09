package com.ruoyi.wear.work.dto;

public class EquipmentCheckDto
{
    private String personId;
    private String personName;
    private String typeCode;
    private String result;
    private String sn;
    private Boolean needsConfirm;

    public String getPersonId() { return personId; }
    public void setPersonId(String personId) { this.personId = personId; }
    public String getPersonName() { return personName; }
    public void setPersonName(String personName) { this.personName = personName; }
    public String getTypeCode() { return typeCode; }
    public void setTypeCode(String typeCode) { this.typeCode = typeCode; }
    public String getResult() { return result; }
    public void setResult(String result) { this.result = result; }
    public String getSn() { return sn; }
    public void setSn(String sn) { this.sn = sn; }
    public Boolean getNeedsConfirm() { return needsConfirm; }
    public void setNeedsConfirm(Boolean needsConfirm) { this.needsConfirm = needsConfirm; }
}
