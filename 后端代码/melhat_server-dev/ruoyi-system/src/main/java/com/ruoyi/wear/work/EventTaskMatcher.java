package com.ruoyi.wear.work;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Set;

public final class EventTaskMatcher
{
    private EventTaskMatcher()
    {
    }

    public static final class Candidate
    {
        public Long taskId;
        public String status;
        public Date windowStart;
        public Date windowEnd;
        public Set<Long> memberIds;
    }

    public static final class Result
    {
        public final String match;
        public final Long taskId;

        public Result(String match, Long taskId)
        {
            this.match = match;
            this.taskId = taskId;
        }
    }

    public static Result match(Long personId, Date occurredAt, List<Candidate> tasks)
    {
        if (personId == null || occurredAt == null || tasks == null || tasks.isEmpty())
        {
            return new Result(WorkTaskStateMachine.MATCH_NONE, null);
        }
        List<Candidate> hits = new ArrayList<Candidate>();
        for (Candidate task : tasks)
        {
            if (task == null || !WorkTaskStateMachine.isMatchWindow(task.status))
            {
                continue;
            }
            if (task.memberIds == null || !task.memberIds.contains(personId))
            {
                continue;
            }
            if (task.windowStart != null && occurredAt.before(task.windowStart))
            {
                continue;
            }
            if (task.windowEnd != null && occurredAt.after(task.windowEnd))
            {
                continue;
            }
            hits.add(task);
        }
        if (hits.isEmpty())
        {
            return new Result(WorkTaskStateMachine.MATCH_NONE, null);
        }
        if (hits.size() == 1)
        {
            return new Result(WorkTaskStateMachine.MATCHED, hits.get(0).taskId);
        }
        return new Result(WorkTaskStateMachine.PENDING, null);
    }
}
