package com.ruoyi.wear.event;

import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.domain.WearEventAction;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.event.mapper.WearEventActionMapper;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.mapper.WearPersonMapper;

/** An account-owned SOS enters administrator approval without a field-review stage. */
@Service
public class ManualSosService {
    public static final String SOURCE = "manual_sos";
    @Autowired private SiteAccessService sites;
    @Autowired private WearSafetyEventMapper events;
    @Autowired private WearEventActionMapper actions;
    @Autowired private WearPersonMapper people;
    @Autowired private EventNotifyService notifications;

    public static boolean isManual(WearSafetyEvent event) {
        return SOURCE.equals(event.getSource()) && "sos".equals(event.getEventType());
    }

    @Transactional(rollbackFor = Exception.class, isolation = Isolation.READ_COMMITTED)
    public EventDto submit(String requestId, String location, String description) {
        Long userId = sites.requireLogin().getUserId();
        Long siteId = sites.requireCurrentSiteForWrite();
        sites.assertAuthorized(siteId);
        requestId = required(requestId, 64, "请求标识");
        if (!requestId.matches("[A-Za-z0-9_-]{16,64}")) throw new ServiceException("请求标识无效", 400);
        location = required(location, 200, "报警位置");
        description = required(description, 500, "报警说明");
        String detail = "报警位置：" + location + "\n报警说明：" + description;
        String key = UUID.nameUUIDFromBytes((siteId + ":" + userId + ":" + requestId)
                .getBytes(StandardCharsets.UTF_8)).toString();
        WearSafetyEvent existing = find(key);
        if (existing != null) return replay(existing, detail);
        String actor = SecurityUtils.getUsername();
        Date now = new Date();
        WearSafetyEvent event = new WearSafetyEvent();
        event.setSource(SOURCE); event.setSourceEventId(key);
        event.setReporterUserId(userId); event.setSiteId(siteId);
        event.setEventType("sos"); event.setSeverity(EventSeverityPolicy.EMERGENCY);
        event.setStatus(EventStateMachine.PENDING_REVIEW);
        event.setAlarmCode("manual.sos"); event.setAlarmName("手动 SOS 报警");
        event.setAlarmDescription(detail);
        event.setOccurredAt(now); event.setReceivedAt(now);
        event.setLocationQuality("unknown"); event.setTaskMatch("none");
        event.setRepeatCount(0); event.setEscalated(0); event.setDemo(0); event.setVersion(1);
        event.setRuleVersion("manual-sos-1");
        event.setCreateBy(actor); event.setUpdateBy(actor); event.setCreateTime(now); event.setUpdateTime(now);
        // Personnel/device binding is optional: an authenticated account can still request help.
        event.setPersonName(sites.requireLogin().getUser().getNickName());
        if (event.getPersonName() == null || event.getPersonName().trim().isEmpty()) event.setPersonName(actor);
        List<WearPerson> linked = people.selectList(new LambdaQueryWrapper<WearPerson>()
                .eq(WearPerson::getAccountUserId, userId).eq(WearPerson::getStatus, "0")
                .orderByAsc(WearPerson::getId).last("LIMIT 1"));
        if (!linked.isEmpty()) {
            WearPerson person = linked.get(0);
            event.setPersonId(person.getId()); event.setPersonName(person.getName()); event.setPersonCode(person.getPersonCode());
        }
        try { events.insert(event); }
        catch (DuplicateKeyException race) {
            existing = find(key);
            if (existing == null) throw race;
            return replay(existing, detail);
        }
        WearEventAction action = new WearEventAction();
        action.setEventId(event.getId()); action.setAction("manual_sos"); action.setActor(actor);
        action.setReason(detail); action.setToStatus(EventStateMachine.PENDING_REVIEW); action.setCreateTime(now);
        actions.insert(action);
        notifications.notifyAfterCommit(event);
        return EventViews.toDto(event);
    }

    private WearSafetyEvent find(String key) {
        return events.selectOne(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSource, SOURCE).eq(WearSafetyEvent::getSourceEventId, key));
    }

    private EventDto replay(WearSafetyEvent event, String detail) {
        if (!detail.equals(event.getAlarmDescription())) throw new ServiceException("该请求已提交，请勿修改内容后重复使用", 409);
        return EventViews.toDto(event);
    }

    private String required(String value, int limit, String name) {
        value = value == null ? "" : value.trim();
        if (value.isEmpty() || value.length() > limit) throw new ServiceException(name + "不能为空且不能超过" + limit + "字", 400);
        return value;
    }
}
