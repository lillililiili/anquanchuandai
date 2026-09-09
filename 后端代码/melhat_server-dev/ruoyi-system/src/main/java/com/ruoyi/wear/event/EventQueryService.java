package com.ruoyi.wear.event;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.event.domain.WearEventAction;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventActionDto;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.mapper.WearEventActionMapper;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;

@Service
public class EventQueryService
{
    @Autowired
    private WearSafetyEventMapper eventMapper;
    @Autowired
    private WearEventActionMapper actionMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private EventCommandService commandService;

    public WearPage<EventDto> page(int current, int size, String type, String status, String personId,
            String severity, String updatedAfter, String claimantUserId, String escalated)
    {
        siteAccessService.requireLogin();
        commandService.escalateDue();
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty())
        {
            return WearPage.of(Collections.<EventDto>emptyList(), 0, current, size);
        }
        if (size > 100)
        {
            size = 100;
        }
        if (current < 1)
        {
            current = 1;
        }
        LambdaQueryWrapper<WearSafetyEvent> query = new LambdaQueryWrapper<WearSafetyEvent>()
                .in(WearSafetyEvent::getSiteId, scope);
        if (StringUtils.isNotEmpty(type))
        {
            query.eq(WearSafetyEvent::getEventType, type);
        }
        if (StringUtils.isNotEmpty(status))
        {
            query.eq(WearSafetyEvent::getStatus, status);
        }
        else
        {
            query.ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED);
        }
        if (StringUtils.isNotEmpty(personId))
        {
            query.eq(WearSafetyEvent::getPersonId, Long.valueOf(personId));
        }
        if (StringUtils.isNotEmpty(severity))
        {
            query.eq(WearSafetyEvent::getSeverity, severity);
        }
        if (StringUtils.isNotEmpty(claimantUserId))
        {
            query.eq(WearSafetyEvent::getClaimantUserId, Long.valueOf(claimantUserId));
        }
        if ("true".equalsIgnoreCase(escalated) || "1".equals(escalated))
        {
            query.eq(WearSafetyEvent::getEscalated, 1);
        }
        if (StringUtils.isNotEmpty(updatedAfter))
        {
            query.ge(WearSafetyEvent::getUpdateTime, parseTime(updatedAfter));
        }
        query.orderByDesc(WearSafetyEvent::getOccurredAt).orderByDesc(WearSafetyEvent::getId);
        IPage<WearSafetyEvent> page = eventMapper.selectPage(new Page<WearSafetyEvent>(current, size), query);
        List<EventDto> records = new ArrayList<EventDto>();
        for (WearSafetyEvent row : page.getRecords())
        {
            records.add(EventViews.toDto(row));
        }
        return WearPage.of(records, page.getTotal(), page.getCurrent(), page.getSize());
    }

    public EventDto detail(Long id)
    {
        WearSafetyEvent event = commandService.requireReadable(id);
        event = commandService.escalateIfDue(event);
        return EventViews.toDto(event);
    }

    public List<EventActionDto> actions(Long id)
    {
        commandService.requireReadable(id);
        List<WearEventAction> rows = actionMapper.selectList(new LambdaQueryWrapper<WearEventAction>()
                .eq(WearEventAction::getEventId, id)
                .orderByDesc(WearEventAction::getId));
        List<EventActionDto> list = new ArrayList<EventActionDto>();
        for (WearEventAction row : rows)
        {
            list.add(EventViews.toAction(row));
        }
        return list;
    }

    public Map<String, Object> inboxCount()
    {
        siteAccessService.requireLogin();
        commandService.escalateDue();
        List<Long> scope = siteAccessService.listScopeSiteIds();
        Map<String, Object> data = new HashMap<String, Object>();
        if (scope.isEmpty())
        {
            data.put("count", 0);
            return data;
        }
        Integer count = eventMapper.selectCount(new LambdaQueryWrapper<WearSafetyEvent>()
                .in(WearSafetyEvent::getSiteId, scope)
                .ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED));
        data.put("count", count == null ? 0 : count.intValue());
        return data;
    }

    private Date parseTime(String raw)
    {
        try
        {
            return Date.from(OffsetDateTime.parse(raw).toInstant());
        }
        catch (Exception ignored)
        {
        }
        try
        {
            return Date.from(Instant.parse(raw));
        }
        catch (Exception ex)
        {
            throw new ServiceException("updatedAfter 格式无效", HttpStatus.BAD_REQUEST);
        }
    }
}
