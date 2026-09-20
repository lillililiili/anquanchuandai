package com.ruoyi.portal;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
@Configuration
public class PortalS2Configuration {
    @Bean @ConditionalOnMissingBean(PortalSpatialSource.class)
    public PortalSpatialSource portalSpatialSource() { return new PortalSpatialSource() {}; }
    @Bean @ConditionalOnMissingBean(PortalMaterialSource.class)
    public PortalMaterialSource portalMaterialSource() { return new PortalMaterialSource() {}; }
}
