package com.ruoyi.wear.work;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.event.EventStateMachine;
import com.ruoyi.wear.event.EventViews;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.person.PersonEligibility;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.domain.WearPersonSite;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.person.mapper.WearPersonSiteMapper;
import com.ruoyi.wear.space.domain.WearSpace;
import com.ruoyi.wear.space.mapper.WearSpaceMapper;
import com.ruoyi.wear.work.domain.WearWorkTask;
import com.ruoyi.wear.work.domain.WearWorkTaskAction;
import com.ruoyi.wear.work.domain.WearWorkTaskMember;
import com.ruoyi.wear.work.domain.WearWorkTaskRequirement;
import com.ruoyi.wear.work.dto.EquipmentCheckDto;
import com.ruoyi.wear.work.dto.WorkMemberDto;
import com.ruoyi.wear.work.dto.WorkTaskDto;
import com.ruoyi.wear.work.mapper.WearWorkTaskActionMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskMemberMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskRequirementMapper;

@Service
public class WorkTaskService
{
    @Autowired private org.springframework.jdbc.core.JdbcTemplate inspectionDb;
    @Autowired private com.ruoyi.wear.event.EventAccessService eventAccess;
    @Autowired
    private WearWorkTaskMapper taskMapper;
    @Autowired
    private WearWorkTaskMemberMapper memberMapper;
    @Autowired
    private WearWorkTaskRequirementMapper requirementMapper;
    @Autowired
    private WearWorkTaskActionMapper actionMapper;
    @Autowired
    private WearPersonMapper personMapper;
    @Autowired
    private WearPersonSiteMapper personSiteMapper;
    @Autowired
    private WearSpaceMapper spaceMapper;
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private WearSafetyEventMapper eventMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Value("${melhat.telemetry.stale-after-seconds:180}")
    private int staleAfterSeconds;

    public WearPage<WorkTaskDto> page(int current, int size, String status, String workType)
    {
        if (!siteAccessService.isPlatformAdmin(siteAccessService.requireLogin()))
            throw new ServiceException("仅管理员可以查看全站作业", HttpStatus.FORBIDDEN);
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty())
        {
            return WearPage.of(Collections.<WorkTaskDto>emptyList(), 0, current, size);
        }
        if (size > 100)
        {
            size = 100;
        }
        if (current < 1)
        {
            current = 1;
        }
        LambdaQueryWrapper<WearWorkTask> query = new LambdaQueryWrapper<WearWorkTask>()
                .in(WearWorkTask::getSiteId, scope)
                .orderByDesc(WearWorkTask::getId);
        if (StringUtils.isNotEmpty(status))
        {
            query.eq(WearWorkTask::getStatus, status);
        }
        if (StringUtils.isNotEmpty(workType))
        {
            query.eq(WearWorkTask::getWorkType, workType);
        }
        IPage<WearWorkTask> page = taskMapper.selectPage(new Page<WearWorkTask>(current, size), query);
        List<WorkTaskDto> records = new ArrayList<WorkTaskDto>();
        for (WearWorkTask row : page.getRecords())
        {
            records.add(toDto(row, false));
        }
        return WearPage.of(records, page.getTotal(), current, size);
    }

    public WearPage<WorkTaskDto> mine(int current, int size)
    {
        LoginUser user = siteAccessService.requireLogin();
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty())
        {
            return WearPage.of(Collections.<WorkTaskDto>emptyList(), 0, current, size);
        }
        Set<Long> taskIds = memberTaskIds();
        if (taskIds.isEmpty()) return WearPage.of(Collections.<WorkTaskDto>emptyList(), 0, current, size);
        current = Math.max(1, current);
        size = Math.max(1, Math.min(100, size));
        IPage<WearWorkTask> page = taskMapper.selectPage(new Page<WearWorkTask>(current, size),
                new LambdaQueryWrapper<WearWorkTask>().in(WearWorkTask::getId, taskIds)
                        .in(WearWorkTask::getSiteId, scope).orderByDesc(WearWorkTask::getId));
        List<WorkTaskDto> records = new ArrayList<WorkTaskDto>();
        for (WearWorkTask row : page.getRecords()) records.add(toDto(row, false));
        return WearPage.of(records, page.getTotal(), current, size);
    }

    public Set<Long> memberTaskIds()
    {
        LoginUser user = siteAccessService.requireLogin();
        List<Long> scope = siteAccessService.listScopeSiteIds();
        Set<Long> taskIds = new HashSet<Long>();
        if (scope.isEmpty()) return taskIds;
        List<WearWorkTask> owned = taskMapper.selectList(new LambdaQueryWrapper<WearWorkTask>()
                .eq(WearWorkTask::getOwnerUserId, user.getUserId())
                .in(WearWorkTask::getSiteId, scope));
        for (WearWorkTask row : owned)
        {
            taskIds.add(row.getId());
        }
        WearPerson me = personMapper.selectOne(new LambdaQueryWrapper<WearPerson>()
                .eq(WearPerson::getAccountUserId, user.getUserId()).last("LIMIT 1"));
        if (me != null)
        {
            if (!PersonEligibility.selectableForNewWork(me, true, new Date())) return taskIds;
            for (WearWorkTask row : taskMapper.selectList(new LambdaQueryWrapper<WearWorkTask>()
                    .eq(WearWorkTask::getGuardianPersonId, me.getId()).in(WearWorkTask::getSiteId, scope)))
                taskIds.add(row.getId());
            List<WearWorkTaskMember> memberships = memberMapper.selectList(new LambdaQueryWrapper<WearWorkTaskMember>()
                    .eq(WearWorkTaskMember::getPersonId, me.getId()));
            for (WearWorkTaskMember item : memberships)
            {
                taskIds.add(item.getTaskId());
            }
        }
        return taskIds;
    }

    public WorkTaskDto detail(Long id)
    {
        return toDto(requireReadable(id), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto create(Map<String, Object> body)
    {
        siteAccessService.assertCanEditTask();
        Long siteId = siteAccessService.requireCurrentSiteForWrite();
        String title = str(body, "title");
        String workType = str(body, "workType");
        if (StringUtils.isEmpty(title) || !WorkTaskStateMachine.isKnownType(workType))
        {
            throw new ServiceException("标题和作业类型不能为空", HttpStatus.BAD_REQUEST);
        }
        Date start = parseTime(str(body, "plannedStart"), false);
        Date end = parseTime(str(body, "plannedEnd"), false);
        List<Long> personIds = longList(body, "personIds");
        boolean required = bool(body, "ticketRequired");
        String ticketNo = str(body, "ticketNo");
        Date now = new Date();
        WearWorkTask row = new WearWorkTask();
        row.setSiteId(siteId);
        row.setTitle(title.trim());
        row.setWorkType(workType);
        row.setSpaceId(parseLong(str(body, "spaceId")));
        row.setPlannedStart(start);
        row.setPlannedEnd(end);
        row.setOwnerUserId(siteAccessService.requireLogin().getUserId());
        row.setGuardianPersonId(parseLong(str(body, "guardianPersonId")));
        row.setTicketRequired(required ? 1 : 0);
        row.setTicketNo(ticketNo);
        row.setTicketStatus(WorkTaskStateMachine.ticketStatus(required, ticketNo));
        row.setDemo(0);
        row.setStatus(WorkTaskStateMachine.initialStatus(!personIds.isEmpty(), start != null && end != null));
        row.setVersion(1);
        String actor = SecurityUtils.getUsername();
        row.setCreateBy(actor);
        row.setCreateTime(now);
        row.setUpdateBy(actor);
        row.setUpdateTime(now);
        taskMapper.insert(row);
        replaceRequirements(row.getId(), stringList(body, "requirements"));
        for (Long personId : personIds)
        {
            addMemberInternal(row, personId, false);
        }
        refreshReady(row.getId());
        insertAction(row.getId(), "create", actor, null, null, row.getStatus());
        return toDto(taskMapper.selectById(row.getId()), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto update(Long id, Map<String, Object> body)
    {
        siteAccessService.assertCanEditTask();
        requireVersion(intVal(body, "version"));
        WearWorkTask row = requireReadable(id);
        if (WorkTaskStateMachine.isEnded(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (!row.getVersion().equals(intVal(body, "version")))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (body.containsKey("title") && StringUtils.isNotEmpty(str(body, "title")))
        {
            row.setTitle(str(body, "title").trim());
        }
        if (body.containsKey("workType") && WorkTaskStateMachine.isKnownType(str(body, "workType")))
        {
            row.setWorkType(str(body, "workType"));
        }
        if (body.containsKey("spaceId"))
        {
            row.setSpaceId(parseLong(str(body, "spaceId")));
        }
        if (body.containsKey("plannedStart"))
        {
            row.setPlannedStart(parseTime(str(body, "plannedStart"), false));
        }
        if (body.containsKey("plannedEnd"))
        {
            row.setPlannedEnd(parseTime(str(body, "plannedEnd"), false));
        }
        if (body.containsKey("guardianPersonId"))
        {
            row.setGuardianPersonId(parseLong(str(body, "guardianPersonId")));
        }
        if (body.containsKey("ticketRequired") || body.containsKey("ticketNo"))
        {
            boolean required = body.containsKey("ticketRequired") ? bool(body, "ticketRequired")
                    : (row.getTicketRequired() != null && row.getTicketRequired().intValue() == 1);
            String ticketNo = body.containsKey("ticketNo") ? str(body, "ticketNo") : row.getTicketNo();
            row.setTicketRequired(required ? 1 : 0);
            row.setTicketNo(ticketNo);
            row.setTicketStatus(WorkTaskStateMachine.ticketStatus(required, ticketNo));
        }
        if (body.containsKey("requirements"))
        {
            replaceRequirements(id, stringList(body, "requirements"));
        }
        row.setVersion(row.getVersion() + 1);
        row.setUpdateBy(SecurityUtils.getUsername());
        row.setUpdateTime(new Date());
        taskMapper.updateById(row);
        refreshReady(id);
        return toDto(taskMapper.selectById(id), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto addMembers(Long id, Map<String, Object> body)
    {
        siteAccessService.assertCanEditTask();
        WearWorkTask row = requireReadable(id);
        if (!WorkTaskStateMachine.canEditMembers(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        for (Long personId : longList(body, "personIds"))
        {
            addMemberInternal(row, personId, true);
        }
        refreshReady(id);
        return toDto(taskMapper.selectById(id), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto removeMember(Long id, Long personId)
    {
        siteAccessService.assertCanEditTask();
        WearWorkTask row = requireReadable(id);
        if (!WorkTaskStateMachine.canEditMembers(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        memberMapper.delete(new LambdaQueryWrapper<WearWorkTaskMember>()
                .eq(WearWorkTaskMember::getTaskId, id).eq(WearWorkTaskMember::getPersonId, personId));
        insertAction(id, "member", SecurityUtils.getUsername(), "remove " + personId, row.getStatus(), row.getStatus());
        refreshReady(id);
        return toDto(taskMapper.selectById(id), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto start(Long id, Integer version)
    {
        siteAccessService.assertCanEditTask();
        requireVersion(version);
        WearWorkTask row = requireReadable(id);
        if (!WorkTaskStateMachine.canStart(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        int n = taskMapper.startIfReady(id, WorkTaskStateMachine.IN_PROGRESS, version, SecurityUtils.getUsername());
        if (n == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "start", SecurityUtils.getUsername(), null, row.getStatus(), WorkTaskStateMachine.IN_PROGRESS);
        return toDto(taskMapper.selectById(id), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto pause(Long id, Integer version)
    {
        siteAccessService.assertCanEditTask();
        requireVersion(version);
        WearWorkTask row = requireReadable(id);
        if (!WorkTaskStateMachine.canPause(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (taskMapper.pauseIfActive(id, version, SecurityUtils.getUsername()) == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "pause", SecurityUtils.getUsername(), null, row.getStatus(), WorkTaskStateMachine.PAUSED);
        return toDto(taskMapper.selectById(id), true);
    }

    @Transactional(rollbackFor = Exception.class)
    public WorkTaskDto end(Long id, Integer version, boolean acknowledgeOpenHighRisk)
    {
        siteAccessService.assertCanEditTask();
        requireVersion(version);
        WearWorkTask row = requireReadable(id);
        if (!WorkTaskStateMachine.canEnd(row.getStatus()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (hasOpenHighRisk(id) && !acknowledgeOpenHighRisk)
        {
            throw new ServiceException("存在未关闭的高风险事件，确认后才能结束任务", HttpStatus.CONFLICT);
        }
        if (taskMapper.endIfActive(id, version, SecurityUtils.getUsername()) == 0)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        insertAction(id, "end", SecurityUtils.getUsername(),
                acknowledgeOpenHighRisk ? "acknowledgeOpenHighRisk" : null, row.getStatus(), WorkTaskStateMachine.ENDED);
        return toDto(taskMapper.selectById(id), true);
    }

    public List<EquipmentCheckDto> equipmentCheck(Long id)
    {
        WearWorkTask row = requireReadable(id);
        return buildEquipmentCheck(row);
    }

    public List<EventDto> events(Long id)
    {
        WearWorkTask row = requireReadable(id);
        Set<Long> members = memberIds(id);
        LambdaQueryWrapper<WearSafetyEvent> query = new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getSiteId, row.getSiteId());
        if (members.isEmpty())
        {
            query.eq(WearSafetyEvent::getTaskId, id);
        }
        else
        {
            query.and(q -> q.eq(WearSafetyEvent::getTaskId, id)
                    .or(w -> w.eq(WearSafetyEvent::getTaskMatch, WorkTaskStateMachine.PENDING)
                            .in(WearSafetyEvent::getPersonId, members)));
        }
        eventAccess.scope(query);
        query.orderByDesc(WearSafetyEvent::getId).last("LIMIT 50");
        List<WearSafetyEvent> rows = eventMapper.selectList(query);
        List<EventDto> list = new ArrayList<EventDto>();
        for (WearSafetyEvent event : rows)
        {
            list.add(EventViews.toDto(event));
        }
        return list;
    }

    public WorkTaskDto requireDto(Long id)
    {
        return toDto(requireReadable(id), false);
    }

    public WearWorkTask requireReadable(Long id)
    {
        WearWorkTask row = taskMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(row.getSiteId());
        if (!siteAccessService.listScopeSiteIds().contains(row.getSiteId()) ||
                (!siteAccessService.isPlatformAdmin(siteAccessService.requireLogin()) && !memberTaskIds().contains(id)))
            throw new ServiceException("只能查看当前组的巡检任务", HttpStatus.FORBIDDEN);
        return row;
    }

    public List<EquipmentCheckDto> buildEquipmentCheck(WearWorkTask task)
    {
        List<EquipmentCheckDto> list = new ArrayList<EquipmentCheckDto>();
        List<WearWorkTaskRequirement> reqs = requirementMapper.selectList(new LambdaQueryWrapper<WearWorkTaskRequirement>()
                .eq(WearWorkTaskRequirement::getTaskId, task.getId()));
        List<WearWorkTaskMember> members = memberMapper.selectList(new LambdaQueryWrapper<WearWorkTaskMember>()
                .eq(WearWorkTaskMember::getTaskId, task.getId()));
        Date now = new Date();
        for (WearWorkTaskMember member : members)
        {
            WearPerson person = personMapper.selectById(member.getPersonId());
            boolean selectable = person != null && PersonEligibility.selectableForNewWork(person, hasSiteGrant(member.getPersonId(), task.getSiteId()), now);
            List<WearAssignment> issued = assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                    .eq(WearAssignment::getPersonId, member.getPersonId())
                    .isNull(WearAssignment::getReturnedAt));
            for (WearWorkTaskRequirement req : reqs)
            {
                WearAssignment hit = null;
                WearDevice device = null;
                for (WearAssignment assignment : issued)
                {
                    WearDevice d = deviceMapper.selectById(assignment.getDeviceId());
                    if (d == null)
                    {
                        continue;
                    }
                    WearProductModel m = d.getModelId() == null ? null : modelMapper.selectById(d.getModelId());
                    if (m != null && req.getTypeCode().equals(m.getTypeCode()))
                    {
                        hit = assignment;
                        device = d;
                        break;
                    }
                }
                EquipmentCheckDto item = new EquipmentCheckDto();
                item.setPersonId(String.valueOf(member.getPersonId()));
                item.setPersonName(person == null ? null : person.getName());
                item.setTypeCode(req.getTypeCode());
                String quality = device == null ? TelemetryFreshness.UNKNOWN
                        : TelemetryFreshness.connectionQuality(device.getLastReportedAt(), now, staleAfterSeconds);
                item.setResult(EquipmentCheck.result(req.getTypeCode(), hit != null, quality));
                item.setSn(device == null ? null : device.getSn());
                item.setNeedsConfirm(!selectable || (task.getDemo() != null && task.getDemo().intValue() == 1));
                list.add(item);
            }
        }
        return list;
    }

    @Transactional(rollbackFor = Exception.class)
    public void transferOwner(Long taskId, Long toUserId, String actor)
    {
        WearWorkTask row = taskMapper.selectById(taskId);
        if (row == null || WorkTaskStateMachine.isEnded(row.getStatus()))
        {
            return;
        }
        if (taskMapper.transferOwner(taskId, toUserId, row.getVersion(), actor) > 0)
        {
            insertAction(taskId, "handover", actor, String.valueOf(toUserId), row.getStatus(), row.getStatus());
        }
    }

    public void transferDutyOwner(Long taskId, Long siteId, Long fromUserId, Long toUserId, String actor)
    {
        WearWorkTask row = taskMapper.selectOne(new LambdaQueryWrapper<WearWorkTask>()
                .eq(WearWorkTask::getId, taskId).last("FOR UPDATE"));
        if (row == null || !siteId.equals(row.getSiteId()) || !fromUserId.equals(row.getOwnerUserId())
                || WorkTaskStateMachine.isEnded(row.getStatus())) return;
        if (taskMapper.transferOwner(taskId, toUserId, row.getVersion(), actor) != 1)
            throw new ServiceException("作业负责人已变更，请刷新重试", HttpStatus.CONFLICT);
        insertAction(taskId, "handover", actor, String.valueOf(toUserId), row.getStatus(), row.getStatus());
    }

    private void addMemberInternal(WearWorkTask task, Long personId, boolean log)
    {
        WearPerson person = personMapper.selectById(personId);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        if (!PersonEligibility.selectableForNewWork(person, hasSiteGrant(personId, task.getSiteId()), new Date()))
        {
            throw new ServiceException("该人员当前不可加入任务", HttpStatus.BAD_REQUEST);
        }
        if (memberMapper.selectCount(new LambdaQueryWrapper<WearWorkTaskMember>()
                .eq(WearWorkTaskMember::getTaskId, task.getId()).eq(WearWorkTaskMember::getPersonId, personId)) > 0)
        {
            return;
        }
        WearWorkTaskMember row = new WearWorkTaskMember();
        row.setTaskId(task.getId());
        row.setPersonId(personId);
        row.setCreateTime(new Date());
        memberMapper.insert(row);
        if (log)
        {
            insertAction(task.getId(), "member", SecurityUtils.getUsername(), String.valueOf(personId), task.getStatus(), task.getStatus());
        }
    }

    private boolean hasSiteGrant(Long personId, Long siteId)
    {
        return personSiteMapper.selectCount(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, personId)
                .eq(WearPersonSite::getSiteId, siteId)
                .eq(WearPersonSite::getStatus, "0")) > 0;
    }

    private void replaceRequirements(Long taskId, List<String> types)
    {
        requirementMapper.delete(new LambdaQueryWrapper<WearWorkTaskRequirement>().eq(WearWorkTaskRequirement::getTaskId, taskId));
        Set<String> seen = new HashSet<String>();
        for (String type : types)
        {
            if (!"helmet".equals(type) && !"belt".equals(type) || seen.contains(type))
            {
                continue;
            }
            seen.add(type);
            WearWorkTaskRequirement row = new WearWorkTaskRequirement();
            row.setTaskId(taskId);
            row.setTypeCode(type);
            requirementMapper.insert(row);
        }
    }

    private void refreshReady(Long id)
    {
        WearWorkTask row = taskMapper.selectById(id);
        if (row == null || WorkTaskStateMachine.IN_PROGRESS.equals(row.getStatus())
                || WorkTaskStateMachine.PAUSED.equals(row.getStatus()) || WorkTaskStateMachine.isEnded(row.getStatus()))
        {
            return;
        }
        boolean hasMember = memberMapper.selectCount(new LambdaQueryWrapper<WearWorkTaskMember>()
                .eq(WearWorkTaskMember::getTaskId, id)) > 0;
        boolean hasWindow = row.getPlannedStart() != null && row.getPlannedEnd() != null;
        String next = WorkTaskStateMachine.initialStatus(hasMember, hasWindow);
        if (!next.equals(row.getStatus()))
        {
            row.setStatus(next);
            row.setUpdateTime(new Date());
            taskMapper.updateById(row);
        }
    }

    private boolean hasOpenHighRisk(Long taskId)
    {
        return eventMapper.selectCount(new LambdaQueryWrapper<WearSafetyEvent>()
                .eq(WearSafetyEvent::getTaskId, taskId)
                .ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED)
                .eq(WearSafetyEvent::getSeverity, "high")) > 0;
    }

    private Set<Long> memberIds(Long taskId)
    {
        Set<Long> ids = new HashSet<Long>();
        List<WearWorkTaskMember> rows = memberMapper.selectList(new LambdaQueryWrapper<WearWorkTaskMember>()
                .eq(WearWorkTaskMember::getTaskId, taskId));
        for (WearWorkTaskMember row : rows)
        {
            ids.add(row.getPersonId());
        }
        return ids;
    }

    private WorkTaskDto toDto(WearWorkTask row, boolean detail)
    {
        WorkTaskDto dto = new WorkTaskDto();
        dto.setId(strId(row.getId()));
        dto.setSiteId(strId(row.getSiteId()));
        dto.setTitle(row.getTitle());
        dto.setWorkType(row.getWorkType());
        dto.setSpaceId(strId(row.getSpaceId()));
        if (row.getSpaceId() != null)
        {
            WearSpace space = spaceMapper.selectById(row.getSpaceId());
            dto.setSpaceName(space == null ? null : space.getName());
        }
        dto.setPlannedStart(row.getPlannedStart());
        dto.setPlannedEnd(row.getPlannedEnd());
        dto.setActualStart(row.getActualStart());
        dto.setActualEnd(row.getActualEnd());
        dto.setStatus(row.getStatus());
        int reports = inspectionDb.queryForObject("SELECT COUNT(*) FROM wear_inspection_report WHERE task_id=?", Integer.class, row.getId());
        int remaining = inspectionDb.queryForObject("SELECT COUNT(*) FROM wear_inspection_item i WHERE task_id=? AND NOT EXISTS(SELECT 1 FROM wear_inspection_record r WHERE r.task_id=i.task_id AND r.item_id=i.id)", Integer.class, row.getId());
        int items = inspectionDb.queryForObject("SELECT COUNT(*) FROM wear_inspection_item WHERE task_id=?", Integer.class, row.getId());
        dto.setInspectionStatus(reports > 0 ? "abnormal" : "ended".equals(row.getStatus()) || (items > 0 && remaining == 0) ? "completed" : "in_progress");
        dto.setOwnerUserId(strId(row.getOwnerUserId()));
        dto.setGuardianPersonId(strId(row.getGuardianPersonId()));
        dto.setTicketRequired(row.getTicketRequired() != null && row.getTicketRequired().intValue() == 1);
        dto.setTicketNo(row.getTicketNo());
        dto.setTicketStatus(row.getTicketStatus());
        dto.setDemo(row.getDemo() != null && row.getDemo().intValue() == 1);
        dto.setVersion(row.getVersion());
        List<WorkMemberDto> members = new ArrayList<WorkMemberDto>();
        List<WearWorkTaskMember> memberRows = memberMapper.selectList(new LambdaQueryWrapper<WearWorkTaskMember>()
                .eq(WearWorkTaskMember::getTaskId, row.getId()));
        for (WearWorkTaskMember member : memberRows)
        {
            WorkMemberDto item = new WorkMemberDto();
            item.setPersonId(strId(member.getPersonId()));
            WearPerson person = personMapper.selectById(member.getPersonId());
            if (person != null)
            {
                item.setPersonCode(person.getPersonCode());
                item.setName(person.getName());
            }
            members.add(item);
        }
        dto.setMembers(members);
        List<String> reqs = new ArrayList<String>();
        List<WearWorkTaskRequirement> reqRows = requirementMapper.selectList(new LambdaQueryWrapper<WearWorkTaskRequirement>()
                .eq(WearWorkTaskRequirement::getTaskId, row.getId()));
        for (WearWorkTaskRequirement req : reqRows)
        {
            reqs.add(req.getTypeCode());
        }
        dto.setRequirements(reqs);
        if (detail)
        {
            dto.setEquipmentCheck(buildEquipmentCheck(row));
        }
        return dto;
    }

    private void insertAction(Long taskId, String action, String actor, String reason, String from, String to)
    {
        WearWorkTaskAction row = new WearWorkTaskAction();
        row.setTaskId(taskId);
        row.setAction(action);
        row.setActor(actor);
        row.setReason(reason);
        row.setFromStatus(from);
        row.setToStatus(to);
        row.setCreateTime(new Date());
        actionMapper.insert(row);
    }

    private void requireVersion(Integer version)
    {
        if (version == null)
        {
            throw new ServiceException("version 不能为空", HttpStatus.BAD_REQUEST);
        }
    }

    private static String strId(Long id)
    {
        return id == null ? null : String.valueOf(id);
    }

    private static String str(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null)
        {
            return null;
        }
        String value = String.valueOf(body.get(key));
        return "null".equals(value) ? null : value;
    }

    private static boolean bool(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null)
        {
            return false;
        }
        Object raw = body.get(key);
        if (raw instanceof Boolean)
        {
            return ((Boolean) raw).booleanValue();
        }
        return "true".equalsIgnoreCase(String.valueOf(raw)) || "1".equals(String.valueOf(raw));
    }

    private static Integer intVal(Map<String, Object> body, String key)
    {
        if (body == null || body.get(key) == null || String.valueOf(body.get(key)).trim().isEmpty())
        {
            return null;
        }
        try
        {
            return Integer.valueOf(String.valueOf(body.get(key)));
        }
        catch (NumberFormatException ex)
        {
            return null;
        }
    }

    private static Long parseLong(String raw)
    {
        if (StringUtils.isEmpty(raw))
        {
            return null;
        }
        try
        {
            return Long.valueOf(raw.trim());
        }
        catch (NumberFormatException ex)
        {
            return null;
        }
    }

    private static List<Long> longList(Map<String, Object> body, String key)
    {
        List<Long> ids = new ArrayList<Long>();
        if (body == null || !(body.get(key) instanceof List))
        {
            return ids;
        }
        for (Object item : (List<?>) body.get(key))
        {
            Long id = parseLong(item == null ? null : String.valueOf(item));
            if (id != null)
            {
                ids.add(id);
            }
        }
        return ids;
    }

    private static List<String> stringList(Map<String, Object> body, String key)
    {
        List<String> values = new ArrayList<String>();
        if (body == null || !(body.get(key) instanceof List))
        {
            return values;
        }
        for (Object item : (List<?>) body.get(key))
        {
            if (item != null)
            {
                values.add(String.valueOf(item));
            }
        }
        return values;
    }

    private Date parseTime(String raw, boolean required)
    {
        if (StringUtils.isEmpty(raw))
        {
            if (required)
            {
                throw new ServiceException("时间不能为空", HttpStatus.BAD_REQUEST);
            }
            return null;
        }
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
            throw new ServiceException("时间格式无效", HttpStatus.BAD_REQUEST);
        }
    }
}
