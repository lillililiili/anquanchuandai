package com.ruoyi.wear.event;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.text.ParseException;
import java.text.SimpleDateFormat;
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
            String severity, String updatedAfter, String claimantUserId, String escalated,
            String personKeyword, String sn, String taskId, String occurredFrom, String occurredTo)
    {
        return page(current, size, type, status, personId, severity, updatedAfter, claimantUserId,
                escalated, personKeyword, sn, taskId, occurredFrom, occurredTo, null, null);
    }

    public WearPage<EventDto> page(int current, int size, String type, String status, String personId,
            String severity, String updatedAfter, String claimantUserId, String escalated,
            String personKeyword, String sn, String taskId, String occurredFrom, String occurredTo,
            String alarmCode, String deviceTypes)
    {
        return page(current, size, type, status, personId, severity, updatedAfter, claimantUserId,
                escalated, personKeyword, sn, taskId, occurredFrom, occurredTo, alarmCode, deviceTypes,
                null, null, null);
    }

    public WearPage<EventDto> page(int current, int size, String type, String status, String personId,
            String severity, String updatedAfter, String claimantUserId, String escalated,
            String personKeyword, String sn, String taskId, String occurredFrom, String occurredTo,
            String alarmCode, String deviceTypes, String statuses, String types, String alarmCodes)
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
        List<String> selectedStatuses = splitChoices(statuses, java.util.Arrays.asList("open", "claimed", "handling", "pending_review", "closed"));
        List<String> selectedTypes = splitChoices(types, java.util.Arrays.asList("sos", "fall", "impact", "geofence", "realtime"));
        List<String> selectedCodes = splitChoices(alarmCodes, null);
        if (!selectedTypes.isEmpty() || !selectedCodes.isEmpty())
        {
            // Coarse workflow types and specific alarm codes belong to one OR group.
            query.and(group -> {
                if (!selectedTypes.isEmpty()) group.in(WearSafetyEvent::getEventType, selectedTypes);
                if (!selectedCodes.isEmpty())
                {
                    if (!selectedTypes.isEmpty()) group.or();
                    group.in(WearSafetyEvent::getAlarmCode, selectedCodes);
                }
            });
        }
        else if (StringUtils.isNotEmpty(alarmCode))
        {
            query.eq(WearSafetyEvent::getAlarmCode, alarmCode.trim());
        }
        applyDeviceTypes(query, deviceTypes);
        if (selectedTypes.isEmpty() && selectedCodes.isEmpty() && StringUtils.isNotEmpty(type))
        {
            query.eq(WearSafetyEvent::getEventType, type);
        }
        if (!selectedStatuses.isEmpty())
        {
            query.in(WearSafetyEvent::getStatus, selectedStatuses);
        }
        else if (StringUtils.isNotEmpty(status) && !"all".equals(status))
        {
            query.eq(WearSafetyEvent::getStatus, status);
        }
        else if (!"all".equals(status))
        {
            query.ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED);
        }
        if (StringUtils.isNotEmpty(personId))
        {
            query.eq(WearSafetyEvent::getPersonId, Long.valueOf(personId));
        }
        if (StringUtils.isNotEmpty(personKeyword))
        {
            query.and(item -> item.like(WearSafetyEvent::getPersonName, personKeyword.trim())
                    .or().like(WearSafetyEvent::getPersonCode, personKeyword.trim()));
        }
        if (StringUtils.isNotEmpty(sn))
        {
            query.like(WearSafetyEvent::getSn, sn.trim());
        }
        if (StringUtils.isNotEmpty(taskId))
        {
            query.eq(WearSafetyEvent::getTaskId, parseId(taskId, "任务ID"));
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
        if (StringUtils.isNotEmpty(occurredFrom))
        {
            query.ge(WearSafetyEvent::getOccurredAt, parseDay(occurredFrom, false));
        }
        if (StringUtils.isNotEmpty(occurredTo))
        {
            query.le(WearSafetyEvent::getOccurredAt, parseDay(occurredTo, true));
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

    /** Choices come from event snapshots in the caller's authorized site scope. */
    public List<Map<String, String>> filterOptions()
    {
        siteAccessService.requireLogin();
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty()) return Collections.emptyList();
        List<WearSafetyEvent> rows = eventMapper.selectList(new LambdaQueryWrapper<WearSafetyEvent>()
                .select(WearSafetyEvent::getAlarmCode, WearSafetyEvent::getAlarmName)
                .in(WearSafetyEvent::getSiteId, scope)
                .isNotNull(WearSafetyEvent::getAlarmCode).ne(WearSafetyEvent::getAlarmCode, "")
                .groupBy(WearSafetyEvent::getAlarmCode, WearSafetyEvent::getAlarmName)
                .orderByAsc(WearSafetyEvent::getAlarmCode, WearSafetyEvent::getAlarmName));
        Map<String, String> labels = new java.util.LinkedHashMap<>();
        for (WearSafetyEvent row : rows)
        {
            String name = row.getAlarmName();
            if (!labels.containsKey(row.getAlarmCode()) || StringUtils.isNotEmpty(name))
                labels.put(row.getAlarmCode(), StringUtils.isEmpty(name) ? row.getAlarmCode() : name);
        }
        List<Map<String, String>> result = new ArrayList<>();
        labels.forEach((code, label) -> {
            Map<String, String> option = new HashMap<>();
            option.put("code", code);
            option.put("label", label);
            result.add(option);
        });
        return result;
    }

    static void applyDeviceTypes(LambdaQueryWrapper<WearSafetyEvent> query, String raw)
    {
        if (StringUtils.isEmpty(raw)) return;
        java.util.Set<String> types = new java.util.LinkedHashSet<>();
        for (String item : raw.split(",", -1))
        {
            String type = item.trim();
            if (!java.util.Arrays.asList("helmet", "belt", "watch").contains(type))
                throw new ServiceException("触发设备类型无效", HttpStatus.BAD_REQUEST);
            types.add(type);
        }
        // Fixed query shape and bound values; no client text is interpolated into SQL.
        query.and(group -> {
            for (String type : types)
                group.or().apply("device_id IN (SELECT d.id FROM wear_device d "
                        + "JOIN wear_product_model m ON m.id = d.model_id WHERE m.type_code = {0})", type);
        });
    }

    private static List<String> splitChoices(String raw, List<String> allowed)
    {
        if (StringUtils.isEmpty(raw)) return Collections.emptyList();
        java.util.Set<String> result = new java.util.LinkedHashSet<>();
        for (String item : raw.split(",", -1))
        {
            String value = item.trim();
            if (value.isEmpty() || value.length() > 100 || (allowed != null && !allowed.contains(value)))
                throw new ServiceException("筛选条件无效", HttpStatus.BAD_REQUEST);
            result.add(value);
        }
        if (result.size() > 100) throw new ServiceException("筛选项过多", HttpStatus.BAD_REQUEST);
        return new ArrayList<>(result);
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

    private Long parseId(String raw, String label)
    {
        try { return Long.valueOf(raw.trim()); }
        catch (NumberFormatException ex) { throw new ServiceException(label + "格式无效", HttpStatus.BAD_REQUEST); }
    }

    private Date parseDay(String raw, boolean endOfDay)
    {
        try
        {
            Date parsed = new SimpleDateFormat("yyyy-MM-dd").parse(raw.trim());
            return endOfDay ? new Date(parsed.getTime() + 86399999L) : parsed;
        }
        catch (ParseException ex)
        {
            throw new ServiceException("日期格式无效", HttpStatus.BAD_REQUEST);
        }
    }
}
