package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;
import java.nio.file.Path;
import static com.ruoyi.guardian.WearableModel.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GuardianBusinessCommandsTest {
    @TempDir Path directory;GuardianStore store;GuardianBusinessCommands service;JSONObject actor=object("id","demo-system");
    @BeforeEach void setup(){JSONObject master=object("sites",JSONArray.of(object("id","site-1","portalStation","S1","enabled",true)),"people",JSONArray.of(object("id","person-1","portalId","P1","name","现场人员","siteId","site-1","enabled",true)),"accounts",JSONArray.of(object("id","demo-system","enabled",true,"name","管理员")),"roles",new JSONArray());
        AdminLedgerStore ledger=mock(AdminLedgerStore.class);when(ledger.read()).thenAnswer(i->copy(master));GuardianAccess access=new GuardianAccess(ledger,mock(AdminQueryService.class));store=new GuardianStore(mock(GuardianHatArchive.class));ReflectionTestUtils.setField(store,"file",directory.resolve("state.json"));
        JSONObject state=object("version",1,"seq",0,"stations",JSONArray.of(object("id","S1","name","测试厂区")),"people",JSONArray.of(object("id","P1","station","S1","siteId","site-1","name","现场人员","active",true)));
        for(String key:new String[]{"devices","works","events","media","fences","groups","bindings","calls","broadcasts","locations","vitals","audit"})state.put(key,new JSONArray());store.replace(state);service=new GuardianBusinessCommands(store,access);
    }
    JSONObject command(String type,JSONObject payload,String operation){return object("type",type,"payload",payload,"operationId",operation,"expectedSeq",store.snapshot().getIntValue("seq"));}
    @Test void groupWriteIsScopedIdempotentAndRejectsForgedTelemetry(){JSONObject request=command("groups.save",object("name","值守组","station","S1","members",JSONArray.of("P1")),"group-create-0001");JSONObject created=service.execute(actor,request);assertEquals(created.getJSONObject("result").getString("id"),service.execute(actor,request).getJSONObject("result").getString("id"));assertEquals(1,rows(store.snapshot(),"groups").size());assertEquals(400,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,command("devices.update",object("online",true),"forged-state-001"))).code);}
    @Test void fenceRequiresGeographicCoordinatesAndCannotCrossSite(){JSONObject bad=object("name","围栏","station","S1","members",JSONArray.of("P1"),"points",JSONArray.parseArray("[[1,1],[2,1],[1,2]]"),"coordinateSystem","PERCENT");assertEquals(400,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,command("fences.save",object("fields",bad),"fence-create-001"))).code);
        bad.put("coordinateSystem","WGS84");bad.put("points",JSONArray.parseArray("[[117.08,36.65],[117.09,36.65],[117.08,36.66]]"));JSONObject created=service.execute(actor,command("fences.save",object("fields",bad),"fence-create-002"));assertNotNull(created.getJSONObject("result").getString("id"));
        bad.put("station","S2");assertEquals(403,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,command("fences.save",object("fields",bad),"fence-create-003"))).code);}
    @Test void staleWriteDoesNotOverwriteAnotherEdit(){JSONObject request=command("groups.save",object("name","第一组","station","S1","members",JSONArray.of("P1")),"group-create-0001");service.execute(actor,request);request.put("operationId","group-create-0002");assertEquals(409,assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,request)).code);assertEquals(1,rows(store.snapshot(),"groups").size());}
    @Test void legacyFenceCanBeDisabledButNotReenabledWithoutRedrawing(){
        store.update(state->{rows(state,"fences").add(object("id","F-legacy","name","历史示意围栏","station","S1","coordinateSystem","PERCENT","points",JSONArray.parseArray("[[10,10],[20,10],[10,20]]"),"members",new JSONArray(),"enabled",true));return true;});
        service.execute(actor,command("fences.toggle",object("id","F-legacy","enabled",false),"legacy-disable-01"));
        AdminQueryService.QueryFailed error=assertThrows(AdminQueryService.QueryFailed.class,()->service.execute(actor,command("fences.toggle",object("id","F-legacy","enabled",true),"legacy-enable-001")));
        assertEquals(409,error.code);assertFalse(find(store.snapshot(),"fences","F-legacy").getBooleanValue("enabled"));
    }
}
