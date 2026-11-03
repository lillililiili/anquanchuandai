package com.ruoyi.database;
import com.alibaba.fastjson2.*;
import com.ruoyi.common.database.DatabaseDialect;
import com.ruoyi.guardian.*;
import com.ruoyi.fuda.FudaPushOutbox;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
class RealDatabaseContract {
 void verify(String configFile,DatabaseDialect product,String resetFlag) throws Exception {
  JSONObject config=JSON.parseObject(new String(Files.readAllBytes(Paths.get(System.getenv(configFile))),StandardCharsets.UTF_8));
  DriverManagerDataSource source=new DriverManagerDataSource();source.setDriverClassName(product==DatabaseDialect.DM8?"dm.jdbc.driver.DmDriver":"com.mysql.cj.jdbc.Driver");source.setUrl(config.getString("jdbcUrl"));source.setUsername(config.getString("username"));source.setPassword(config.getString("password"));
  JdbcTemplate jdbc=new JdbcTemplate(source);assertEquals(product,DatabaseDialect.of(jdbc));
  if("true".equals(System.getenv(resetFlag))) {
   if(product==DatabaseDialect.DM8) {
    assertEquals("WEARABLE_TEST",config.getString("username"));
    for(String table:jdbc.query("SELECT TABLE_NAME FROM USER_TABLES",(rs,n)->rs.getString(1))) {DatabaseDialect.identifier(table);jdbc.execute("DROP TABLE "+table+" CASCADE CONSTRAINTS");}
   } else {
    assertEquals("wearable_test",config.getString("username"));assertEquals("wearable_test",jdbc.queryForObject("SELECT DATABASE()",String.class));
    jdbc.execute((org.springframework.jdbc.core.ConnectionCallback<Void>)c->{
     try(java.sql.Statement statement=c.createStatement()) {
      statement.execute("SET FOREIGN_KEY_CHECKS=0");java.util.List<String> tables=new ArrayList<>();
      try(java.sql.ResultSet r=statement.executeQuery("SHOW TABLES")){while(r.next())tables.add(r.getString(1));}
      try{for(String table:tables){DatabaseDialect.identifier(table);statement.execute("DROP TABLE "+table);}}
      finally{statement.execute("SET FOREIGN_KEY_CHECKS=1");}
     }return null;
    });
   }
  }
  SchemaLifecycle schema=new SchemaLifecycle(jdbc);schema.migrate(SchemaLifecycle.all(product));schema.validate(SchemaLifecycle.all(product));
  SchemaLifecycle.configure(source,product.name().toLowerCase(Locale.ROOT),"validate");
  org.apache.ibatis.session.SqlSessionFactory sf=DatabaseMapperContractTest.factory(source,product==DatabaseDialect.DM8?"dm8":"mysql");
  try(org.apache.ibatis.session.SqlSession session=sf.openSession(true)) {
   com.ruoyi.system.mapper.SysUserMapper mapper=session.getMapper(com.ruoyi.system.mapper.SysUserMapper.class);
   com.ruoyi.common.core.domain.entity.SysUser user=new com.ruoyi.common.core.domain.entity.SysUser();user.setUserName("contract-user");user.setNickName("Contract");user.setDeptId(1L);
   assertEquals(1,mapper.insertUser(user));assertNotNull(user.getUserId());assertTrue(user.getUserId()>0);
   assertEquals(user.getUserId(),mapper.checkUserNameUnique("contract-user").getUserId());
   com.ruoyi.common.core.domain.entity.SysUser query=new com.ruoyi.common.core.domain.entity.SysUser();query.setDeptId(1L);query.getParams().put("beginTime","2000-01-01");query.getParams().put("endTime","2099-01-01");
   assertEquals(1,mapper.selectUserList(query).size());
   com.ruoyi.quartz.mapper.SysJobMapper jobs=session.getMapper(com.ruoyi.quartz.mapper.SysJobMapper.class);
   com.ruoyi.quartz.domain.SysJob job=new com.ruoyi.quartz.domain.SysJob();job.setJobName("contract-job");job.setJobGroup("DEFAULT");job.setInvokeTarget("contract.noop");job.setCronExpression("0 0 0 * * ?");
   assertEquals(1,jobs.insertJob(job));assertNotNull(job.getJobId());assertNotNull(jobs.selectJobById(job.getJobId()));
  }
  HelmetBusinessJournal helmetJournal=new HelmetBusinessJournal(jdbc);
  JSONObject location=JSON.parseObject("{\"id\":\"location-contract\",\"deviceId\":\"helmet-contract\",\"personId\":\"person-contract\",\"receivedMillis\":1000}");
  helmetJournal.offlineLocation(location);helmetJournal.offlineLocation(location);assertEquals(1,helmetJournal.locations("person-contract",null,0,2000,0,"",10).size());
  WearableMaintenance maintenance=new WearableMaintenance(jdbc);assertFalse(maintenance.paused());
  WearableBusinessStore store=new WearableBusinessStore(jdbc);
  JSONObject empty=JSON.parseObject("{\"version\":1,\"seq\":0,\"stations\":[],\"people\":[],\"devices\":[],\"events\":[],\"locations\":[]}");
  WearableBusinessStore.Snapshot initial=store.load("guardian",null,()->empty);
  initial.state.put("large",String.join("",Collections.nCopies(70000,"x")));
  long revision=store.save("guardian",initial.revision,initial.state,null);
  assertEquals(initial.state,store.read("guardian").state);
  assertThrows(IllegalStateException.class,()->store.save("guardian",revision,empty,()->{throw new IllegalStateException("rollback");}));
  assertEquals(revision,store.read("guardian").revision);
  JSONObject payload=JSON.parseObject("{\"enabled\":true,\"time\":\"2026-11-03T00:00:00Z\"}");
  long sequence=store.appendDeviceReport("contract-receipt","direct-belt","belt-contract",payload);
  assertEquals(sequence,store.appendDeviceReport("contract-receipt","direct-belt","belt-contract",payload));
  assertThrows(IllegalStateException.class,()->store.appendDeviceReport("contract-receipt","direct-belt","belt-contract",new JSONObject()));
  assertEquals(1,store.pendingReports(0,10).size());
  assertTrue(store.processReport("contract-receipt",()->{}));assertFalse(store.processReport("contract-receipt",()->fail("duplicate handler")));
  AdminLedgerStore ledger=new AdminLedgerStore(jdbc);JSONObject state=ledger.read();assertNotNull(state);ledger.write(state);assertEquals(JSON.parseObject(state.toJSONString()),JSON.parseObject(ledger.read().toJSONString()));
  assertTrue(Math.abs(product.dbTimeMillis(jdbc)-System.currentTimeMillis())<5000);
  assertEquals(Boolean.TRUE,jdbc.queryForObject("SELECT enabled FROM wearable_role WHERE id='mobile-user'",(rs,n)->rs.getBoolean(1)));
  FudaAlarmJournal journal=new FudaAlarmJournal(jdbc);
  WearableBusinessStore.Snapshot alarms=store.read("guardian");
  JSONObject belt=JSON.parseObject("{\"id\":\"belt-contract\",\"type\":\"B\",\"source\":\"DIRECT_BELT\",\"deviceNumber\":\"B-CONTRACT\"}");alarms.state.getJSONArray("devices").add(belt);
  JSONObject alarm=JSON.parseObject("{\"id\":\"alarm-contract-one\",\"deviceId\":\"belt-contract\",\"source\":\"device\",\"protocol\":\"direct-belt\",\"createdAt\":\"2026-11-03T00:00:00Z\"}");alarms.state.getJSONArray("events").add(alarm);store.save("guardian",alarms.revision,alarms.state,null);
  FudaAlarmJournal.AlarmPage page=journal.scan(0,1,Collections.singleton("SAFETY_BELT:B-CONTRACT"));assertEquals(1,page.items.size());long cursor=page.nextSequence;
  WearableBusinessStore.Snapshot late=store.read("guardian");JSONObject older=JSON.parseObject(alarm.toJSONString());older.put("id","alarm-contract-late");older.put("createdAt","2026-01-01T00:00:00Z");late.state.getJSONArray("events").add(older);store.save("guardian",late.revision,late.state,null);
  assertEquals("alarm-contract-late",journal.scan(cursor,1,Collections.singleton("SAFETY_BELT:B-CONTRACT")).items.get(0).getString("eventId"));
  long committed=journal.highWatermark();
  CountDownLatch allocatedFirst=new CountDownLatch(1),releaseFirst=new CountDownLatch(1),startedSecond=new CountDownLatch(1),allocatedSecond=new CountDownLatch(1),releaseSecond=new CountDownLatch(1);
  ExecutorService journalWorkers=Executors.newFixedThreadPool(2);
  JSONObject firstAlarm=JSON.parseObject(alarm.toJSONString());firstAlarm.put("id","alarm-commit-first");
  JSONObject secondAlarm=JSON.parseObject(alarm.toJSONString());secondAlarm.put("id","alarm-commit-second");
  JSONObject firstEvidence=new JSONObject();firstEvidence.put("devices",new JSONArray(Collections.singletonList(belt)));firstEvidence.put("events",new JSONArray(Collections.singletonList(firstAlarm)));
  JSONObject secondEvidence=JSON.parseObject(firstEvidence.toJSONString());secondEvidence.put("events",new JSONArray(Collections.singletonList(secondAlarm)));
  TransactionTemplate journalTx=new TransactionTemplate(new DataSourceTransactionManager(source));
  try {
   Future<?> first=journalWorkers.submit(()->journalTx.execute(status->{org.springframework.test.util.ReflectionTestUtils.invokeMethod(journal,"appendNew",firstEvidence,Collections.emptySet(),false);allocatedFirst.countDown();await(releaseFirst);return null;}));
   assertTrue(allocatedFirst.await(15,TimeUnit.SECONDS));
   Future<?> second=journalWorkers.submit(()->journalTx.execute(status->{startedSecond.countDown();org.springframework.test.util.ReflectionTestUtils.invokeMethod(journal,"appendNew",secondEvidence,Collections.emptySet(),false);allocatedSecond.countDown();await(releaseSecond);return null;}));
   assertTrue(startedSecond.await(5,TimeUnit.SECONDS));assertFalse(allocatedSecond.await(200,TimeUnit.MILLISECONDS));
   assertEquals(committed,journal.highWatermark());assertTrue(journal.scan(committed,10,Collections.singleton("SAFETY_BELT:B-CONTRACT")).items.isEmpty());
   releaseFirst.countDown();first.get(15,TimeUnit.SECONDS);assertTrue(allocatedSecond.await(15,TimeUnit.SECONDS));
   FudaAlarmJournal.AlarmPage firstPage=journal.scan(committed,10,Collections.singleton("SAFETY_BELT:B-CONTRACT"));assertEquals(committed+1,firstPage.nextSequence);assertEquals("alarm-commit-first",firstPage.items.get(0).getString("eventId"));
   releaseSecond.countDown();second.get(15,TimeUnit.SECONDS);
   assertEquals("alarm-commit-second",journal.scan(firstPage.nextSequence,10,Collections.singleton("SAFETY_BELT:B-CONTRACT")).items.get(0).getString("eventId"));
  } finally {releaseFirst.countDown();releaseSecond.countDown();journalWorkers.shutdownNow();}
  FudaPushOutbox box=new FudaPushOutbox(jdbc);TransactionTemplate tx=new TransactionTemplate(new DataSourceTransactionManager(source));
  JSONObject envelope=JSON.parseObject("{\"eventId\":\"contract-push\",\"eventType\":\"STATUS\",\"data\":{\"enabled\":true}}");
  tx.execute(s->{box.enqueue("contract","device","BELT","belt-contract",envelope,1000);box.enqueue("contract","device","BELT","belt-contract",envelope,1000);return null;});
  assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox",Integer.class));
  ExecutorService pool=Executors.newFixedThreadPool(2);
  try {
   Future<FudaPushOutbox.Delivery> a=pool.submit(()->box.claim("contract",1000,30000));Future<FudaPushOutbox.Delivery> b=pool.submit(()->box.claim("contract",1000,30000));
   FudaPushOutbox.Delivery first=a.get(15,TimeUnit.SECONDS),second=b.get(15,TimeUnit.SECONDS);assertTrue((first==null) != (second==null));
   FudaPushOutbox.Delivery claimed=first==null?second:first;FudaPushOutbox.Delivery renewed=box.claim("contract",31001,30000);
   assertNotEquals(claimed.leaseToken,renewed.leaseToken);assertFalse(box.finish(claimed,"DELIVERED","OK",200,31002,0));assertTrue(box.finish(renewed,"DELIVERED","OK",200,31002,0));
  } finally {pool.shutdownNow();}
 }
 private static void await(CountDownLatch latch) {
  try{if(!latch.await(30,TimeUnit.SECONDS))throw new IllegalStateException("test release timeout");}
  catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException(e);}
 }
}
