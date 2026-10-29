package com.ruoyi.melhat.belt;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "melhat.belt")
public class DirectBeltProperties {
    private boolean enabled;
    private int heartbeatTimeoutSeconds = 45;
    private String publicBaseUrl = "", apiUrl = "", wsUrl = "";
    // The supplied DTO and management clients disagree about wear values; no default is safe.
    private String wornValue = "", unwornValue = "", hookedValue = "", unhookedValue = "";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean value) { enabled = value; }
    public int getHeartbeatTimeoutSeconds() { return Math.max(10, heartbeatTimeoutSeconds); }
    public void setHeartbeatTimeoutSeconds(int value) { heartbeatTimeoutSeconds = value; }
    public String getPublicBaseUrl() { return publicBaseUrl; }
    public void setPublicBaseUrl(String value) { publicBaseUrl = clean(value); }
    public String getApiUrl() { return apiUrl; }
    public void setApiUrl(String value) { apiUrl = clean(value); }
    public String getWsUrl() { return wsUrl; }
    public void setWsUrl(String value) { wsUrl = clean(value); }
    public String getWornValue() { return wornValue; }
    public void setWornValue(String value) { wornValue = clean(value); }
    public String getUnwornValue() { return unwornValue; }
    public void setUnwornValue(String value) { unwornValue = clean(value); }
    public String getHookedValue() { return hookedValue; }
    public void setHookedValue(String value) { hookedValue = clean(value); }
    public String getUnhookedValue() { return unhookedValue; }
    public void setUnhookedValue(String value) { unhookedValue = clean(value); }
    public boolean wearMappingConfirmed() { return distinct(wornValue, unwornValue); }
    public boolean hookMappingConfirmed() {
        return distinct(hookedValue, unhookedValue) && !"-1".equals(hookedValue) && !"-1".equals(unhookedValue);
    }
    public Boolean worn(String value) { return mapped(value, wornValue, unwornValue); }
    public Boolean hooked(String value) { return hookMappingConfirmed() ? mapped(value, hookedValue, unhookedValue) : null; }
    private static Boolean mapped(String raw, String yes, String no) {
        return !distinct(yes, no) || raw == null ? null : yes.equals(raw) ? Boolean.TRUE : no.equals(raw) ? Boolean.FALSE : null;
    }
    private static boolean distinct(String yes, String no) { return !yes.isEmpty() && !no.isEmpty() && !yes.equals(no); }
    private static String clean(String value) { return value == null ? "" : value.trim(); }
}
