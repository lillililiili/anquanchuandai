package com.ruoyi.wear.auth.dto;

import com.ruoyi.wear.site.domain.WearSite;

public class SiteDto
{
    private String id;
    private String siteCode;
    private String name;
    private String status;
    private String timezone;
    private Integer version;

    public static SiteDto from(WearSite site)
    {
        if (site == null)
        {
            return null;
        }
        SiteDto dto = new SiteDto();
        dto.setId(site.getId() == null ? null : String.valueOf(site.getId()));
        dto.setSiteCode(site.getSiteCode());
        dto.setName(site.getName());
        dto.setStatus(site.getStatus());
        dto.setTimezone(site.getTimezone());
        dto.setVersion(site.getVersion());
        return dto;
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getSiteCode() { return siteCode; }
    public void setSiteCode(String siteCode) { this.siteCode = siteCode; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getTimezone() { return timezone; }
    public void setTimezone(String timezone) { this.timezone = timezone; }
    public Integer getVersion() { return version; }
    public void setVersion(Integer version) { this.version = version; }
}
