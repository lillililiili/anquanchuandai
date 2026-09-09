package com.ruoyi.melhat;

import com.ruoyi.wear.work.EventTaskMatcher;
import com.ruoyi.wear.work.WorkTaskStateMachine;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class EventTaskMatchTest {

    @Test
    void zeroOneManyMatches() {
        Date now = new Date();
        EventTaskMatcher.Candidate a = candidate(1L, now, 3600_000L);
        EventTaskMatcher.Candidate b = candidate(2L, now, 3600_000L);
        assertEquals(WorkTaskStateMachine.MATCH_NONE, EventTaskMatcher.match(9L, now, Collections.singletonList(a)).match);
        EventTaskMatcher.Result one = EventTaskMatcher.match(1L, now, Collections.singletonList(a));
        assertEquals(WorkTaskStateMachine.MATCHED, one.match);
        assertEquals(Long.valueOf(1L), one.taskId);
        EventTaskMatcher.Result many = EventTaskMatcher.match(1L, now, Arrays.asList(a, b));
        assertEquals(WorkTaskStateMachine.PENDING, many.match);
        assertNull(many.taskId);
    }

    private static EventTaskMatcher.Candidate candidate(Long id, Date now, long windowMs) {
        EventTaskMatcher.Candidate item = new EventTaskMatcher.Candidate();
        item.taskId = id;
        item.status = WorkTaskStateMachine.IN_PROGRESS;
        item.windowStart = new Date(now.getTime() - windowMs);
        item.windowEnd = new Date(now.getTime() + windowMs);
        item.memberIds = new HashSet<Long>(Collections.singletonList(1L));
        return item;
    }
}
