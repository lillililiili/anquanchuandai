package com.ruoyi.common.database;
import org.springframework.jdbc.core.JdbcTemplate;
/** Commissioned DM8 settings are part of the SQL/data contract, not deployment suggestions. */
public final class DatabaseRuntimeContract {
 private DatabaseRuntimeContract(){}
 public static void verify(JdbcTemplate jdbc) {
  if(DatabaseDialect.of(jdbc)!=DatabaseDialect.DM8)return;
  int compatible=jdbc.queryForObject("SELECT CAST(PARA_VALUE AS INT) FROM V$DM_INI WHERE PARA_NAME='COMPATIBLE_MODE'",Integer.class);
  int strict=jdbc.queryForObject("SELECT CAST(PARA_VALUE AS INT) FROM V$DM_INI WHERE PARA_NAME='MY_STRICT_TABLES'",Integer.class);
  int caseSensitive=jdbc.queryForObject("SELECT SF_GET_CASE_SENSITIVE_FLAG() FROM DUAL",Integer.class);
  int unicode=jdbc.queryForObject("SELECT SF_GET_UNICODE_FLAG() FROM DUAL",Integer.class);
  validateDmParameters(compatible,strict,caseSensitive,unicode);
 }
 public static void validateDmParameters(int compatible,int strict,int caseSensitive,int unicode) {
  if(compatible!=4||(strict&7)!=7||caseSensitive!=0||unicode!=1)
   throw new IllegalStateException("DM8 runtime contract requires COMPATIBLE_MODE=4, MY_STRICT_TABLES strict bits 1/2/4, CASE_SENSITIVE=0 and UTF8; actual values: "+compatible+","+strict+","+caseSensitive+","+unicode);
 }
}
