package com.ruoyi.wear.event;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Profile("!prod")
@ConditionalOnProperty(name = "melhat.demo-mode", havingValue = "true")
@Component
public class EventEscalateScheduler
{
    @Autowired
    private EventCommandService commandService;

    @Scheduled(fixedDelay = 60000)
    public void escalateDueSos()
    {
        commandService.escalateDue();
    }
}
