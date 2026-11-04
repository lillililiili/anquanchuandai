package com.ruoyi.guardian;
import com.alibaba.fastjson2.*;
import com.ruoyi.cluster.*;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.service.PlatformDeviceSyncService;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import static com.ruoyi.guardian.WearableModel.object;
/** Real business services plus MyBatis/Spring transaction integration; only vendor preview is synthetic. */
public final class CoordinationBusinessFixture {
    private final SafetyHatInfoMapper hatMapper;private final WearableBusinessStore business;private final ClusterWorkCoordinator work;private final WearableMaintenance gate;
    private final AdminLedgerStore ledger;private final GuardianStore guardian;private final GuardianHatArchive hats;
    private final AdminDeviceService devices;private final AdminMasterService master;private final AdminAssignmentService assignments;private final AdminMaintenanceService maintenance;private final AdminPlatformService sync;private final PlatformDeviceSyncService platform;private final ExternalDataStore external;
    private JSONObject oldProjection;
    private volatile List<HeadbandVO> incoming=Collections.emptyList();private volatile boolean failSync,slowPreview;
    public CoordinationBusinessFixture(JdbcTemplate jdbc,AdminLedgerStore ledger,WearableBusinessStore business,ClusterWorkCoordinator work,WearableMaintenance gate,ExternalDataStore external)throws Exception {
        this.ledger=ledger;this.external=external;this.business=business;this.work=work;this.gate=gate;
        com.baomidou.mybatisplus.extension.spring.MybatisSqlSessionFactoryBean factory=new com.baomidou.mybatisplus.extension.spring.MybatisSqlSessionFactoryBean();factory.setDataSource(jdbc.getDataSource());
        com.baomidou.mybatisplus.core.MybatisConfiguration configuration=new com.baomidou.mybatisplus.core.MybatisConfiguration();configuration.setMapUnderscoreToCamelCase(true);factory.setConfiguration(configuration);
        configuration.addMapper(SafetyHatInfoMapper.class);
        SafetyHatInfoMapper mapper=new org.mybatis.spring.SqlSessionTemplate(factory.getObject()).getMapper(SafetyHatInfoMapper.class);hatMapper=mapper;hats=new GuardianHatArchive(mapper);
        guardian=new GuardianStore(hats,business);ReflectionTestUtils.setField(guardian,"coordinator",work);ReflectionTestUtils.setField(guardian,"ledger",ledger);ReflectionTestUtils.setField(guardian,"maintenance",gate);
        org.springframework.beans.factory.support.DefaultListableBeanFactory beans=new org.springframework.beans.factory.support.DefaultListableBeanFactory();AdminQueryService query=new AdminQueryService(ledger,guardian,beans.getBeanProvider(AdminMaintenanceService.class));
        devices=new AdminDeviceService(ledger,hats);ReflectionTestUtils.setField(devices,"queries",query);assignments=new AdminAssignmentService(ledger,guardian,query);maintenance=new AdminMaintenanceService(ledger,query,assignments);beans.registerSingleton("maintenance",maintenance);
        master=new AdminMasterService(ledger,guardian,query);ReflectionTestUtils.setField(master,"coordinator",work);
        platform=new PlatformDeviceSyncService(null,mapper){@Override public List<HeadbandVO> preview(){if(slowPreview)CoordinationProcessNode.barrier("platform-preview");return incoming;}@Override public Map<String,Integer> syncRecords(List<HeadbandVO> list,String actor){Map<String,Integer> result=super.syncRecords(list,actor);if(failSync)throw new IllegalStateException("Injected after syncRecords SQL");return result;}};
        sync=new AdminPlatformService(ledger,query,platform);ReflectionTestUtils.setField(sync,"coordinator",work);ReflectionTestUtils.setField(sync,"externalData",external);
    }
    public JSONObject execute(JSONObject input){String type=input.getString("type");JSONObject command=input.getJSONObject("input");String actor=input.getString("actor");if(actor==null)actor="demo-system";
        if("guardianSnapshot".equals(type))return guardian.snapshot();
        if("captureProjection".equals(type)){oldProjection=ledger.read();return object("revision",oldProjection.getLongValue("revision"));}
        if("applyOldProjection".equals(type)){guardian.update(state->{PlatformProjection.apply(state,oldProjection);return true;});return business.read("guardian").state;}
        if("rollbackAll".equals(type))return ledger.mutate(()->{JSONObject state=ledger.read();hats.ensureDirectUnassigned("coord-hat-rollback");external.record("coord-rollback","Fixture","site-1","DEVICE","rollback",object("value",1),"local");platform.syncRecords(Collections.singletonList(headband("coord-sync-rollback")),"fixture");state.getJSONObject("idempotency").put("rollback-all",object("test",true));ledger.write(state);throw new IllegalStateException("Injected after all associated SQL");});
        if("platform.sync".equals(type)){incoming=Collections.singletonList(headband(command.getString("deviceNumber")));failSync=command.getBooleanValue("fail");slowPreview=command.getBooleanValue("hold");try{return sync.sync(actor,"site-1");}catch(RuntimeException e){throw e;}catch(Exception e){throw new IllegalStateException(e);}finally{failSync=false;slowPreview=false;}}
        if(type.startsWith("assignments."))return assignments.execute(actor,type,command);
        if(maintenance.handles(type))return maintenance.execute(actor,type,command);
        if(type.startsWith("devices."))return devices.execute(actor,type,command);
        return master.execute(actor,type,command);
    }
    public JSONObject receive(OwnerToken token,DeviceOwnership ownership) {
        GuardianIngest ingest=new GuardianIngest(guardian);
        org.springframework.beans.factory.support.DefaultListableBeanFactory beans=new org.springframework.beans.factory.support.DefaultListableBeanFactory();
        beans.registerSingleton("telemetry",new com.ruoyi.melhat.direct.DirectHelmetTelemetryService(hatMapper,null,ingest));
        WearableReportDelivery delivery=new WearableReportDelivery(business,ingest,beans.getBeanProvider(com.ruoyi.melhat.direct.DirectHelmetTelemetryService.class),beans.getBeanProvider(DirectBeltTelemetryService.class));
        ReflectionTestUtils.setField(delivery,"ownership",ownership);ReflectionTestUtils.setField(delivery,"coordinator",work);ReflectionTestUtils.setField(delivery,"maintenance",gate);
        boolean active=delivery.helmetOwned(token,object("act","ca_report_location","device_id",token.deviceId).toJSONString(),new JSONObject(),false);
        return object("received",true,"active",active);
    }
    private static HeadbandVO headband(String number){HeadbandVO row=new HeadbandVO();row.setHelmetSn(number);row.setOnline("1");return row;}
}
