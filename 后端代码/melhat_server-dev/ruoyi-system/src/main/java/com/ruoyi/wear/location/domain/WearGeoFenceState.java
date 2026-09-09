package com.ruoyi.wear.location.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_geo_fence_state")
public class WearGeoFenceState
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long fenceId;
    private Long personId;
    private Integer inside;
    private Integer candidateInside;
    private Date since;
    private Date lastEvalAt;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getFenceId() { return fenceId; }
    public void setFenceId(Long fenceId) { this.fenceId = fenceId; }
    public Long getPersonId() { return personId; }
    public void setPersonId(Long personId) { this.personId = personId; }
    public Integer getInside() { return inside; }
    public void setInside(Integer inside) { this.inside = inside; }
    public Integer getCandidateInside() { return candidateInside; }
    public void setCandidateInside(Integer candidateInside) { this.candidateInside = candidateInside; }
    public Date getSince() { return since; }
    public void setSince(Date since) { this.since = since; }
    public Date getLastEvalAt() { return lastEvalAt; }
    public void setLastEvalAt(Date lastEvalAt) { this.lastEvalAt = lastEvalAt; }
}
