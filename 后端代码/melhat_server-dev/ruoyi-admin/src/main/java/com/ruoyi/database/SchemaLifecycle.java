package com.ruoyi.database;

import com.ruoyi.common.database.DatabaseDialect;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.util.StreamUtils;
import javax.sql.DataSource;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** DDL is an operator action on DM8 and cluster deployments. No DDL runs during validation. */
public final class SchemaLifecycle {
 private static final Map<DataSource,String> MODES=Collections.synchronizedMap(new WeakHashMap<>());
 public static final String[] BUSINESS={"20261003_wearable_master","20261023_helmet_business","20261026_wearable_business","20261027_fuda_alarm_journal","20261102_fuda_push_outbox","20261103_shared_files","20261103_cluster_routing"};
 private final JdbcTemplate jdbc;
 public SchemaLifecycle(JdbcTemplate jdbc){this.jdbc=jdbc;}
 public static void configure(DataSource source,String product,String mode) {
  DatabaseDialect configured;
  try{configured=DatabaseDialect.valueOf(product.toUpperCase(Locale.ROOT));}catch(Exception e){throw new IllegalStateException("Unsupported configured database: "+product);}
  configured.requireProduct(new JdbcTemplate(source).execute((org.springframework.jdbc.core.ConnectionCallback<String>)c->c.getMetaData().getDatabaseProductName()));
  if(!Arrays.asList("legacy","validate").contains(mode))throw new IllegalStateException("Application schema mode must be legacy or validate; use SchemaMigration for migrate");
  if(configured==DatabaseDialect.DM8&&"legacy".equals(mode))throw new IllegalStateException("DM8 startup is validate-only; run SchemaMigration before application startup");
  MODES.put(source,mode);
 }
 public static void ensure(JdbcTemplate jdbc,String resource) {
  DatabaseDialect d=DatabaseDialect.of(jdbc);
  String mode=MODES.get(jdbc.getDataSource());
  if(mode==null)mode=d==DatabaseDialect.DM8?"validate":"legacy";
  SchemaLifecycle s=new SchemaLifecycle(jdbc);List<Migration> list=Collections.singletonList(resource(d,resource));
  if("legacy".equals(mode))s.migrate(list);
  s.validate(list);
 }
 public static Migration resource(DatabaseDialect dialect,String name) {
  String path="db/"+(dialect==DatabaseDialect.DM8?"dm8/":"mysql/")+name+".sql";
  try{return new Migration(name,StreamUtils.copyToString(new ClassPathResource(path).getInputStream(),StandardCharsets.UTF_8));}
  catch(Exception e){throw new IllegalStateException("Missing database migration "+path,e);}
 }
 public static List<Migration> all(DatabaseDialect d) {
  List<Migration> list=new ArrayList<>();list.add(resource(d,"00000000_base"));
  for(String n:BUSINESS)list.add(resource(d,n));return list;
 }
 public static final class Migration {
  final String id,sql,checksum;
  public Migration(String id,String sql){DatabaseDialect.identifier(id.replace('-','_').replaceFirst("^[0-9]","v"));this.id=id;this.sql=sql.replace("\r\n","\n").replace('\r','\n');this.checksum=sha(this.sql);}
 }
 private void bootstrap() {
  if(!DatabaseDialect.tableExists(jdbc,"wearable_schema_history"))jdbc.execute("CREATE TABLE wearable_schema_history(version_id VARCHAR(100) PRIMARY KEY,checksum CHAR(64) NOT NULL,state VARCHAR(16) NOT NULL,updated_at BIGINT NOT NULL)");
  if(!DatabaseDialect.tableExists(jdbc,"wearable_schema_step"))jdbc.execute("CREATE TABLE wearable_schema_step(version_id VARCHAR(100) NOT NULL,step_no INT NOT NULL,checksum CHAR(64) NOT NULL,state VARCHAR(16) NOT NULL,PRIMARY KEY(version_id,step_no))");
  if(!DatabaseDialect.tableExists(jdbc,"wearable_schema_lock"))jdbc.execute("CREATE TABLE wearable_schema_lock(id INT PRIMARY KEY,owner VARCHAR(36))");
  DatabaseDialect.of(jdbc).insertIfAbsent(jdbc,"wearable_schema_lock",Arrays.asList("id","owner"),Arrays.asList("id"),1,null);
 }
 public void validate(List<Migration> migrations) {
  com.ruoyi.common.database.DatabaseRuntimeContract.verify(jdbc);
  if(!DatabaseDialect.tableExists(jdbc,"wearable_schema_history"))throw new IllegalStateException("Schema not migrated; run SchemaMigration before startup");
  for(Migration m:migrations) {
   List<Map<String,Object>> rows=jdbc.queryForList("SELECT checksum,state FROM wearable_schema_history WHERE version_id=?",m.id);
   if(rows.size()!=1||!m.checksum.equals(rows.get(0).get("checksum"))||!"COMPLETE".equals(rows.get(0).get("state")))throw new IllegalStateException("Schema migration missing, incomplete or checksum mismatch: "+m.id);
   for(String statement:statements(m.sql)) {
    java.util.regex.Matcher matcher=java.util.regex.Pattern.compile("(?is)^CREATE TABLE(?: IF NOT EXISTS)?\\s+([A-Za-z_][A-Za-z0-9_]*)").matcher(statement.trim());
    if(matcher.find()&&!DatabaseDialect.tableExists(jdbc,matcher.group(1)))throw new IllegalStateException("Schema object missing: "+matcher.group(1));
   }
  }
 }
 public void migrate(List<Migration> migrations) {
  if(org.springframework.transaction.support.TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Schema migration must run outside business transactions; DDL may autocommit");
  com.ruoyi.common.database.DatabaseRuntimeContract.verify(jdbc);
  bootstrap();String owner=UUID.randomUUID().toString();
  if(jdbc.update("UPDATE wearable_schema_lock SET owner=? WHERE id=1 AND owner IS NULL",owner)!=1)throw new IllegalStateException("Another schema migration owns the database; do not start concurrent migrators");
  try {for(Migration m:migrations)apply(m);}finally{jdbc.update("UPDATE wearable_schema_lock SET owner=NULL WHERE id=1 AND owner=?",owner);}
 }
 private void apply(Migration m) {
  List<Map<String,Object>> old=jdbc.queryForList("SELECT checksum,state FROM wearable_schema_history WHERE version_id=?",m.id);
  if(!old.isEmpty()) {
   if(!m.checksum.equals(old.get(0).get("checksum")))throw new IllegalStateException("Schema checksum mismatch: "+m.id);
   if("COMPLETE".equals(old.get(0).get("state")))return;
   throw new IllegalStateException("Migration "+m.id+" is incomplete. DDL may have committed. Inspect wearable_schema_step and reconcile explicitly before retry; never mark COMPLETE without executing remaining steps.");
  }
  jdbc.update("INSERT INTO wearable_schema_history(version_id,checksum,state,updated_at) VALUES (?,?,'STARTED',?)",m.id,m.checksum,System.currentTimeMillis());
  List<String> steps=statements(m.sql);
  try {
   for(int i=0;i<steps.size();i++) {
    jdbc.update("INSERT INTO wearable_schema_step(version_id,step_no,checksum,state) VALUES (?,?,?,'STARTED')",m.id,i+1,sha(steps.get(i)));
    jdbc.execute(steps.get(i));
    jdbc.update("UPDATE wearable_schema_step SET state='COMPLETE' WHERE version_id=? AND step_no=?",m.id,i+1);
   }
   jdbc.update("UPDATE wearable_schema_history SET state='COMPLETE',updated_at=? WHERE version_id=?",System.currentTimeMillis(),m.id);
  } catch(RuntimeException error) {
   jdbc.update("UPDATE wearable_schema_history SET state='FAILED',updated_at=? WHERE version_id=?",System.currentTimeMillis(),m.id);throw error;
  }
 }
 @SuppressWarnings("deprecation") private static List<String> statements(String sql) {
  List<String> list=new ArrayList<>();ScriptUtils.splitSqlScript(sql,';',list);return list;
 }
 private static String sha(String s) {
  try {byte[] bytes=MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder();for(byte b:bytes)out.append(String.format("%02x",b&255));return out.toString();}
  catch(Exception e){throw new IllegalStateException(e);}
 }
}
