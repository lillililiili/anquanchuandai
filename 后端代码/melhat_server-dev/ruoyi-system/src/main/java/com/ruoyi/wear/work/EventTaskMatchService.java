package com.ruoyi.wear.work;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;
import com.ruoyi.wear.work.domain.WearWorkTask;
import com.ruoyi.wear.work.domain.WearWorkTaskMember;
import com.ruoyi.wear.work.mapper.WearWorkTaskMapper;
import com.ruoyi.wear.work.mapper.WearWorkTaskMemberMapper;

@Service
public class EventTaskMatchService
{
    @Autowired
    private WearWorkTaskMapper taskMapper;
    @Autowired
    private WearWorkTaskMemberMapper memberMapper;
    @Autowired
    private WearSafetyEventMapper eventMapper;

    public void applyOnInsert(WearSafetyEvent row)
    {
        if (row == null || row.getId() == null)
        {
            return;
        }
        EventTaskMatcher.Result result = EventTaskMatcher.match(row.getPersonId(), row.getOccurredAt(), candidates(row.getSiteId()));
        eventMapper.applyMatch(row.getId(), result.taskId, result.match);
        row.setTaskId(result.taskId);
        row.setTaskMatch(result.match);
    }

    public List<EventTaskMatcher.Candidate> candidates(Long siteId)
    {
        List<EventTaskMatcher.Candidate> list = new ArrayList<EventTaskMatcher.Candidate>();
        if (siteId == null)
        {
            return list;
        }
        List<WearWorkTask> tasks = taskMapper.selectList(new LambdaQueryWrapper<WearWorkTask>()
                .eq(WearWorkTask::getSiteId, siteId)
                .in(WearWorkTask::getStatus, WorkTaskStateMachine.IN_PROGRESS, WorkTaskStateMachine.PAUSED));
        for (WearWorkTask task : tasks)
        {
            EventTaskMatcher.Candidate item = new EventTaskMatcher.Candidate();
            item.taskId = task.getId();
            item.status = task.getStatus();
            Date start = task.getActualStart() != null ? task.getActualStart() : task.getPlannedStart();
            Date end = task.getActualEnd() != null ? task.getActualEnd() : task.getPlannedEnd();
            item.windowStart = start;
            item.windowEnd = end;
            item.memberIds = memberIds(task.getId());
            list.add(item);
        }
        return list;
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
}
