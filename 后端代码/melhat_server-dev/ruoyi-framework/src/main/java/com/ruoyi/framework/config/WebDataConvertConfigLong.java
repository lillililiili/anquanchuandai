package com.ruoyi.framework.config;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.MapperFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.module.SimpleModule;
import com.fasterxml.jackson.databind.ser.std.ToStringSerializer;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.http.converter.json.Jackson2ObjectMapperBuilder;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;

import java.text.SimpleDateFormat;
import java.util.TimeZone;

@Configuration
public class WebDataConvertConfigLong {

    @Bean
    public MappingJackson2HttpMessageConverter jackson2HttpMessageConverter() {
        final Jackson2ObjectMapperBuilder builder = new Jackson2ObjectMapperBuilder();
        //字段为null，也会被包含在序列化结果中。
        builder.serializationInclusion(JsonInclude.Include.ALWAYS);

        final ObjectMapper objectMapper = builder.build();
        SimpleModule simpleModule = new SimpleModule();

        // Long 转为 String 防止 js 丢失精度
        simpleModule.addSerializer(Long.class, ToStringSerializer.instance);
//        simpleModule.addSerializer(Long.TYPE, ToStringSerializer.instance);//long 类型不转化
        objectMapper.registerModule(simpleModule);
        // 忽略 transient 关键词属性
//        objectMapper.configure(MapperFeature.PROPAGATE_TRANSIENT_MARKER, true);

        // 设置序列化传输时间为东八区时区
       objectMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        // FIXME:序列化默认日期格式 请使用@JsonFormat(pattern = "yyyy-MM-dd") 自定义时间格式
       objectMapper.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        // FIXME:序列化默认日期格式 请使用@JsonFormat(pattern = "yyyy-MM-dd") 自定义时间格式
      objectMapper.setDateFormat(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss"));
        return new MappingJackson2HttpMessageConverter(objectMapper);
    }
}
