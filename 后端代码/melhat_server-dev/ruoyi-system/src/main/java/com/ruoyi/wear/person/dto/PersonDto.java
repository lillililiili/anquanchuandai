package com.ruoyi.wear.person.dto;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.ruoyi.wear.assignment.dto.AssignmentDto;

public class PersonDto
{
    private String id;
    private String personCode;
    private String name;
    private String orgDeptId;
    private String teamId;
    private String teamName;
    private String contractorId;
    private String contractorName;
    private String accountUserId;
    private String status;
    @JsonFormat(pattern = "yyyy-MM-dd")
    private Date validFrom;
    @JsonFormat(pattern = "yyyy-MM-dd")
    private Date validTo;
    private boolean selectable;
    private List<String> siteIds = new ArrayList<String>();
    private List<AssignmentDto> equipment = new ArrayList<AssignmentDto>();
    private Integer version;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getPersonCode() { return personCode; }
    public void setPersonCode(String personCode) { this.personCode = personCode; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getOrgDeptId() { return orgDeptId; }
    public void setOrgDeptId(String orgDeptId) { this.orgDeptId = orgDeptId; }
    public String getTeamId() { return teamId; }
    public void setTeamId(String teamId) { this.teamId = teamId; }
    public String getTeamName() { return teamName; }
    public void setTeamName(String teamName) { this.teamName = teamName; }
    public String getContractorId() { return contractorId; }
    public void setContractorId(String contractorId) { this.contractorId = contractorId; }
    public String getContractorName() { return contractorName; }
    public void setContractorName(String contractorName) { this.contractorName = contractorName; }
    public String getAccountUserId() { return accountUserId; }
    public void setAccountUserId(String accountUserId) { this.accountUserId = accountUserId; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Date getValidFrom() { return validFrom; }
    public void setValidFrom(Date validFrom) { this.validFrom = validFrom; }
    public Date getValidTo() { return validTo; }
    public void setValidTo(Date validTo) { this.validTo = validTo; }
    public boolean isSelectable() { return selectable; }
    public void setSelectable(boolean selectable) { this.selectable = selectable; }
    public List<String> getSiteIds() { return siteIds; }
    public void setSiteIds(List<String> siteIds) { this.siteIds = siteIds; }
    public List<AssignmentDto> getEquipment() { return equipment; }
    public void setEquipment(List<AssignmentDto> equipment) { this.equipment = equipment == null ? new ArrayList<AssignmentDto>() : equipment; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
