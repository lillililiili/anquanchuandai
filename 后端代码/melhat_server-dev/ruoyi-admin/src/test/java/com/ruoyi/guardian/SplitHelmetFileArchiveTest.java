package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.melhat.split.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.UUID;
import static com.ruoyi.guardian.WearableModel.object;
import static org.junit.jupiter.api.Assertions.*;

class SplitHelmetFileArchiveTest {
    @Test void historicalFilesOutliveCommandWindowAndRestartWithoutExposingOrigins(){
        JdbcTemplate jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        SplitHelmetProperties config=new SplitHelmetProperties();config.setEnabled(true);
        SplitHelmetStore store=new SplitHelmetStore(jdbc,config);
        JSONObject file=object("id","abc","siteId","old-site","areaId","old-area","personId","old-person","createdAt","2026-11-01T10:00:00Z","available",true,"url","/api/guardian/v1/split/devices/SN1/files/abc");
        store.saveFile("SN1",file,"SN1/20261101/cap_abc.jpg","https://files.example/media/SN1/20261101/cap_abc.jpg");
        for(int i=0;i<110;i++)store.commandIntent(object("id","cmd-"+i,"actorId","actor","deviceId","SN1","requestKey","req-"+i,"fingerprint","fp-"+i,"createdMillis",i));
        assertEquals(100,store.commands("SN1").size());assertEquals(1,store.files("SN1").size());
        SplitHelmetStore restarted=new SplitHelmetStore(jdbc,config);JSONObject restored=restarted.file("SN1","abc");
        assertEquals("old-site",restored.getString("siteId"));assertEquals("old-person",restored.getString("personId"));assertEquals("SN1/20261101/cap_abc.jpg",restored.getString("privateFileKey"));assertTrue(restored.getLongValue("privateRefreshedAt")>0);
        assertFalse(restarted.files("SN1").get(0).containsKey("privateSourceUrl"));assertFalse(restarted.files("SN1").get(0).toJSONString().contains("https://files.example"));assertNull(restarted.file("OTHER","abc"));
    }
}
