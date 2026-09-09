package com.ruoyi.wear.auth.dto;

import java.util.List;
import java.util.Set;

public class MeDto
{
    private String userId;
    private String userName;
    private String nickName;
    private String status;
    private boolean admin;
    private Set<String> roles;
    private Set<String> permissions;
    private List<SiteDto> authorizedSites;
    private String currentSiteId;

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }
    public String getNickName() { return nickName; }
    public void setNickName(String nickName) { this.nickName = nickName; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public boolean isAdmin() { return admin; }
    public void setAdmin(boolean admin) { this.admin = admin; }
    public Set<String> getRoles() { return roles; }
    public void setRoles(Set<String> roles) { this.roles = roles; }
    public Set<String> getPermissions() { return permissions; }
    public void setPermissions(Set<String> permissions) { this.permissions = permissions; }
    public List<SiteDto> getAuthorizedSites() { return authorizedSites; }
    public void setAuthorizedSites(List<SiteDto> authorizedSites) { this.authorizedSites = authorizedSites; }
    public String getCurrentSiteId() { return currentSiteId; }
    public void setCurrentSiteId(String currentSiteId) { this.currentSiteId = currentSiteId; }
}
