package com.ruoyi.database;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
class SchemaLifecycleTest {
 private JdbcTemplate db(){return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));}
 @Test void validationNeverCreatesTablesAndMigrationIsRepeatable() {
  JdbcTemplate j=db();SchemaLifecycle s=new SchemaLifecycle(j);
  SchemaLifecycle.Migration m=new SchemaLifecycle.Migration("one","CREATE TABLE sample(id INT PRIMARY KEY)");
  assertThrows(IllegalStateException.class,()->s.validate(Arrays.asList(m)));
  assertFalse(com.ruoyi.common.database.DatabaseDialect.tableExists(j,"sample"));
  s.migrate(Arrays.asList(m));s.migrate(Arrays.asList(m));s.validate(Arrays.asList(m));
  assertEquals(1,j.queryForObject("SELECT COUNT(*) FROM wearable_schema_history WHERE state='COMPLETE'",Integer.class));
  assertThrows(IllegalStateException.class,()->s.validate(Arrays.asList(new SchemaLifecycle.Migration("one","CREATE TABLE sample(id BIGINT PRIMARY KEY)"))));
 }
 @Test void failedDdlNeverBecomesCompleteAndNeedsExplicitRepair() {
  JdbcTemplate j=db();SchemaLifecycle s=new SchemaLifecycle(j);
  SchemaLifecycle.Migration m=new SchemaLifecycle.Migration("broken","CREATE TABLE first_step(id INT); INVALID SQL");
  assertThrows(RuntimeException.class,()->s.migrate(Arrays.asList(m)));
  assertEquals("FAILED",j.queryForObject("SELECT state FROM wearable_schema_history WHERE version_id='broken'",String.class));
  assertEquals(1,j.queryForObject("SELECT COUNT(*) FROM wearable_schema_step WHERE state='COMPLETE'",Integer.class));
  assertThrows(IllegalStateException.class,()->s.migrate(Arrays.asList(m)));
  assertThrows(IllegalStateException.class,()->s.validate(Arrays.asList(m)));
 }
 @Test void constructorsInValidateModeCannotApplyDdl() {
  JdbcTemplate j=db();SchemaLifecycle.configure(j.getDataSource(),"h2","validate");
  assertThrows(IllegalStateException.class,()->new com.ruoyi.guardian.WearableBusinessStore(j));
  assertFalse(com.ruoyi.common.database.DatabaseDialect.tableExists(j,"wearable_business_meta"));
 }
 @Test void migrationCannotCommitAnExistingBusinessTransactionThroughDdl() {
  JdbcTemplate j=db();org.springframework.transaction.support.TransactionTemplate tx=new org.springframework.transaction.support.TransactionTemplate(new org.springframework.jdbc.datasource.DataSourceTransactionManager(j.getDataSource()));
  tx.execute(status->{assertThrows(IllegalStateException.class,()->new SchemaLifecycle(j).migrate(Arrays.asList(new SchemaLifecycle.Migration("inside_tx","CREATE TABLE forbidden(id INT)"))));return null;});
  assertFalse(com.ruoyi.common.database.DatabaseDialect.tableExists(j,"wearable_schema_history"));
 }
 @Test void legacyConstructionRejectsTrackedSchemaDriftInsteadOfPretendingItWasRepaired() {
  JdbcTemplate j=db();new com.ruoyi.guardian.HelmetBusinessJournal(j);j.execute("DROP TABLE helmet_location_fix");
  assertThrows(IllegalStateException.class,()->new com.ruoyi.guardian.HelmetBusinessJournal(j));
 }
 @Test void checksumsSurviveWindowsToKylinLineEndingChanges() {
  JdbcTemplate j=db();SchemaLifecycle schema=new SchemaLifecycle(j);
  schema.migrate(Arrays.asList(new SchemaLifecycle.Migration("portable","CREATE TABLE portable(id INT);\r\n")));
  assertDoesNotThrow(()->schema.validate(Arrays.asList(new SchemaLifecycle.Migration("portable","CREATE TABLE portable(id INT);\n"))));
 }
}
