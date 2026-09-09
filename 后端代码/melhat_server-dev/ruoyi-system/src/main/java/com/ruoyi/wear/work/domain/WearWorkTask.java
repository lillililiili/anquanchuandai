package com.ruoyi.wear.work.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_work_task")
public class WearWorkTask
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long siteId;
    private String title;
    private String workType;
    private Long spaceId;
    private Date plannedStart;
    private Date plannedEnd;
    private Date actualStart;
    private Date actualEnd;
    private String status;
    private Long ownerUserId;
    private Long guardianPersonId;
    private Integer ticketRequired;
    private String ticketNo;
    private String ticketStatus;
    private Integer demo;
    private Integer version;
    private String createBy;
    private Date createTime;
    private String updateBy;
    private Date updateTime;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getSiteId() { return siteId; }
    public void setSiteId(Long siteId) { this.siteId = siteId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getWorkType() { return workType; }
    public void setWorkType(String workType) { this.workType = workType; }
    public Long getSpaceId() { return spaceId; }
    public void setSpaceId(Long spaceId) { this.spaceId = spaceId; }
    public Date getPlannedStart() { return plannedStart; }
    public void setPlannedStart(Date plannedStart) { this.plannedStart = plannedStart; }
    public Date getPlannedEnd() { return plannedEnd; }
    public void setPlannedEnd(Date plannedEnd) { this.plannedEnd = plannedEnd; }
    public Date getActualStart() { return actualStart; }
    public void setActualStart(Date actualStart) { this.actualStart = actualStart; }
    public Date getActualEnd() { return actualEnd; }
    public void setActualEnd(Date actualEnd) { this.actualEnd = actualEnd; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Long getOwnerUserId() { return ownerUserId; }
    public void setOwnerUserId(Long ownerUserId) { this.ownerUserId = ownerUserId; }
    public Long getGuardianPersonId() { return guardianPersonId; }
    public void setGuardianPersonId(Long guardianPersonId) { this.guardianPersonId = guardianPersonId; }
    public Integer getTicketRequired() { return ticketRequired; }
    public void setTicketRequired(Integer ticketRequired) { this.ticketRequired = ticketRequired; }
    public String getTicketNo() { return ticketNo; }
    public void setTicketNo(String ticketNo) { this.ticketNo = ticketNo; }
    public String getTicketStatus() { return ticketStatus; }
    public void setTicketStatus(String ticketStatus) { this.ticketStatus = ticketStatus; }
    public Integer getDemo() { return demo; }
    public void setDemo(Integer demo) { this.demo = demo; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
    public String getCreateBy() { return createBy; }
    public void setCreateBy(String createBy) { this.createBy = createBy; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
    public String getUpdateBy() { return updateBy; }
    public void setUpdateBy(String updateBy) { this.updateBy = updateBy; }
    public Date getUpdateTime() { return updateTime; }
    public void setUpdateTime(Date updateTime) { this.updateTime = updateTime; }
}
