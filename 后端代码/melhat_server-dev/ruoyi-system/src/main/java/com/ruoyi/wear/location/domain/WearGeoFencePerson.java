package com.ruoyi.wear.location.domain;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_geo_fence_person")
public class WearGeoFencePerson
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long fenceId;
    private Long personId;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getFenceId() { return fenceId; }
    public void setFenceId(Long fenceId) { this.fenceId = fenceId; }
    public Long getPersonId() { return personId; }
    public void setPersonId(Long personId) { this.personId = personId; }
}
