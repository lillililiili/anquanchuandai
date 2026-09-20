package com.ruoyi.portal;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
@Configuration
public class PortalEventConfiguration {
    @Bean @ConditionalOnMissingBean(PortalEventSource.class)
    public PortalEventSource portalEventSource(){return new PortalEventSource(){};}
}
