package com.ruoyi.wear.assignment.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.ruoyi.common.core.domain.BaseEntity;

@TableName("wear_assignment")
public class WearAssignment extends BaseEntity
{
    private static final long serialVersionUID = 1L;

    @TableId(type = IdType.AUTO)
    private Long id;
    private Long deviceId;
    private Long personId;
    private Long siteId;
    private Date issuedAt;
    private Date returnedAt;
    private String issuedBy;
    private String returnedBy;
    private String returnReason;
    private String returnKind;
    private Integer version;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
    public Long getPersonId() { return personId; }
    public void setPersonId(Long personId) { this.personId = personId; }
    public Long getSiteId() { return siteId; }
    public void setSiteId(Long siteId) { this.siteId = siteId; }
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
