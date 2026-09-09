package com.ruoyi.wear.person.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.ruoyi.common.core.domain.BaseEntity;

@TableName("wear_person")
public class WearPerson extends BaseEntity
{
    private static final long serialVersionUID = 1L;

    @TableId(type = IdType.AUTO)
    private Long id;
    private String personCode;
    private String name;
    private Long orgDeptId;
    private Long teamId;
    private Long contractorId;
    private Long accountUserId;
    private String status;
    @JsonFormat(pattern = "yyyy-MM-dd")
    private Date validFrom;
    @JsonFormat(pattern = "yyyy-MM-dd")
    private Date validTo;
    private Integer version;
    @TableLogic(value = "0", delval = "2")
    private String delFlag;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getPersonCode() { return personCode; }
    public void setPersonCode(String personCode) { this.personCode = personCode; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public Long getOrgDeptId() { return orgDeptId; }
    public void setOrgDeptId(Long orgDeptId) { this.orgDeptId = orgDeptId; }
    public Long getTeamId() { return teamId; }
    public void setTeamId(Long teamId) { this.teamId = teamId; }
    public Long getContractorId() { return contractorId; }
    public void setContractorId(Long contractorId) { this.contractorId = contractorId; }
    public Long getAccountUserId() { return accountUserId; }
    public void setAccountUserId(Long accountUserId) { this.accountUserId = accountUserId; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Date getValidFrom() { return validFrom; }
    public void setValidFrom(Date validFrom) { this.validFrom = validFrom; }
    public Date getValidTo() { return validTo; }
    public void setValidTo(Date validTo) { this.validTo = validTo; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
    public String getDelFlag() { return delFlag; }
    public void setDelFlag(String delFlag) { this.delFlag = delFlag; }
}
