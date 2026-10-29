package com.ruoyi.melhat.direct;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** Cloud credentials are server configuration, never part of the shared UI snapshot. */
@Component
@ConfigurationProperties(prefix = "melhat.helmet-media")
public class HelmetMediaProperties {
    private boolean enabled;
    private String controlUrl = "";
    private String sharedKey = "";
    private int commandTimeoutSeconds = 120;
    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean value) { enabled = value; }
    public String getControlUrl() { return controlUrl; }
    public void setControlUrl(String value) { controlUrl = value == null ? "" : value.replaceAll("/+$", ""); }
    public String getSharedKey() { return sharedKey; }
    public void setSharedKey(String value) { sharedKey = value == null ? "" : value; }
    public int getCommandTimeoutSeconds() { return Math.max(30, commandTimeoutSeconds); }
    public void setCommandTimeoutSeconds(int value) { commandTimeoutSeconds = value; }
}
