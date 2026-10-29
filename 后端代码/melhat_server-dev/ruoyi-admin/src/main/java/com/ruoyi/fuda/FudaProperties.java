package com.ruoyi.fuda;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import java.util.*;

/** Private application credentials are deliberately separate from human login sessions. */
@Component
@ConfigurationProperties(prefix="fuda.api")
public class FudaProperties {
    private boolean enabled;
    private String sourcePlatform="wearable-platform";
    private Map<String,Application> applications=new LinkedHashMap<>();
    private Map<String,LocationProfile> locationProfiles=new LinkedHashMap<>();
    public boolean isEnabled(){return enabled;}
    public void setEnabled(boolean value){enabled=value;}
    public String getSourcePlatform(){return sourcePlatform;}
    public void setSourcePlatform(String value){sourcePlatform=value;}
    public Map<String,Application> getApplications(){return applications;}
    public void setApplications(Map<String,Application> value){applications=value==null?new LinkedHashMap<>():value;}
    public Map<String,LocationProfile> getLocationProfiles(){return locationProfiles;}
    public void setLocationProfiles(Map<String,LocationProfile> value){locationProfiles=value==null?new LinkedHashMap<>():value;}
    /** Commissioned per ledger device, for current position only. Never retroactively reinterprets historical alarms. */
    public static class LocationProfile {
        private boolean verified;
        private String coordinateSystem="UNKNOWN",positionMethod="UNKNOWN",evidence="",firmware="";
        public boolean isVerified(){return verified;}public void setVerified(boolean value){verified=value;}
        public String getCoordinateSystem(){return coordinateSystem;}public void setCoordinateSystem(String value){coordinateSystem=value;}
        public String getPositionMethod(){return positionMethod;}public void setPositionMethod(String value){positionMethod=value;}
        public String getEvidence(){return evidence;}public void setEvidence(String value){evidence=value;}
        public String getFirmware(){return firmware;}public void setFirmware(String value){firmware=value;}
    }
    public static class Application {
        private boolean enabled;
        private String secretBase64="";
        private Set<String> allowedLedgerDeviceIds=new LinkedHashSet<>();
        public boolean isEnabled(){return enabled;}
        public void setEnabled(boolean value){enabled=value;}
        public String getSecretBase64(){return secretBase64;}
        public void setSecretBase64(String value){secretBase64=value;}
        public Set<String> getAllowedLedgerDeviceIds(){return allowedLedgerDeviceIds;}
        public void setAllowedLedgerDeviceIds(Set<String> value){allowedLedgerDeviceIds=value==null?new LinkedHashSet<>():value;}
    }
}
