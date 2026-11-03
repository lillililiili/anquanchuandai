package com.ruoyi.generator.service;
import org.aspectj.lang.annotation.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import com.ruoyi.common.exception.ServiceException;
/** Existing code templates and metadata queries are MySQL-only. Business operations are unaffected. */
@Aspect @Component
public class GeneratorDatabaseGuard {
 @Value("${melhat.database.product:mysql}") private String product="mysql";
 @Before("execution(public * com.ruoyi.generator.service.*.*(..)) && !within(com.ruoyi.generator.service.GeneratorDatabaseGuard)")
 public void requireSupportedDatabase() {
  if(!"mysql".equalsIgnoreCase(product))throw new ServiceException("当前数据库不支持代码生成；DM8 业务功能不受影响");
 }
}
