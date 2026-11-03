package com.ruoyi.database;
import com.ruoyi.common.database.DatabaseDialect;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
class DatabaseDialectTest {
 @Test void productsAreExplicitAndMismatchesFailClosed() {
  assertEquals(DatabaseDialect.DM8, DatabaseDialect.detect("DM DBMS"));
  assertEquals(DatabaseDialect.MYSQL, DatabaseDialect.detect("MySQL"));
  assertThrows(IllegalStateException.class,()->DatabaseDialect.detect("PostgreSQL"));
  assertThrows(IllegalStateException.class,()->DatabaseDialect.MYSQL.requireProduct("DM DBMS"));
 }
 @Test void mergeUsesParametersAndRejectsInjectedIdentifiers() {
  String sql=DatabaseDialect.DM8.upsertSql("wearable_meta",Arrays.asList("id","revision"),Arrays.asList("id"),Arrays.asList("revision"));
  assertTrue(sql.startsWith("MERGE INTO wearable_meta"));
  assertTrue(sql.contains("WHEN MATCHED THEN UPDATE"));
  assertEquals(2,sql.chars().filter(c->c=='?').count());
  assertThrows(IllegalArgumentException.class,()->DatabaseDialect.DM8.upsertSql("x;drop table y",Arrays.asList("id"),Arrays.asList("id"),Collections.emptyList()));
 }
 @Test void compatibilityUpsertPreservesDuplicatePayloadAndDatabaseTime() {
  JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:dialect;MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
  jdbc.execute("CREATE TABLE IF NOT EXISTS sample(id INT PRIMARY KEY,body VARCHAR(40))");
  DatabaseDialect d=DatabaseDialect.of(jdbc);
  assertEquals(1,d.insertIfAbsent(jdbc,"sample",Arrays.asList("id","body"),Arrays.asList("id"),1,"first"));
  assertEquals(0,d.insertIfAbsent(jdbc,"sample",Arrays.asList("id","body"),Arrays.asList("id"),1,"second"));
  assertEquals("first",jdbc.queryForObject("SELECT body FROM sample WHERE id=1",String.class));
  d.upsert(jdbc,"sample",Arrays.asList("id","body"),Arrays.asList("id"),1,"changed");
  assertEquals("changed",jdbc.queryForObject("SELECT body FROM sample WHERE id=1",String.class));
  assertTrue(Math.abs(System.currentTimeMillis()-d.dbTimeMillis(jdbc))<5000);
 }
}
