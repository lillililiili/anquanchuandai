package com.ruoyi.melhat.direct;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** Endpoints advertised to the helmet must be reachable from its own network. */
@Component
@ConfigurationProperties(prefix = "melhat.direct")
public class DirectHelmetProperties {
    private boolean enabled;
    private int heartbeatTimeoutSeconds = 45;
    private String publicBaseUrl = "";
    private String wsUrl = "";
    private String apiUrl = "";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }
    public int getHeartbeatTimeoutSeconds() { return Math.max(10, heartbeatTimeoutSeconds); }
    public void setHeartbeatTimeoutSeconds(int value) { this.heartbeatTimeoutSeconds = value; }
    public String getPublicBaseUrl() { return publicBaseUrl; }
    public void setPublicBaseUrl(String value) { this.publicBaseUrl = value == null ? "" : value.trim(); }
    public String getWsUrl() { return wsUrl; }
    public void setWsUrl(String value) { this.wsUrl = value == null ? "" : value.trim(); }
    public String getApiUrl() { return apiUrl; }
    public void setApiUrl(String value) { this.apiUrl = value == null ? "" : value.trim(); }
}
