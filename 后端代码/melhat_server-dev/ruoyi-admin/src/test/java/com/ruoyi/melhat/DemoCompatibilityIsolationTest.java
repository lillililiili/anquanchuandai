package com.ruoyi.melhat;

import com.ruoyi.melhat.controller.DemoCompatibilityController;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DemoCompatibilityIsolationTest {

    @Test
    void demoControllerRequiresNonProdAndDemoMode() {
        Profile profile = DemoCompatibilityController.class.getAnnotation(Profile.class);
        assertNotNull(profile);
        assertTrue(Arrays.asList(profile.value()).contains("!prod"));

        ConditionalOnProperty property = DemoCompatibilityController.class.getAnnotation(ConditionalOnProperty.class);
        assertNotNull(property);
        assertTrue(Arrays.asList(property.name()).contains("melhat.demo-mode"));
        assertTrue("true".equals(property.havingValue()));
    }
}
