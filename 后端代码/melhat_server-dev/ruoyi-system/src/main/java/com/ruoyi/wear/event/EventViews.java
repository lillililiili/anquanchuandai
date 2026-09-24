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
        dto.setReminderOnly(EventReminderPolicy.isReminder(row));
        dto.setType(row.getEventType());
        dto.setDeviceType(row.getDeviceType());
        dto.setAlarmCode(row.getAlarmCode());
        String name = row.getAlarmName();
        if ("sos".equals(row.getEventType()) && (name == null || name.trim().isEmpty()
                || "告警名称未提供".equals(name.trim()))) name = "SOS 求助";
        dto.setAlarmName(name);
        dto.setAlarmDescription(row.getAlarmDescription());
        dto.setSeverity(EventSeverityPolicy.effectiveSeverity(row));
        dto.setStatus(row.getStatus());
        boolean legacy = EventStateMachine.CLOSED.equals(row.getStatus());
        boolean verified = EventStateMachine.VERIFIED.equals(row.getStatus());
        boolean awaitingReview = EventStateMachine.PENDING_REVIEW.equals(row.getStatus());
        boolean warning = EventReminderPolicy.isReminder(row);
        dto.setFieldReportStatus(legacy ? "unknown" : warning || ManualSosService.isManual(row)
                ? "not_required" : verified || awaitingReview ? "submitted" : "pending");
        dto.setVerificationStatus(legacy ? "unknown" : warning ? "not_required" : verified ? "verified" : "pending");
        dto.setReviewStatus(legacy ? "unknown" : !EventSeverityPolicy.isEmergency(row) ? "not_required"
                : verified ? "approved" : awaitingReview ? "pending" : "not_submitted");
        dto.setOccurredAt(row.getOccurredAt());
        dto.setReceivedAt(row.getReceivedAt());
        dto.setPersonId(str(row.getPersonId()));
        dto.setReporterUserId(str(row.getReporterUserId()));
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
