package com.ruoyi.wear.event;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import com.alibaba.fastjson2.JSON;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.system.websocket.WebSocketSever;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;

@Service
public class EventNotifyService
{
    @Autowired private EventAccessService eventAccess;
    @Autowired
    private WearSiteAccountMapper siteAccountMapper;

    public void notifyAfterCommit(final WearSafetyEvent event)
    {
        if (event == null || event.getSiteId() == null || event.getId() == null)
        {
            return;
        }
        Runnable send = new Runnable()
        {
            @Override
            public void run()
            {
                sendNow(event);
            }
        };
        if (TransactionSynchronizationManager.isSynchronizationActive())
        {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization()
            {
                @Override
                public void afterCommit()
                {
                    send.run();
                }
            });
        }
        else
        {
            send.run();
        }
    }

    private void sendNow(WearSafetyEvent event)
    {
        Map<String, Object> payload = new LinkedHashMap<String, Object>();
        payload.put("type", "wear.event");
        payload.put("eventId", String.valueOf(event.getId()));
        payload.put("siteId", String.valueOf(event.getSiteId()));
        payload.put("severity", EventSeverityPolicy.effectiveSeverity(event));
        payload.put("demo", event.getDemo() != null && event.getDemo().intValue() == 1);
        String json = JSON.toJSONString(payload);
        for (Long userId : eventAccess.recipients(event))
        {
            String uid = String.valueOf(userId);
            WebSocketSever.sendMessageByUser(uid + "_1", json);
            WebSocketSever.sendMessageByUser(uid + "_2", json);
        }
    }
}
