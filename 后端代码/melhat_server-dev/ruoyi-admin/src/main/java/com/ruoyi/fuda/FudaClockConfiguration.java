package com.ruoyi.fuda;
import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
@Configuration
public class FudaClockConfiguration {
    @Bean("fudaClock") public Clock fudaClock(){return Clock.systemUTC();}
}
