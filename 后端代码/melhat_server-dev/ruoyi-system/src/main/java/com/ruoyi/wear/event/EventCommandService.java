package com.ruoyi.wear.event;

import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.system.service.ISysRoleService;
import com.ruoyi.system.service.ISysUserService;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.domain.WearEventAction;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.mapper.WearEventActionMapper;
import com.ruoyi.wear.event.mapper.WearEventInboxMapper;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
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
    private WearSiteAccountMapper siteAccountMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private EventNotifyService notifyService;
    @Autowired
    private ISysUserService userService;
    @Autowired
    private ISysRoleService roleService;
    @Autowired
    private WorkTaskService workTaskService;

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

    public EventDto ack(Long id)
    {
        WearSafetyEvent event = requireReadable(id);
        LoginUser user = siteAccessService.requireLogin();
        inboxMapper.markAcked(user.getUserId(), event.getId());
        insertAction(event.getId(), "ack", SecurityUtils.getUsername(), null, event.getStatus(), event.getStatus());
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto claim(Long id, Integer version)
    {
        siteAccessService.assertCanClaimEvent();
        requireVersion(version);
        WearSafetyEvent event = requireReadable(id);
        if (!EventStateMachine.canClaim(event.getStatus()))
        {
            throw new ServiceException("已被认领，请刷新", HttpStatus.CONFLICT);
        }
        LoginUser user = siteAccessService.requireLogin();
        String actor = SecurityUtils.getUsername();
        int rows = eventMapper.claimIfOpen(id, user.getUserId(), version, actor);
        if (rows == 0)
        {
            WearSafetyEvent latest = eventMapper.selectById(id);
            if (latest == null)
            {
                throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
            }
            if (!EventStateMachine.OPEN.equals(latest.getStatus()))
            {
                throw new ServiceException("已被认领，请刷新", HttpStatus.CONFLICT);
            }
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "claim", actor, null, EventStateMachine.OPEN, EventStateMachine.CLAIMED);
        inboxMapper.markAcked(user.getUserId(), id);
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto handle(Long id, String comment, Integer version)
    {
        siteAccessService.assertCanClaimEvent();
        requireVersion(version);
        WearSafetyEvent event = requireReadable(id);
        assertClaimant(event);
        if (!EventStateMachine.canHandle(event.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        String to = EventStateMachine.handleTarget(event.getEventType());
        String actor = SecurityUtils.getUsername();
        int rows = eventMapper.handleIfActive(id, to, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "handle", actor, comment, event.getStatus(), to);
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto transfer(Long id, String toUserIdRaw, String reason, Integer version)
    {
        siteAccessService.assertCanClaimEvent();
        requireVersion(version);
        if (StringUtils.isEmpty(toUserIdRaw) || StringUtils.isEmpty(reason))
        {
            throw new ServiceException("转交对象和原因不能为空", HttpStatus.BAD_REQUEST);
        }
        WearSafetyEvent event = requireReadable(id);
        assertClaimant(event);
        if (!EventStateMachine.canTransfer(event.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        Long toUserId;
        try
        {
            toUserId = Long.valueOf(toUserIdRaw.trim());
        }
        catch (NumberFormatException ex)
        {
            throw new ServiceException("转交对象无效", HttpStatus.BAD_REQUEST);
        }
        LoginUser me = siteAccessService.requireLogin();
        if (toUserId.equals(me.getUserId()))
        {
            throw new ServiceException("不能转交给自己", HttpStatus.BAD_REQUEST);
        }
        assertTransferTarget(toUserId, event.getSiteId());
        String actor = SecurityUtils.getUsername();
        int rows = eventMapper.transferIfActive(id, toUserId, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "transfer", actor, reason, event.getStatus(), event.getStatus());
        inboxMapper.markAcked(toUserId, id);
        return EventViews.toDto(eventMapper.selectById(id));
    }

    @Transactional(rollbackFor = Exception.class)
    public EventDto close(Long id, String reason, Integer version)
    {
        requireVersion(version);
        if (StringUtils.isEmpty(reason))
        {
            throw new ServiceException("关闭原因不能为空", HttpStatus.BAD_REQUEST);
        }
        WearSafetyEvent event = requireReadable(id);
        String actor = SecurityUtils.getUsername();
        String from;
        if (EventStateMachine.isHighRisk(event.getEventType()))
        {
            if (!siteAccessService.canReviewEvent())
            {
                throw new ServiceException("高风险须复核后关闭", HttpStatus.FORBIDDEN);
            }
            if (!EventStateMachine.canReviewerClose(event.getEventType(), event.getStatus()))
            {
                throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
            }
            from = EventStateMachine.PENDING_REVIEW;
        }
        else
        {
            siteAccessService.assertCanClaimEvent();
            if (!EventStateMachine.canDutyClose(event.getEventType(), event.getStatus()))
            {
                throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
            }
            from = EventStateMachine.HANDLING;
        }
        int rows = eventMapper.closeIfStatus(id, from, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "close", actor, reason, from, EventStateMachine.CLOSED);
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
        int rows = eventMapper.reopenIfClosed(id, version, actor);
        if (rows == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "reopen", actor, reason, EventStateMachine.CLOSED, EventStateMachine.OPEN);
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
        insertAction(event.getId(), "escalate", "system", "SOS超过5分钟未认领", EventStateMachine.OPEN, EventStateMachine.OPEN);
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
        return event;
    }

    private void assertClaimant(WearSafetyEvent event)
    {
        LoginUser user = siteAccessService.requireLogin();
        if (event.getClaimantUserId() == null || !event.getClaimantUserId().equals(user.getUserId()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    private void assertTransferTarget(Long userId, Long siteId)
    {
        SysUser target = userService.selectUserById(userId);
        if (target == null || "2".equals(target.getDelFlag()) || !"0".equals(target.getStatus()))
        {
            throw new ServiceException("转交对象无效", HttpStatus.BAD_REQUEST);
        }
        if (siteAccountMapper.selectCount(new LambdaQueryWrapper<WearSiteAccount>()
                .eq(WearSiteAccount::getUserId, userId)
                .eq(WearSiteAccount::getSiteId, siteId)
                .eq(WearSiteAccount::getStatus, "0")) == 0)
        {
            throw new ServiceException("转交对象不在该厂站", HttpStatus.FORBIDDEN);
        }
        Set<String> roles = roleService.selectRolePermissionByUserId(userId);
        if (!WearRoleKeys.canClaimEvent(roles, false))
        {
            throw new ServiceException("转交对象不能认领事件", HttpStatus.FORBIDDEN);
        }
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
