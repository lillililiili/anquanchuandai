package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@org.springframework.scheduling.annotation.EnableScheduling
public class PlatformStatusPoller {
    private final AdminLedgerStore ledger;private final AdminPlatformService platform;
    public PlatformStatusPoller(AdminLedgerStore ledger,AdminPlatformService platform){this.ledger=ledger;this.platform=platform;}
    @Scheduled(initialDelay=120000,fixedDelay=120000)
    public void refresh() {
        JSONObject state=ledger.read();if(state==null)return;
        JSONObject sources=state.getJSONObject("platformSync");if(sources==null)return;
        for(String site:sources.keySet())try { synchronized(ledger) { platform.sync("demo-system",site,true); } }
        catch(Exception error) { org.slf4j.LoggerFactory.getLogger(getClass()).warn("厂站 {} 厂家状态刷新失败，保留上次结果",site); }
    }
}
