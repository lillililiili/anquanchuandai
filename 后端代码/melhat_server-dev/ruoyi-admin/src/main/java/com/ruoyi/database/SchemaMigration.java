package com.ruoyi.database;
import com.ruoyi.common.database.DatabaseDialect;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
/** Dedicated pre-start process; no web/services/schedulers are initialized. Credentials only come from environment. */
public final class SchemaMigration {
 private SchemaMigration(){}
 public static void main(String[] args) {
  if(args.length!=0)throw new IllegalArgumentException("SchemaMigration accepts no command-line credentials; configure MELHAT_DB_* environment variables");
  String product=required("MELHAT_DB_PRODUCT");DatabaseDialect dialect;
  try{dialect=DatabaseDialect.valueOf(product.toUpperCase(java.util.Locale.ROOT));}catch(Exception e){throw new IllegalStateException("Unsupported configured database");}
  if(dialect==DatabaseDialect.H2)throw new IllegalArgumentException("H2 is test-only");
  SingleConnectionDataSource source=new SingleConnectionDataSource();source.setSuppressClose(true);source.setDriverClassName(dialect==DatabaseDialect.DM8?"dm.jdbc.driver.DmDriver":"com.mysql.cj.jdbc.Driver");
  source.setUrl(required("MELHAT_DB_URL"));source.setUsername(required("MELHAT_DB_USERNAME"));source.setPassword(required("MELHAT_DB_PASSWORD"));
  try{JdbcTemplate jdbc=new JdbcTemplate(source);dialect.requireProduct(jdbc.execute((org.springframework.jdbc.core.ConnectionCallback<String>)c->c.getMetaData().getDatabaseProductName()));
  SchemaLifecycle schema=new SchemaLifecycle(jdbc);schema.migrate(SchemaLifecycle.all(dialect));schema.validate(SchemaLifecycle.all(dialect));
  System.out.println("Schema migration and checksum validation complete for "+dialect);
  }finally{source.destroy();}
 }
 private static String required(String key){String value=System.getenv(key);if(value==null||value.isEmpty())throw new IllegalStateException("Missing environment variable "+key);return value;}
}
