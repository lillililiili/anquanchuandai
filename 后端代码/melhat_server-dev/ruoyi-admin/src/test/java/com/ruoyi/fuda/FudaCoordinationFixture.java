package com.ruoyi.fuda;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.cluster.*;
import com.ruoyi.guardian.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import java.time.Clock;
import java.util.*;
/** Uses production dispatcher/capture/sender against real SQL and a loopback external receiver. */
public final class FudaCoordinationFixture {
    public static JSONObject run(JdbcTemplate jdbc,ClusterDatabase db,ClusterIdentity identity,ClusterWorkCoordinator work,WearableMaintenance maintenance,JSONObject input){
        FudaPushProperties properties=new FudaPushProperties();properties.setEnabled(true);properties.setDestinationId("coordination");properties.setAppId("coord-fixture");properties.setSecretBase64(Base64.getEncoder().encodeToString(new byte[32]));properties.setAllowLoopbackHttp(true);properties.setEndpoint(input.getString("url")+"/fuda");properties.setBatchSize(1);properties.setMinSendIntervalMillis(0);properties.setAllowedLedgerDeviceIds(Collections.singleton(input.getString("ledgerId")));
        FudaPushOutbox box=new FudaPushOutbox(jdbc){boolean held;@Override public Delivery claim(String destination,long now,long lease){Delivery row=super.claim(destination,now,lease);if(row!=null&&input.getBooleanValue("hold")&&!held){held=true;CoordinationProcessNode.barrier("push-before-send");}return row;}};
        db.locked(()->{box.enqueue("coordination",input.getString("ledgerId"),"HELMET","coord-hat-A",FudaMapping.object("eventId","coord-push","eventType","STATUS","data",FudaMapping.object("deviceId","coord-hat-A")),db.now());return null;});
        Clock clock=Clock.systemUTC();FudaPushCapture capture=new FudaPushCapture(jdbc,box,properties,new FudaProperties(),new com.ruoyi.melhat.direct.DirectHelmetProperties(),new com.ruoyi.melhat.belt.DirectBeltProperties(),clock);
        org.springframework.beans.factory.support.DefaultListableBeanFactory beans=new org.springframework.beans.factory.support.DefaultListableBeanFactory();
        FudaPushDispatcher dispatcher=new FudaPushDispatcher(box,capture,new FudaPushHttpSender(properties,clock),properties,clock,beans.getBeanProvider(GuardianStore.class));
        ReflectionTestUtils.setField(dispatcher,"coordinator",work);ReflectionTestUtils.setField(dispatcher,"maintenance",maintenance);ReflectionTestUtils.setField(dispatcher,"clusterDb",db);ReflectionTestUtils.setField(dispatcher,"clusterIdentity",identity);
        try{return FudaMapping.object("completed",dispatcher.drain());}finally{dispatcher.close();}
    }
}
