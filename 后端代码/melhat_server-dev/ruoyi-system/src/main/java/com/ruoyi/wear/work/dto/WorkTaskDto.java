package com.ruoyi.wear.work.dto;

import java.util.Collections;
import java.util.Date;
import java.util.List;
import com.fasterxml.jackson.annotation.JsonFormat;

public class WorkTaskDto
{
    private String id;
    private String siteId;
    private String title;
    private String workType;
    private String spaceId;
    private String spaceName;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date plannedStart;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date plannedEnd;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date actualStart;
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ssXXX", timezone = "GMT+8")
    private Date actualEnd;
    private String status;
    private String ownerUserId;
    private String guardianPersonId;
    private Boolean ticketRequired;
    private String ticketNo;
    private String ticketStatus;
    private Boolean demo;
    private Integer version;
    private List<WorkMemberDto> members = Collections.emptyList();
    private List<String> requirements = Collections.emptyList();
    private List<EquipmentCheckDto> equipmentCheck = Collections.emptyList();

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getWorkType() { return workType; }
    public void setWorkType(String workType) { this.workType = workType; }
    public String getSpaceId() { return spaceId; }
    public void setSpaceId(String spaceId) { this.spaceId = spaceId; }
    public String getSpaceName() { return spaceName; }
    public void setSpaceName(String spaceName) { this.spaceName = spaceName; }
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
    public String getOwnerUserId() { return ownerUserId; }
    public void setOwnerUserId(String ownerUserId) { this.ownerUserId = ownerUserId; }
    public String getGuardianPersonId() { return guardianPersonId; }
    public void setGuardianPersonId(String guardianPersonId) { this.guardianPersonId = guardianPersonId; }
    public Boolean getTicketRequired() { return ticketRequired; }
    public void setTicketRequired(Boolean ticketRequired) { this.ticketRequired = ticketRequired; }
    public String getTicketNo() { return ticketNo; }
    public void setTicketNo(String ticketNo) { this.ticketNo = ticketNo; }
    public String getTicketStatus() { return ticketStatus; }
    public void setTicketStatus(String ticketStatus) { this.ticketStatus = ticketStatus; }
    public Boolean getDemo() { return demo; }
    public void setDemo(Boolean demo) { this.demo = demo; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
    public List<WorkMemberDto> getMembers() { return members; }
    public void setMembers(List<WorkMemberDto> members) { this.members = members; }
    public List<String> getRequirements() { return requirements; }
    public void setRequirements(List<String> requirements) { this.requirements = requirements; }
    public List<EquipmentCheckDto> getEquipmentCheck() { return equipmentCheck; }
    public void setEquipmentCheck(List<EquipmentCheckDto> equipmentCheck) { this.equipmentCheck = equipmentCheck; }
}
