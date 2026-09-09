package com.ruoyi.wear.location.domain;

import java.util.Date;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;

@TableName("wear_geo_fence")
public class WearGeoFence
{
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long siteId;
    private String name;
    private String polygonJson;
    private Integer enabled;
    private String applyMode;
    private String timeStart;
    private String timeEnd;
    private Integer enterEnabled;
    private Integer leaveEnabled;
    private Integer debounceSeconds;
    private Integer ruleVersion;
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
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getPolygonJson() { return polygonJson; }
    public void setPolygonJson(String polygonJson) { this.polygonJson = polygonJson; }
    public Integer getEnabled() { return enabled; }
    public void setEnabled(Integer enabled) { this.enabled = enabled; }
    public String getApplyMode() { return applyMode; }
    public void setApplyMode(String applyMode) { this.applyMode = applyMode; }
    public String getTimeStart() { return timeStart; }
    public void setTimeStart(String timeStart) { this.timeStart = timeStart; }
    public String getTimeEnd() { return timeEnd; }
    public void setTimeEnd(String timeEnd) { this.timeEnd = timeEnd; }
    public Integer getEnterEnabled() { return enterEnabled; }
    public void setEnterEnabled(Integer enterEnabled) { this.enterEnabled = enterEnabled; }
    public Integer getLeaveEnabled() { return leaveEnabled; }
    public void setLeaveEnabled(Integer leaveEnabled) { this.leaveEnabled = leaveEnabled; }
    public Integer getDebounceSeconds() { return debounceSeconds; }
    public void setDebounceSeconds(Integer debounceSeconds) { this.debounceSeconds = debounceSeconds; }
    public Integer getRuleVersion() { return ruleVersion; }
    public void setRuleVersion(Integer ruleVersion) { this.ruleVersion = ruleVersion; }
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
