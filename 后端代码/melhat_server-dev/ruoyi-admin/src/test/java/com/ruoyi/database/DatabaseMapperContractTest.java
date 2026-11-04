package com.ruoyi.database;
import com.ruoyi.framework.config.MyBatisConfig;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.generator.service.GeneratorDatabaseGuard;
import org.apache.ibatis.session.*;
import org.mybatis.spring.SqlSessionFactoryBean;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
class DatabaseMapperContractTest {
 static SqlSessionFactory factory(javax.sql.DataSource source,String database) throws Exception {
  SqlSessionFactoryBean b=new SqlSessionFactoryBean();b.setDataSource(source);
  b.setDatabaseIdProvider(s->database);
  b.setTypeAliasesPackage(new MyBatisConfig().setTypeAliasesPackage("com.ruoyi.**.domain"));
  b.setMapperLocations(new PathMatchingResourcePatternResolver().getResources("classpath*:mapper/**/*Mapper.xml"));
  b.setConfigLocation(new org.springframework.core.io.ClassPathResource("mybatis/mybatis-config.xml"));return b.getObject();
 }
 @Test void dm8MappedSqlUsesChosenDatePaginationAndScopeContracts() throws Exception {
  SqlSessionFactory f=factory(new DriverManagerDataSource("jdbc:h2:mem:mapper","sa",""),"dm8");
  SysUser u=new SysUser();u.setDeptId(1L);u.getParams().put("beginTime","2026-11-01");u.getParams().put("endTime","2026-11-03");
  String sql=f.getConfiguration().getMappedStatement("com.ruoyi.system.mapper.SysUserMapper.selectUserList").getBoundSql(u).getSql().toLowerCase(Locale.ROOT);
  assertFalse(sql.contains("date_format"));assertFalse(sql.contains("find_in_set"));assertTrue(sql.contains("to_char"));assertTrue(sql.contains("instr"));
  String unique=f.getConfiguration().getMappedStatement("com.ruoyi.system.mapper.SysUserMapper.checkUserNameUnique").getBoundSql("test").getSql().toLowerCase(Locale.ROOT);
  assertTrue(unique.contains("fetch first 1 rows only"));assertFalse(unique.contains("limit"));
  String group=f.getConfiguration().getMappedStatement("com.ruoyi.system.mapper.SysUserMapper.getUsersGroup")
      .getBoundSql(Map.of("id",1L,"roleName","admin")).getSql();
  assertFalse(group.contains("#"),"group SQL must not contain a MySQL-only comment");
 }
 @Test void mysqlRetainsItsDateAndPaginationContracts() throws Exception {
  SqlSessionFactory f=factory(new DriverManagerDataSource("jdbc:h2:mem:mysqlmapper","sa",""),"mysql");
  SysUser u=new SysUser();u.getParams().put("beginTime","2026-11-01");
  assertTrue(f.getConfiguration().getMappedStatement("com.ruoyi.system.mapper.SysUserMapper.selectUserList").getBoundSql(u).getSql().contains("date_format"));
  assertTrue(f.getConfiguration().getMappedStatement("com.ruoyi.system.mapper.SysUserMapper.checkUserNameUnique").getBoundSql("test").getSql().toLowerCase(Locale.ROOT).contains("limit 1"));
 }
 @Test void unsupportedGeneratorFailsBeforeAnyDatabaseOperation() {
  GeneratorDatabaseGuard g=new GeneratorDatabaseGuard();org.springframework.test.util.ReflectionTestUtils.setField(g,"product","dm8");
  assertThrows(com.ruoyi.common.exception.ServiceException.class,g::requireSupportedDatabase);
 }
}
