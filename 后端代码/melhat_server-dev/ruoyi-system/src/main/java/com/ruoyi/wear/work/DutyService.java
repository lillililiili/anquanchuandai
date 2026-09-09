package com.ruoyi.wear.work;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.alibaba.fastjson2.JSON;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.system.service.ISysRoleService;
import com.ruoyi.system.service.ISysUserService;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.EventStateMachine;
import com.ruoyi.wear.event.EventViews;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
import com.ruoyi.wear.work.domain.WearDutyHandover;
import com.ruoyi.wear.work.domain.WearWorkTask;
import com.ruoyi.wear.work.dto.EquipmentCheckDto;
import com.ruoyi.wear.work.dto.HandoverDto;
import com.ruoyi.wear.work.dto.WorkTaskDto;
import com.ruoyi.wear.work.mapper.WearDutyHandoverMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskMapper;

@Service
public class DutyService
{
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private WearSafetyEventMapper eventMapper;
    @Autowired
    private WearWorkTaskMapper taskMapper;
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private WearDutyHandoverMapper handoverMapper;
    @Autowired
    private WorkTaskService workTaskService;
    @Autowired
    private WearSiteAccountMapper siteAccountMapper;
    @Autowired
    private ISysUserService userService;
    @Autowired
    private ISysRoleService roleService;

    public Map<String, Object> summary()
    {
        siteAccessService.requireLogin();
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        LoginUser user = siteAccessService.requireLogin();
        Map<String, Object> data = new HashMap<String, Object>();
        data.put("unclaimed", countEvents(siteId, EventStateMachine.OPEN, null));
        data.put("mine", countMine(siteId, user.getUserId()));
        data.put("overdue", countOverdue(siteId));
        data.put("lostSupervision", countLostSupervision(siteId));
        int[] counts = peopleDeviceCounts(siteId);
        data.put("peopleCount", Integer.valueOf(counts[0]));
        data.put("deviceCount", Integer.valueOf(counts[1]));
        List<WorkTaskDto> active = new ArrayList<WorkTaskDto>();
        List<WearWorkTask> tasks = taskMapper.selectList(new LambdaQueryWrapper<WearWorkTask>()
                .eq(WearWorkTask::getSiteId, siteId)
                .in(WearWorkTask::getStatus, WorkTaskStateMachine.IN_PROGRESS, WorkTaskStateMachine.PAUSED, WorkTaskStateMachine.READY)
                .orderByDesc(WearWorkTask::getId).last("LIMIT 10"));
        for (WearWorkTask task : tasks)
        {
            active.add(workTaskService.requireDto(task.getId()));
        }
        data.put("activeTasks", active);
        List<Object> recent = new ArrayList<Object>();
        List<WearSafetyEvent> events = eventMapper.selectList(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSiteId, siteId)
                .ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED)
                .orderByDesc(WearSafetyEvent::getId).last("LIMIT 8"));
        for (WearSafetyEvent event : events)
        {
            recent.add(EventViews.toDto(event));
        }
        data.put("recentEvents", recent);
        return data;
    }

    public List<Map<String, String>> operators()
    {
        siteAccessService.requireLogin();
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        List<WearSiteAccount> grants = siteAccountMapper.selectList(new LambdaQueryWrapper<WearSiteAccount>()
                .eq(WearSiteAccount::getSiteId, siteId).eq(WearSiteAccount::getStatus, "0"));
        List<Map<String, String>> list = new ArrayList<Map<String, String>>();
        for (WearSiteAccount grant : grants)
        {
            SysUser user = userService.selectUserById(grant.getUserId());
            if (user == null || "2".equals(user.getDelFlag()) || !"0".equals(user.getStatus()))
            {
                continue;
            }
            Set<String> roles = roleService.selectRolePermissionByUserId(user.getUserId());
            if (!WearRoleKeys.canClaimEvent(roles, false))
            {
                continue;
            }
            Map<String, String> row = new HashMap<String, String>();
            row.put("userId", String.valueOf(user.getUserId()));
            row.put("userName", user.getUserName());
            row.put("nickName", user.getNickName());
            list.add(row);
        }
        return list;
    }

    public List<HandoverDto> handovers()
    {
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        List<WearDutyHandover> rows = handoverMapper.selectList(new LambdaQueryWrapper<WearDutyHandover>()
                .eq(WearDutyHandover::getSiteId, siteId).orderByDesc(WearDutyHandover::getId).last("LIMIT 20"));
        List<HandoverDto> list = new ArrayList<HandoverDto>();
        for (WearDutyHandover row : rows)
        {
            list.add(toDto(row));
        }
        return list;
    }

    @Transactional(rollbackFor = Exception.class)
    public HandoverDto createHandover(Map<String, Object> body)
    {
        siteAccessService.assertCanEditTask();
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        LoginUser from = siteAccessService.requireLogin();
        Long toUserId = parseLong(body == null ? null : body.get("toUserId"));
        if (toUserId == null)
        {
            throw new ServiceException("接班人不能为空", HttpStatus.BAD_REQUEST);
        }
        if (toUserId.equals(from.getUserId()))
        {
            throw new ServiceException("不能交接给自己", HttpStatus.BAD_REQUEST);
        }
        assertDutyTarget(toUserId, siteId);
        List<String> eventIds = stringList(body, "eventIds");
        List<String> taskIds = stringList(body, "taskIds");
        if (eventIds.isEmpty())
        {
            eventIds = defaultEventIds(siteId, from.getUserId());
        }
        if (taskIds.isEmpty())
        {
            taskIds = defaultTaskIds(siteId, from.getUserId());
        }
        Map<String, Object> payload = new HashMap<String, Object>();
        payload.put("eventIds", eventIds);
        payload.put("taskIds", taskIds);
        WearDutyHandover row = new WearDutyHandover();
        row.setSiteId(siteId);
        row.setFromUserId(from.getUserId());
        row.setToUserId(toUserId);
        row.setStatus("pending");
        row.setPayloadJson(JSON.toJSONString(payload));
        row.setComment(body == null || body.get("comment") == null ? null : String.valueOf(body.get("comment")));
        row.setVersion(1);
        String actor = SecurityUtils.getUsername();
        row.setCreateBy(actor);
        row.setCreateTime(new Date());
        row.setUpdateBy(actor);
        row.setUpdateTime(new Date());
        handoverMapper.insert(row);
        return toDto(row);
    }

    @Transactional(rollbackFor = Exception.class)
    public HandoverDto confirm(Long id)
    {
        siteAccessService.assertCanEditTask();
        LoginUser user = siteAccessService.requireLogin();
        WearDutyHandover row = handoverMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(row.getSiteId());
        if (!"pending".equals(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (!user.getUserId().equals(row.getToUserId()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        if (handoverMapper.confirmIfPending(id, user.getUserId(), SecurityUtils.getUsername()) == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        Map<?, ?> payload = JSON.parseObject(row.getPayloadJson());
        List<String> eventIds = payload == null ? new ArrayList<String>() : stringListFromJson(payload.get("eventIds"));
        List<String> taskIds = payload == null ? new ArrayList<String>() : stringListFromJson(payload.get("taskIds"));
        String actor = SecurityUtils.getUsername();
        for (String eventId : eventIds)
        {
            Long eid = parseLong(eventId);
            WearSafetyEvent event = eid == null ? null : eventMapper.selectById(eid);
            if (event == null || !row.getFromUserId().equals(event.getClaimantUserId()))
            {
                continue;
            }
            if (!EventStateMachine.canTransfer(event.getStatus()))
            {
                continue;
            }
            eventMapper.transferIfActive(eid, row.getToUserId(), event.getVersion(), actor);
        }
        for (String taskId : taskIds)
        {
            Long tid = parseLong(taskId);
            if (tid != null)
            {
                workTaskService.transferOwner(tid, row.getToUserId(), actor);
            }
        }
        return toDto(handoverMapper.selectById(id));
    }

    private int countEvents(Long siteId, String status, Long claimant)
    {
        LambdaQueryWrapper<WearSafetyEvent> query = new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSiteId, siteId).eq(WearSafetyEvent::getStatus, status);
        if (claimant != null)
        {
            query.eq(WearSafetyEvent::getClaimantUserId, claimant);
        }
        return toInt(eventMapper.selectCount(query));
    }

    private int countMine(Long siteId, Long userId)
    {
        return toInt(eventMapper.selectCount(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSiteId, siteId)
                .eq(WearSafetyEvent::getClaimantUserId, userId)
                .ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED)));
    }

    private int countOverdue(Long siteId)
    {
        return toInt(eventMapper.selectCount(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSiteId, siteId)
                .eq(WearSafetyEvent::getEscalated, 1)
                .ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED)));
    }

    private int countLostSupervision(Long siteId)
    {
        Set<String> people = new HashSet<String>();
        List<WearWorkTask> tasks = taskMapper.selectList(new LambdaQueryWrapper<WearWorkTask>()
                .eq(WearWorkTask::getSiteId, siteId).eq(WearWorkTask::getStatus, WorkTaskStateMachine.IN_PROGRESS));
        for (WearWorkTask task : tasks)
        {
            for (EquipmentCheckDto item : workTaskService.buildEquipmentCheck(task))
            {
                if ("helmet".equals(item.getTypeCode()) && !EquipmentCheck.OK.equals(item.getResult()))
                {
                    people.add(item.getPersonId());
                }
            }
        }
        return people.size();
    }

    private int[] peopleDeviceCounts(Long siteId)
    {
        List<WearAssignment> rows = assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getSiteId, siteId).isNull(WearAssignment::getReturnedAt));
        Set<Long> people = new HashSet<Long>();
        Set<Long> devices = new HashSet<Long>();
        for (WearAssignment row : rows)
        {
            people.add(row.getPersonId());
            devices.add(row.getDeviceId());
        }
        return new int[] { people.size(), devices.size() };
    }

    private List<String> defaultEventIds(Long siteId, Long userId)
    {
        List<String> ids = new ArrayList<String>();
        List<WearSafetyEvent> rows = eventMapper.selectList(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSiteId, siteId)
                .eq(WearSafetyEvent::getClaimantUserId, userId)
                .ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED));
        for (WearSafetyEvent row : rows)
        {
            ids.add(String.valueOf(row.getId()));
        }
        return ids;
    }

    private List<String> defaultTaskIds(Long siteId, Long userId)
    {
        List<String> ids = new ArrayList<String>();
        List<WearWorkTask> rows = taskMapper.selectList(new LambdaQueryWrapper<WearWorkTask>()
                .eq(WearWorkTask::getSiteId, siteId)
                .eq(WearWorkTask::getOwnerUserId, userId)
                .ne(WearWorkTask::getStatus, WorkTaskStateMachine.ENDED));
        for (WearWorkTask row : rows)
        {
            ids.add(String.valueOf(row.getId()));
        }
        return ids;
    }

    private void assertDutyTarget(Long userId, Long siteId)
    {
        SysUser target = userService.selectUserById(userId);
        if (target == null || "2".equals(target.getDelFlag()) || !"0".equals(target.getStatus()))
        {
            throw new ServiceException("接班人无效", HttpStatus.BAD_REQUEST);
        }
        if (siteAccountMapper.selectCount(new LambdaQueryWrapper<WearSiteAccount>()
                .eq(WearSiteAccount::getUserId, userId)
                .eq(WearSiteAccount::getSiteId, siteId)
                .eq(WearSiteAccount::getStatus, "0")) == 0)
        {
            throw new ServiceException("接班人不在该厂站", HttpStatus.FORBIDDEN);
        }
        Set<String> roles = roleService.selectRolePermissionByUserId(userId);
        if (!WearRoleKeys.canClaimEvent(roles, false))
        {
            throw new ServiceException("接班人不能值班", HttpStatus.FORBIDDEN);
        }
    }

    private HandoverDto toDto(WearDutyHandover row)
    {
        HandoverDto dto = new HandoverDto();
        dto.setId(String.valueOf(row.getId()));
        dto.setSiteId(String.valueOf(row.getSiteId()));
        dto.setFromUserId(String.valueOf(row.getFromUserId()));
        dto.setFromUserName(userDisplay(row.getFromUserId()));
        dto.setToUserId(String.valueOf(row.getToUserId()));
        dto.setToUserName(userDisplay(row.getToUserId()));
        dto.setStatus(row.getStatus());
        dto.setPayloadJson(row.getPayloadJson());
        dto.setComment(row.getComment());
        dto.setCreateTime(row.getCreateTime());
        dto.setConfirmedAt(row.getConfirmedAt());
        return dto;
    }

    private String userDisplay(Long userId)
    {
        if (userId == null)
        {
            return null;
        }
        SysUser user = userService.selectUserById(userId);
        if (user == null)
        {
            return String.valueOf(userId);
        }
        if (StringUtils.isNotEmpty(user.getNickName()))
        {
            return user.getNickName();
        }
        return user.getUserName();
    }

    private static int toInt(Number n)
    {
        return n == null ? 0 : n.intValue();
    }

    private static Long parseLong(Object raw)
    {
        if (raw == null)
        {
            return null;
        }
        try
        {
            return Long.valueOf(String.valueOf(raw).trim());
        }
        catch (NumberFormatException ex)
        {
            return null;
        }
    }

    private static List<String> stringList(Map<String, Object> body, String key)
    {
        if (body == null || !(body.get(key) instanceof List))
        {
            return new ArrayList<String>();
        }
        return stringListFromJson(body.get(key));
    }

    private static List<String> stringListFromJson(Object raw)
    {
        List<String> values = new ArrayList<String>();
        if (!(raw instanceof List))
        {
            return values;
        }
        for (Object item : (List<?>) raw)
        {
            if (item != null && StringUtils.isNotEmpty(String.valueOf(item)))
            {
                values.add(String.valueOf(item));
            }
        }
        return values;
    }
}
