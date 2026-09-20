package com.ruoyi.portal;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
@Configuration
public class PortalVideoConfiguration {
    @Bean @ConditionalOnMissingBean(PortalVideoSource.class)
    public PortalVideoSource portalVideoSource(){return new PortalVideoSource(){};}
}
