package com.ruoyi.wear.event;

import com.ruoyi.wear.event.domain.WearEventAction;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventActionDto;
import com.ruoyi.wear.event.dto.EventDto;

public final class EventViews
{
    private EventViews()
    {
    }

    public static EventDto toDto(WearSafetyEvent row)
    {
        if (row == null)
        {
            return null;
        }
        EventDto dto = new EventDto();
        dto.setId(str(row.getId()));
        dto.setType(row.getEventType());
        dto.setSeverity(row.getSeverity());
        dto.setStatus(row.getStatus());
        dto.setOccurredAt(row.getOccurredAt());
        dto.setReceivedAt(row.getReceivedAt());
        dto.setPersonId(str(row.getPersonId()));
        dto.setPersonCode(row.getPersonCode());
        dto.setPersonName(row.getPersonName());
        dto.setDeviceId(str(row.getDeviceId()));
        dto.setSn(row.getSn());
        dto.setSiteId(str(row.getSiteId()));
        dto.setLocationLat(row.getLocationLat());
        dto.setLocationLng(row.getLocationLng());
        dto.setLocationQuality(row.getLocationQuality());
        dto.setClaimantUserId(str(row.getClaimantUserId()));
        dto.setRepeatCount(row.getRepeatCount() == null ? 0 : row.getRepeatCount());
        dto.setEscalated(row.getEscalated() != null && row.getEscalated().intValue() == 1);
        dto.setDemo(row.getDemo() != null && row.getDemo().intValue() == 1);
        dto.setSource(row.getSource());
        dto.setSourceEventId(row.getSourceEventId());
        dto.setRuleVersion(row.getRuleVersion());
        dto.setTaskId(str(row.getTaskId()));
        dto.setTaskMatch(row.getTaskMatch() == null ? "none" : row.getTaskMatch());
        dto.setFenceId(str(row.getFenceId()));
        dto.setFenceAction(row.getFenceAction());
        dto.setVersion(row.getVersion());
        return dto;
    }

    public static EventActionDto toAction(WearEventAction row)
    {
        EventActionDto dto = new EventActionDto();
        dto.setId(str(row.getId()));
        dto.setEventId(str(row.getEventId()));
        dto.setAction(row.getAction());
        dto.setActor(row.getActor());
        dto.setReason(row.getReason());
        dto.setFromStatus(row.getFromStatus());
        dto.setToStatus(row.getToStatus());
        dto.setCreateTime(row.getCreateTime());
        return dto;
    }

    public static String str(Long id)
    {
        return id == null ? null : String.valueOf(id);
    }
}
