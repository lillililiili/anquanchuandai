package com.ruoyi.wear.event;

import java.util.Calendar;
import java.util.Date;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.domain.WearEventAction;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.mapper.WearEventActionMapper;
import com.ruoyi.wear.event.mapper.WearEventInboxMapper;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.work.WorkTaskService;
import com.ruoyi.wear.work.WorkTaskStateMachine;
import com.ruoyi.wear.work.domain.WearWorkTask;

@Service
public class EventCommandService
{
    @Autowired
    private WearSafetyEventMapper eventMapper;
    @Autowired
    private WearEventActionMapper actionMapper;
    @Autowired
    private WearEventInboxMapper inboxMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private EventNotifyService notifyService;
    @Autowired
    private WorkTaskService workTaskService;
    @Autowired private EventAccessService eventAccess;
    @Autowired private EventEvidenceService evidence;

    @Transactional(rollbackFor = Exception.class)
    public EventDto assignTask(Long id, String taskIdRaw, Integer version)
    {
        siteAccessService.assertCanEditTask();
        requireVersion(version);
        WearSafetyEvent event = requireReadable(id);
        Long taskId = null;
        String match = WorkTaskStateMachine.MATCH_NONE;
        if (StringUtils.isNotEmpty(taskIdRaw))
        {
            WearWorkTask task;
            try
            {
                task = workTaskService.requireReadable(Long.valueOf(taskIdRaw.trim()));
            }
            catch (NumberFormatException ex)
            {
                throw new ServiceException("任务无效", HttpStatus.BAD_REQUEST);
            }
            if (!task.getSiteId().equals(event.getSiteId()))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            taskId = task.getId();
            match = WorkTaskStateMachine.MATCHED;
        }
        if (eventMapper.assignTask(id, taskId, match, version, SecurityUtils.getUsername()) == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "task", SecurityUtils.getUsername(), match, event.getStatus(), event.getStatus());
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto report(Long id,String comment,Integer version,List<org.springframework.web.multipart.MultipartFile> files) throws java.io.IOException {
        requireVersion(version);
        WearSafetyEvent event=requireReadable(id);
        if(EventReminderPolicy.isReminder(event)) throw new ServiceException("警告请点击收到",400);
        if(!EventStateMachine.canHandle(event.getStatus()) || !version.equals(event.getVersion()))
            throw new ServiceException("事件已更新，请刷新后重试",409);
        comment = requireReportComment(comment);
        if (files == null || files.isEmpty() || files.stream().anyMatch(file -> file == null || file.isEmpty()))
            throw new ServiceException("请添加至少一个有效的现场照片或视频", HttpStatus.BAD_REQUEST);
        evidence.save(event,version,files);
        return handle(id,comment,version);
    }

    public EventDto ack(Long id)
    {
        WearSafetyEvent event = requireReadable(id);
        LoginUser user = siteAccessService.requireLogin();
        inboxMapper.markAcked(user.getUserId(), event.getId());
        insertAction(event.getId(), "ack", SecurityUtils.getUsername(), null, event.getStatus(), event.getStatus());
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto confirm(Long id, Integer version) {
        requireVersion(version);
        WearSafetyEvent event = requireReadable(id);
        if (!EventReminderPolicy.isReminder(event))
            throw new ServiceException("此事件请通过上报流程提交", HttpStatus.FORBIDDEN);
        // Accept legacy pending-review reminders as well, without involving an administrator.
        if (EventStateMachine.isComplete(event.getStatus()) ||
                eventMapper.confirmIfStatus(id, event.getStatus(), version, SecurityUtils.getUsername()) == 0)
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        insertAction(id, "confirm", SecurityUtils.getUsername(), "本人已收到警告", event.getStatus(), EventStateMachine.CONFIRMED);
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto claim(Long id, Integer version)
    {
        throw new ServiceException("异常无需认领，组内成员可直接上报", HttpStatus.FORBIDDEN);
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto handle(Long id, String comment, Integer version)
    {
        requireVersion(version);
        WearSafetyEvent event = requireReadable(id);
        if (EventReminderPolicy.isReminder(event))
            throw new ServiceException("设备提醒请直接确认", HttpStatus.BAD_REQUEST);
        comment = requireReportComment(comment);
        if (!evidence.hasSubmission(id, version))
            throw new ServiceException("请添加至少一个有效的现场照片或视频", HttpStatus.BAD_REQUEST);
        if (!EventStateMachine.canHandle(event.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        String to = EventStateMachine.handleTarget(EventSeverityPolicy.effectiveSeverity(event));
        String actor = SecurityUtils.getUsername();
        int rows = eventMapper.handleIfActive(id, to, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "handle", actor, comment.trim(), event.getStatus(), to);
        WearSafetyEvent latest = eventMapper.selectById(id);
        notifyService.notifyAfterCommit(latest);
        return EventViews.toDto(latest);
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto transfer(Long id, String toUserIdRaw, String reason, Integer version)
    {
        throw new ServiceException("异常由作业组共同处理，无需转交", HttpStatus.FORBIDDEN);
    }

    private String requireReportComment(String comment) {
        if (StringUtils.isBlank(comment))
            throw new ServiceException("请填写异常原因说明", HttpStatus.BAD_REQUEST);
        comment = comment.trim();
        if (comment.length() > 500)
            throw new ServiceException("异常原因不能超过500字", HttpStatus.BAD_REQUEST);
        return comment;
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto close(Long id, String reason, Integer version)
    {
        requireVersion(version);
        if (StringUtils.isEmpty(reason))
        {
            throw new ServiceException("审批意见不能为空", HttpStatus.BAD_REQUEST);
        }
        WearSafetyEvent event = requireReadable(id);
        String actor = SecurityUtils.getUsername();
        siteAccessService.assertCanReviewEvent();
        if (!EventSeverityPolicy.isEmergency(event) || !EventStateMachine.PENDING_REVIEW.equals(event.getStatus()))
            throw new ServiceException("仅可审批已上报的紧急事件", HttpStatus.CONFLICT);
        if (ManualSosService.isManual(event)) {
            if (siteAccessService.requireLogin().getUserId().equals(event.getReporterUserId()))
                throw new ServiceException("报警人与审批人不能是同一账号", 403);
        } else {
            List<WearEventAction> reports = actionMapper.selectList(new com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper<WearEventAction>()
                    .eq(WearEventAction::getEventId,id).eq(WearEventAction::getAction,"handle").orderByDesc(WearEventAction::getId).last("LIMIT 1"));
            if(reports.isEmpty()) throw new ServiceException("请先完成现场上报",409);
            // Device SOS keeps both workflow steps, but an administrator may perform both.
            if(!"sos".equals(event.getEventType()) && actor.equals(reports.get(0).getActor()))
                throw new ServiceException("现场上报人与审批人不能是同一账号",403);
        }
        String from = EventStateMachine.PENDING_REVIEW;
        int rows = eventMapper.closeIfStatus(id, from, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "review", actor, reason, from, EventStateMachine.VERIFIED);
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto reopen(Long id, String reason, Integer version)
    {
        siteAccessService.assertCanReviewEvent();
        requireVersion(version);
        if (StringUtils.isEmpty(reason))
        {
            throw new ServiceException("重开原因不能为空", HttpStatus.BAD_REQUEST);
        }
        WearSafetyEvent event = requireReadable(id);
        if (!EventStateMachine.canReopen(event.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        String actor = SecurityUtils.getUsername();
        String target = ManualSosService.isManual(event) ? EventStateMachine.PENDING_REVIEW : EventStateMachine.OPEN;
        int rows = ManualSosService.isManual(event)
                ? eventMapper.reopenManualSos(id, version, actor) : eventMapper.reopenIfClosed(id, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "reopen", actor, reason, event.getStatus(), target);
        WearSafetyEvent latest = eventMapper.selectById(id);
        notifyService.notifyAfterCommit(latest);
        return EventViews.toDto(latest);
    }

    @Transactional(rollbackFor = Exception.class)
    public void escalateDue()
    {
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.MINUTE, -5);
        List<WearSafetyEvent> due = eventMapper.selectDueSos(cal.getTime());
        for (WearSafetyEvent event : due)
        {
            escalateOne(event);
        }
    }

    @Transactional(rollbackFor = Exception.class)
    public WearSafetyEvent escalateIfDue(WearSafetyEvent event)
    {
        if (event == null)
        {
            return null;
        }
        if (!EventStateMachine.SOS.equals(event.getEventType()) || !EventStateMachine.OPEN.equals(event.getStatus()))
        {
            return event;
        }
        if (event.getEscalated() != null && event.getEscalated().intValue() == 1)
        {
            return event;
        }
        if (event.getOccurredAt() == null)
        {
            return event;
        }
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.MINUTE, -5);
        if (!event.getOccurredAt().before(cal.getTime()))
        {
            return event;
        }
        escalateOne(event);
        return eventMapper.selectById(event.getId());
    }

    private void escalateOne(WearSafetyEvent event)
    {
        int rows = eventMapper.markEscalated(event.getId());
        if (rows == 0)
        {
            return;
        }
        insertAction(event.getId(), "escalate", "system", "SOS超过5分钟未上报", EventStateMachine.OPEN, EventStateMachine.OPEN);
        WearSafetyEvent latest = eventMapper.selectById(event.getId());
        notifyService.notifyAfterCommit(latest);
    }

    public WearSafetyEvent requireReadable(Long id)
    {
        WearSafetyEvent event = eventMapper.selectById(id);
        if (event == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(event.getSiteId());
        eventAccess.assertReadable(event);
        return event;
    }

    private void requireVersion(Integer version)
    {
        if (version == null)
        {
            throw new ServiceException("version 不能为空", HttpStatus.BAD_REQUEST);
        }
    }

    private void insertAction(Long eventId, String action, String actor, String reason, String from, String to)
    {
        WearEventAction row = new WearEventAction();
        row.setEventId(eventId);
        row.setAction(action);
        row.setActor(actor);
        row.setReason(reason);
        row.setFromStatus(from);
        row.setToStatus(to);
        row.setCreateTime(new Date());
        actionMapper.insert(row);
    }
}
