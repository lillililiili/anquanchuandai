package com.ruoyi.wear.location.dto;

import java.util.Collections;
import java.util.List;
import java.util.Map;

public class GeoFenceDto
{
    private String id;
    private String siteId;
    private String name;
    private List<Map<String, Object>> polygon = Collections.emptyList();
    private Boolean enabled;
    private String applyMode;
    private List<String> personIds = Collections.emptyList();
    private String timeStart;
    private String timeEnd;
    private Boolean enterEnabled;
    private Boolean leaveEnabled;
    private Integer debounceSeconds;
    private Integer ruleVersion;
    private Boolean demo;
    private Integer version;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public List<Map<String, Object>> getPolygon() { return polygon; }
    public void setPolygon(List<Map<String, Object>> polygon) { this.polygon = polygon; }
    public Boolean getEnabled() { return enabled; }
    public void setEnabled(Boolean enabled) { this.enabled = enabled; }
    public String getApplyMode() { return applyMode; }
    public void setApplyMode(String applyMode) { this.applyMode = applyMode; }
    public List<String> getPersonIds() { return personIds; }
    public void setPersonIds(List<String> personIds) { this.personIds = personIds; }
    public String getTimeStart() { return timeStart; }
    public void setTimeStart(String timeStart) { this.timeStart = timeStart; }
    public String getTimeEnd() { return timeEnd; }
    public void setTimeEnd(String timeEnd) { this.timeEnd = timeEnd; }
    public Boolean getEnterEnabled() { return enterEnabled; }
    public void setEnterEnabled(Boolean enterEnabled) { this.enterEnabled = enterEnabled; }
    public Boolean getLeaveEnabled() { return leaveEnabled; }
    public void setLeaveEnabled(Boolean leaveEnabled) { this.leaveEnabled = leaveEnabled; }
    public Integer getDebounceSeconds() { return debounceSeconds; }
    public void setDebounceSeconds(Integer debounceSeconds) { this.debounceSeconds = debounceSeconds; }
    public Integer getRuleVersion() { return ruleVersion; }
    public void setRuleVersion(Integer ruleVersion) { this.ruleVersion = ruleVersion; }
    public Boolean getDemo() { return demo; }
    public void setDemo(Boolean demo) { this.demo = demo; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
