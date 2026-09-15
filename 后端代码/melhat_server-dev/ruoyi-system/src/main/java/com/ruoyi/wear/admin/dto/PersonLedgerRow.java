package com.ruoyi.wear.admin.dto;

import java.util.Date;
import com.ruoyi.common.annotation.Excel;

public class PersonLedgerRow
{
    @Excel(name = "人员编码") private String personCode;
    @Excel(name = "姓名") private String name;
    @Excel(name = "班组ID") private String teamId;
    @Excel(name = "承包商ID") private String contractorId;
    @Excel(name = "关联厂站ID", prompt = "多个厂站以英文逗号分隔") private String siteIds;
    @Excel(name = "有效期开始", dateFormat = "yyyy-MM-dd") private Date validFrom;
    @Excel(name = "有效期结束", dateFormat = "yyyy-MM-dd") private Date validTo;
    @Excel(name = "状态", readConverterExp = "0=启用,1=停用") private String status;

    public String getPersonCode() { return personCode; }
    public void setPersonCode(String personCode) { this.personCode = personCode; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getTeamId() { return teamId; }
    public void setTeamId(String teamId) { this.teamId = teamId; }
    public String getContractorId() { return contractorId; }
    public void setContractorId(String contractorId) { this.contractorId = contractorId; }
    public String getSiteIds() { return siteIds; }
    public void setSiteIds(String siteIds) { this.siteIds = siteIds; }
    public Date getValidFrom() { return validFrom; }
    public void setValidFrom(Date validFrom) { this.validFrom = validFrom; }
    public Date getValidTo() { return validTo; }
    public void setValidTo(Date validTo) { this.validTo = validTo; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
}
