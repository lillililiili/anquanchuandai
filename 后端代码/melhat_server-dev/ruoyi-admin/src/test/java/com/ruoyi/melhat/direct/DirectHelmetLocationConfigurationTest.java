package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.io.ClassPathResource;
import static org.junit.jupiter.api.Assertions.*;

class DirectHelmetLocationConfigurationTest {
    @Test void documentedHelmetCellProfileBindsWithoutInferringOtherDevicesOrSources() throws Exception {
        DirectHelmetLocationProfiles profiles=new Binder(ConfigurationPropertySources.from(
                new YamlPropertySourceLoader().load("application",new ClassPathResource("application.yml"))))
                .bind("melhat.direct-location",Bindable.of(DirectHelmetLocationProfiles.class)).get();
        JSONObject point=JSONObject.parseObject("{\"latitude\":30,\"longitude\":110,\"locationSource\":\"CELL\"}");
        profiles.apply("866652021714127",point);assertEquals("GCJ02",point.getString("coordinateSystem"));assertEquals("valid",point.getString("locationQuality"));
        point.put("firmware","uncommissioned-firmware");profiles.apply("866652021714127",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
        point.remove("firmware");point.put("locationSource","UNKNOWN");profiles.apply("866652021714127",point);assertEquals("unknown",point.getString("locationQuality"));
        point.put("locationSource","CELL");profiles.apply("866652023095053",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
        profiles.apply("unknown-helmet",point);assertEquals("UNKNOWN",point.getString("coordinateSystem"));
    }
}
