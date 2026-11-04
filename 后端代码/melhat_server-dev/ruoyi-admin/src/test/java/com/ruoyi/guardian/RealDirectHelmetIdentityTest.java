package com.ruoyi.guardian;

import com.alibaba.fastjson2.*;
import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.extension.spring.MybatisSqlSessionFactoryBean;
import com.ruoyi.common.database.DatabaseDialect;
import com.ruoyi.database.SchemaLifecycle;
import com.ruoyi.helmet.mapper.*;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.melhat.direct.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.mybatis.spring.SqlSessionTemplate;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.*;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Real MyBatis + vendor SQL + durable receipt + Guardian projection. Only the pause gate is controlled. */
@EnabledIfEnvironmentVariable(named="LOCATION_CONNECTION_FILE",matches=".+")
class RealDirectHelmetIdentityTest {
    SingleConnectionDataSource source;
    JdbcTemplate jdbc;
    WearableBusinessStore business;
    JSONObject original;
    WearableReportDelivery delivery;
    WearableMaintenance pause;
    GuardianStore guardian;
    SafetyHatInfoMapper hats;
    String device;
    DatabaseDialect dialect;
    boolean failAfterSql;

    @BeforeEach void setup() throws Exception {
        JSONObject config=JSON.parseObject(Files.readString(Paths.get(System.getenv("LOCATION_CONNECTION_FILE"))));
        assertTrue(Arrays.asList("WEARABLE_TEST","wearable_test").contains(config.getString("username")),"Dedicated test schema only");
        assertTrue(config.getString("jdbcUrl").contains(config.getString("username").equals("WEARABLE_TEST")?":15237":":15306"),"Dedicated test port only");
        source=new SingleConnectionDataSource(config.getString("jdbcUrl"),config.getString("username"),config.getString("password"),true);
        jdbc=new JdbcTemplate(source);dialect=DatabaseDialect.of(jdbc);
        SchemaLifecycle.configure(source,dialect.name(),"validate");new SchemaLifecycle(jdbc).validate(SchemaLifecycle.all(dialect));
        business=WearableBusinessStore.existing(jdbc,"");original=business.read("guardian").state;
        MybatisConfiguration configuration=new MybatisConfiguration();configuration.setMapUnderscoreToCamelCase(true);
        for(Class<?> mapper:Arrays.asList(SafetyHatInfoMapper.class,SafetyHatLocationRecordMapper.class,RealTimeAlarmMapper.class,SosAlarmRecordMapper.class))configuration.addMapper(mapper);
        MybatisSqlSessionFactoryBean factory=new MybatisSqlSessionFactoryBean();factory.setDataSource(source);factory.setConfiguration(configuration);
        SqlSessionTemplate session=new SqlSessionTemplate(factory.getObject());hats=session.getMapper(SafetyHatInfoMapper.class);
        GuardianHatArchive archive=new GuardianHatArchive(hats);device="identity-"+UUID.randomUUID();archive.ensureDirectUnassigned(device);
        JSONObject state=copy(original);
        rows(state,"devices").add(object("id",device,"type","H","source","DIRECT_HELMET","active",true,"online",true,"siteId","site-1","station","identity-test","name",device));
        business.save("guardian",business.read("guardian").revision,state,null);
        guardian=new GuardianStore(archive,business);GuardianIngest ingest=new GuardianIngest(guardian);
        DirectHelmetPersistence persistence=new DirectHelmetPersistence(hats,session.getMapper(SafetyHatLocationRecordMapper.class),session.getMapper(RealTimeAlarmMapper.class),session.getMapper(SosAlarmRecordMapper.class)) {
            @Override public JSONObject receive(SafetyHatInfo hat,DirectHelmetMessage message,JSONObject context) {
                JSONObject result=super.receive(hat,message,context);
                if(failAfterSql) {failAfterSql=false;throw new IllegalStateException("fixture-after-business-sql");}
                return result;
            }
        };
        HelmetBusinessJournal journal=new HelmetBusinessJournal(jdbc);ReflectionTestUtils.setField(persistence,"journal",journal);
        DirectHelmetTelemetryService telemetry=new DirectHelmetTelemetryService(hats,persistence,ingest);ReflectionTestUtils.setField(telemetry,"journal",journal);
        DefaultListableBeanFactory beans=new DefaultListableBeanFactory();beans.registerSingleton("telemetry",telemetry);
        delivery=new WearableReportDelivery(business,ingest,beans.getBeanProvider(DirectHelmetTelemetryService.class),beans.getBeanProvider(DirectBeltTelemetryService.class));
        pause=mock(WearableMaintenance.class);when(pause.paused()).thenReturn(true);ReflectionTestUtils.setField(delivery,"maintenance",pause);
    }
    @AfterEach void restore() {
        try {if(original!=null)business.save("guardian",business.read("guardian").revision,original,null);}
        finally {if(source!=null)source.destroy();}
    }
    @Test void locationReceiptCommitsLegacyPointJournalProjectionAndMarkerOnce() throws Exception { verifyReport("ca_report_location","safety_hat_location_record"); }
    @Test void alarmReceiptCommitsGeneratedIdAndEventLinkOnce() throws Exception { verifyReport("ca_sos","real_time_alarm"); }
    @Test void sipSosReceiptCommitsGeneratedIdAndEventLinkOnce() throws Exception { verifyReport("ca_sip_sos","sos_alarm_record"); }

    @Test void lateSqlFailureRetriesTheSameDurableReceiptWithoutDuplicates() throws Exception {
        failAfterSql=true;verifyReport("ca_report_location","safety_hat_location_record");
    }
    @Test void recoverRetainedVendorFailureReceiptsWithoutDeletingThem() {
        List<JSONObject> pending=jdbc.query("SELECT receipt_id,device_id,body FROM wearable_device_report WHERE protocol='direct-helmet' AND processed_at IS NULL AND device_id LIKE 'identity-%'",
                (rs,n)->object("receiptId",rs.getString(1),"protocol","direct-helmet","deviceId",rs.getString(2),"payload",JSON.parseObject(rs.getString(3))));
        for(JSONObject report:pending) {
            String oldDevice=report.getString("deviceId");
            JSONObject captured=report.getJSONObject("payload").getJSONObject("context").getJSONObject("device");
            guardian.update(state->{if(find(state,"devices",oldDevice)==null)rows(state,"devices").add(copy(captured));return true;});
            when(pause.paused()).thenReturn(false);
            String act=report.getJSONObject("payload").getJSONObject("raw").getString("act");
            String table="ca_report_location".equals(act)?"safety_hat_location_record":"ca_sos".equals(act)?"real_time_alarm":"sos_alarm_record";
            assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE hat_number=?",Integer.class,oldDevice));
            delivery.deliver(report);delivery.deliver(report);
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE hat_number=?",Integer.class,oldDevice));
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=? AND processed_at IS NOT NULL",Integer.class,report.getString("receiptId")));
            if("ca_report_location".equals(act))assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_location_fix WHERE device_id=?",Integer.class,oldDevice));
            else assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_event_link WHERE device_id=? AND projected=1",Integer.class,oldDevice));
            System.out.println("IDENTITY_PREVIOUS_VENDOR_FAILURE_RECOVERED database="+dialect+" table="+table+" receipt="+report.getString("receiptId")+" pid="+ProcessHandle.current().pid()+" processed=true replayRows=1");
        }
        System.out.println("IDENTITY_PREVIOUS_PENDING_COUNT database="+dialect+" recovered="+pending.size());
    }

    void verifyReport(String act,String table) throws Exception {
        String raw=object("act",act,"device_id",device,"x_point","35.466123","y_point","112.574204","gps","1","bat_l",73,"type","identity-test").toJSONString();
        assertFalse(delivery.helmet(device,raw),"Paused: report persisted, processing not completed");
        JSONObject report=jdbc.queryForObject("SELECT receipt_id,body FROM wearable_device_report WHERE device_id=?",(rs,n)->object("receiptId",rs.getString(1),"protocol","direct-helmet","deviceId",device,"payload",JSON.parseObject(rs.getString(2))),device);
        String receipt=report.getString("receiptId");
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=? AND processed_at IS NULL",Integer.class,receipt));
        assertEquals(0,count(table));
        when(pause.paused()).thenReturn(false);
        if(failAfterSql) {
            IllegalStateException injected=assertThrows(IllegalStateException.class,()->delivery.deliver(report));
            assertEquals("fixture-after-business-sql",injected.getMessage());
            assertEquals(0,count(table));
            assertEquals(0,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_location_fix WHERE device_id=?",Integer.class,device));
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=? AND processed_at IS NULL",Integer.class,receipt));
            System.out.println("IDENTITY_SQL_ROLLBACK_PENDING database="+dialect+" receipt="+receipt+" sameReceiptWillRecover=true");
        }
        try {delivery.deliver(report);}
        catch(RuntimeException failure) {
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=? AND processed_at IS NULL",Integer.class,receipt),"Failure must retain durable pending receipt");
            assertEquals(0,count(table),"Business insert must roll back");
            for(Throwable cause=failure;cause!=null;cause=cause.getCause())if(cause instanceof java.sql.SQLException) {
                java.sql.SQLException sql=(java.sql.SQLException)cause;
                System.out.println("IDENTITY_VENDOR_ERROR table="+table+" code="+sql.getErrorCode()+" state="+sql.getSQLState()+" message="+sql.getMessage());break;
            }
            throw failure;
        }
        assertEquals(1,count(table));
        Long generated=jdbc.queryForObject("SELECT id FROM "+table+" WHERE hat_number=?",Long.class,device);assertNotNull(generated);assertTrue(generated>0);
        assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM wearable_device_report WHERE receipt_id=? AND processed_at IS NOT NULL",Integer.class,receipt));
        JSONObject state=business.read("guardian").state;
        if("ca_report_location".equals(act)) {
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_location_fix WHERE device_id=?",Integer.class,device));
            assertTrue(rows(state,"locations").stream().anyMatch(v->device.equals(((JSONObject)v).getString("deviceId"))));
            assertEquals("112.574204",jdbc.queryForObject("SELECT lng FROM "+table+" WHERE id=?",String.class,generated));
            assertEquals("35.466123",jdbc.queryForObject("SELECT lat FROM "+table+" WHERE id=?",String.class,generated));
        } else {
            assertEquals(generated,jdbc.queryForObject("SELECT source_record_id FROM helmet_event_link WHERE device_id=?",Long.class,device));
            assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM helmet_event_link WHERE device_id=? AND projected=1",Integer.class,device));
            assertTrue(rows(state,"events").stream().anyMatch(v->device.equals(((JSONObject)v).getString("deviceId"))));
        }
        delivery.deliver(report);assertEquals(1,count(table));
        assertEquals(generated,jdbc.queryForObject("SELECT id FROM "+table+" WHERE hat_number=?",Long.class,device));
        System.out.println("IDENTITY_PASS database="+dialect+" table="+table+" generatedId="+generated+" receipt="+receipt+" pid="+ProcessHandle.current().pid()+" persistedThenProcessed=true replayRows=1");
    }
    int count(String table) {return jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE hat_number=?",Integer.class,device);}
}
