package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.direct.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Exercises the production SQL store together with the real assignment/authority predicate. */
class HelmetMediaSqlViewingTest {
    @TempDir Path directory;
    @Test @SuppressWarnings("unchecked") void viewerSurvivesSqlReloadAndScheduledAuthorityCheck() throws Exception {
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE","sa",""));
        String key=Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.UTF_8));
        HelmetMediaStore mediaStore=new HelmetMediaStore(directory.resolve("media.json").toString(),directory.resolve("public").toString(),new WearableBusinessStore(jdbc,key));
        HelmetCloudClient cloud=mock(HelmetCloudClient.class);when(cloud.configured()).thenReturn(true);
        when(cloud.request(eq("POST"),eq("/streams"),any())).thenAnswer(i->object("streamId","stream-a","pushUrl","rtmp://fixture/stream-a","expiresAt",Instant.now().plusSeconds(30).toString()));
        when(cloud.request("GET","/streams/stream-a",null)).thenAnswer(i->object("streamId","stream-a","publishing",false,"statusVerified",true,"hlsUrl","https://fixture/hls","expiresAt",Instant.now().plusSeconds(30).toString()));
        when(cloud.request("GET","/health",null)).thenReturn(object("ready",true,"components",object("tts",true),"devices",new JSONArray()));
        when(cloud.request(eq("GET"),startsWith("/events?"),isNull())).thenReturn(object("events",new JSONArray()));
        DirectHelmetGateway gateway=mock(DirectHelmetGateway.class);when(gateway.isOnline("helmet-a")).thenReturn(true);
        ObjectProvider<DirectHelmetGateway> gateways=mock(ObjectProvider.class);when(gateways.getObject()).thenReturn(gateway);
        HelmetMediaService media=new HelmetMediaService(cloud,mediaStore,new HelmetMediaProperties(),gateways);
        ReflectionTestUtils.setField(media,"healthy",true);
        JSONObject master=object("sites",JSONArray.of(object("id","site-1","enabled",true)),
                "accounts",JSONArray.of(object("id","demo-duty","enabled",true,"roleIds",JSONArray.of("duty"))),
                "roles",JSONArray.of(object("id","duty","enabled",true,"grants",JSONArray.of(object("siteIds",JSONArray.of("site-1"),"operations",JSONArray.of("communications:voice"))))),
                "people",JSONArray.of(object("id","ledger-person","portalId","P1","siteId","site-1","enabled",true)),
                "devices",JSONArray.of(object("id","ledger-helmet","portalDeviceId","helmet-a","source","DIRECT_HELMET","type","HELMET","siteId","site-1","lifecycle","IN_USE")),
                "assignments",JSONArray.of(object("id","assignment-a","personId","ledger-person","deviceId","ledger-helmet","active",true,"version",1)));
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));
        GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));
        PersonEquipmentContext equipment=new PersonEquipmentContext(ledger,access,mock(GuardianStore.class),mock(WearableBusinessPolicy.class));
        ObjectProvider<PersonEquipmentContext> contexts=mock(ObjectProvider.class);when(contexts.getIfAvailable()).thenReturn(equipment);ReflectionTestUtils.setField(media,"equipmentContexts",contexts);
        JSONObject input=object("action","start_video","idempotencyKey","sql-viewer-start-001","viewerSessionId","sql-viewer-001","personId","P1","siteId","site-1","assignmentId","assignment-a","assignmentVersion",1);
        // GET /live carries only current person/assignment context, never server-side site/area fields.
        JSONObject liveInput=object("viewerSessionId","sql-viewer-001","personId","P1","assignmentId","assignment-a","assignmentVersion",1);
        assertEquals("sent",media.command("demo-duty","helmet-a",input).getString("status"));
        assertEquals(1,mediaStore.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").size());
        assertEquals("waiting_media",media.live("demo-duty","helmet-a",liveInput).getString("status"));
        media.reconcile();
        assertEquals(1,mediaStore.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").size());
        assertEquals("waiting_media",media.live("demo-duty","helmet-a",liveInput).getString("status"));
        assertFalse(jdbc.queryForObject("SELECT body FROM wearable_media_stream WHERE record_key='helmet-a'",String.class).contains("sql-viewer-001"));
        verify(gateway,times(1)).sendCommand(eq("helmet-a"),any());
        master.getJSONArray("assignments").getJSONObject(0).put("version",2);media.reconcile();
        assertTrue(mediaStore.snapshot().getJSONObject("streams").getJSONObject("helmet-a").getJSONObject("viewers").isEmpty());
        assertThrows(IllegalArgumentException.class,()->media.live("demo-duty","helmet-a",liveInput));
    }
}
