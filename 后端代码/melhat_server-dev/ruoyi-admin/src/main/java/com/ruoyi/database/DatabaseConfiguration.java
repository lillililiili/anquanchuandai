package com.ruoyi.database;
import javax.sql.DataSource;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.*;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ruoyi.common.database.DatabaseDialect;
@Configuration
public class DatabaseConfiguration {
 @Bean public static BeanPostProcessor databaseContract(Environment env) {
  return new BeanPostProcessor() {
   @Override public Object postProcessAfterInitialization(Object bean,String name) {
    if(bean instanceof DataSource&&"dynamicDataSource".equals(name)) {
     DataSource source=(DataSource)bean;
     String product=env.getProperty("melhat.database.product","mysql");
     String mode=env.getProperty("melhat.database.schema-mode","legacy");
     if(env.getProperty("melhat.cluster.enabled",Boolean.class,false)&&!"validate".equals(mode))throw new IllegalStateException("Cluster startup requires melhat.database.schema-mode=validate");
     SchemaLifecycle.configure(source,product,mode);
     if("validate".equals(mode))new SchemaLifecycle(new JdbcTemplate(source)).validate(SchemaLifecycle.all(DatabaseDialect.of(new JdbcTemplate(source))));
    }
    return bean;
   }
  };
 }
}
