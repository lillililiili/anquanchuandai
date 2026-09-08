package com.ruoyi.common.annotation;

import java.lang.annotation.*;

/**
 * 任务数据过滤注解
 * 
 * @author ruoyi
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface TaskStateFinishScope
{

    /**
     * 任务表的别名
     */
    public String taskAlias() default "";

    /**
     * 权限字符（用于多个角色匹配符合要求的权限）默认根据权限注解@ss获取，多个权限用逗号分隔开来
     */
    public String permission() default "";
}
