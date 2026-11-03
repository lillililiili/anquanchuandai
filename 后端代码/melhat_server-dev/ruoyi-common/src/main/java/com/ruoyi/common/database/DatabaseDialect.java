package com.ruoyi.common.database;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.DataIntegrityViolationException;
import java.sql.*;
import java.util.*;

/** Closed set of supported SQL contracts. Values are always JDBC parameters. */
public enum DatabaseDialect {
 MYSQL, DM8, H2;
 public static DatabaseDialect detect(String product) {
  if ("MySQL".equalsIgnoreCase(product)) return MYSQL;
  if ("DM DBMS".equalsIgnoreCase(product) || "DM".equalsIgnoreCase(product)) return DM8;
  if ("H2".equalsIgnoreCase(product)) return H2; // Test compatibility only; never a production profile.
  throw new IllegalStateException("Unsupported database product: "+product);
 }
 public void requireProduct(String product) {
  DatabaseDialect actual=detect(product);
  if(this!=actual)throw new IllegalStateException("Configured database "+this+" does not match JDBC product "+actual);
 }
 public static DatabaseDialect of(JdbcTemplate jdbc) {
  return jdbc.execute((ConnectionCallback<DatabaseDialect>)c->detect(c.getMetaData().getDatabaseProductName()));
 }
 public long dbTimeMillis(JdbcTemplate jdbc) {
  return jdbc.queryForObject(this==DM8?"SELECT CURRENT_TIMESTAMP FROM DUAL":"SELECT CURRENT_TIMESTAMP",(rs,n)->rs.getTimestamp(1).getTime());
 }
 public String limit(String select,String count) {
  if(!"?".equals(count)&&!count.matches("[0-9]+"))throw new IllegalArgumentException("Invalid row limit");
  return select+(this==DM8?" FETCH FIRST "+count+" ROWS ONLY":" LIMIT "+count);
 }
 public String upsertSql(String table,List<String> columns,List<String> keys,List<String> updates) {
  identifier(table); columns.forEach(DatabaseDialect::identifier);keys.forEach(DatabaseDialect::identifier);updates.forEach(DatabaseDialect::identifier);
  if(columns.isEmpty()||keys.isEmpty()||!columns.containsAll(keys)||!columns.containsAll(updates))throw new IllegalArgumentException("Invalid upsert columns");
  String names=String.join(",",columns), params=String.join(",",Collections.nCopies(columns.size(),"?"));
  if(this!=DM8) {
   List<String> assignments=new ArrayList<>();
   for(String c:updates)assignments.add(c+"=VALUES("+c+")");
   if(assignments.isEmpty())assignments.add(keys.get(0)+"="+keys.get(0));
   return "INSERT INTO "+table+" ("+names+") VALUES ("+params+") ON DUPLICATE KEY UPDATE "+String.join(",",assignments);
  }
  List<String> select=new ArrayList<>(),on=new ArrayList<>(),set=new ArrayList<>(),values=new ArrayList<>();
  for(String c:columns){select.add("? AS "+c);values.add("s."+c);}
  for(String k:keys)on.add("t."+k+"=s."+k);
  for(String c:updates)if(!keys.contains(c))set.add("t."+c+"=s."+c);
  return "MERGE INTO "+table+" t USING (SELECT "+String.join(",",select)+" FROM DUAL) s ON ("+String.join(" AND ",on)+")"
    +(set.isEmpty()?"":" WHEN MATCHED THEN UPDATE SET "+String.join(",",set))
    +" WHEN NOT MATCHED THEN INSERT ("+names+") VALUES ("+String.join(",",values)+")";
 }
 public int upsert(JdbcTemplate jdbc,String table,List<String> columns,List<String> keys,Object... values) {
  List<String> updates=new ArrayList<>(columns);updates.removeAll(keys);
  return jdbc.update(upsertSql(table,columns,keys,updates),values);
 }
 /** A duplicate unique identity is a no-op; every other constraint/error propagates. */
 public int insertIfAbsent(JdbcTemplate jdbc,String table,List<String> columns,List<String> keys,Object... values) {
  identifier(table);columns.forEach(DatabaseDialect::identifier);keys.forEach(DatabaseDialect::identifier);
  String sql="INSERT INTO "+table+" ("+String.join(",",columns)+") VALUES ("+String.join(",",Collections.nCopies(values.length,"?"))+")";
  try {return jdbc.update(sql,values);}catch(DuplicateKeyException duplicate){return 0;}
  catch(DataIntegrityViolationException error) {
   // Spring 5 has no DM vendor mapping. -6602 is DM's unique constraint violation.
   Throwable cause=error;while(cause!=null){if(this==DM8&&cause instanceof SQLException&&((SQLException)cause).getErrorCode()==-6602)return 0;cause=cause.getCause();}
   throw error;
  }
 }
 public static void identifier(String value) {
  if(value==null||!value.matches("[A-Za-z_][A-Za-z0-9_]*"))throw new IllegalArgumentException("Invalid SQL identifier");
 }
 public static boolean tableExists(JdbcTemplate jdbc,String table) {
  identifier(table);
  return jdbc.execute((ConnectionCallback<Boolean>)c->{
   String name=c.getMetaData().storesUpperCaseIdentifiers()?table.toUpperCase(Locale.ROOT):table;
   try(ResultSet r=c.getMetaData().getTables(c.getCatalog(),c.getSchema(),name,new String[]{"TABLE"})){return r.next();}
  });
 }
}
