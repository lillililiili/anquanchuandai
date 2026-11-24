package com.ruoyi.melhat.split;

import com.ruoyi.guardian.*;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

/** Registers the actual components and lets Spring choose constructors, unlike direct new() tests. */
class SplitHelmetBeanTest {
    @Test void everySplitComponentStartsWithIntegrationDisabledAndWithoutVendorCredentials(){
        try(AnnotationConfigApplicationContext context=new AnnotationConfigApplicationContext()){
            context.getBeanFactory().registerSingleton("jdbc",new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:split-bean-test;MODE=MySQL","sa","")));
            context.getBeanFactory().registerSingleton("access",mock(GuardianAccess.class));
            context.getBeanFactory().registerSingleton("equipment",mock(PersonEquipmentContext.class));
            context.getBeanFactory().registerSingleton("bridge",mock(SplitHelmetBridge.class));
            context.register(SplitHelmetProperties.class,SplitHelmetClient.class,SplitHelmetStore.class,SplitHelmetService.class,SplitHelmetCallbackController.class,SplitHelmetSessionController.class);
            context.refresh();
            assertFalse(context.getBean(SplitHelmetService.class).enabled());
            assertFalse(context.getBean(SplitHelmetClient.class).configured());
            assertNotNull(context.getBean(SplitHelmetCallbackController.class));
            assertNotNull(context.getBean(SplitHelmetSessionController.class));
        }
    }
}
