package com.ruoyi.melhat;

import java.time.LocalDateTime;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import com.ruoyi.wear.work.DutyLedgerService;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.junit.jupiter.api.Assertions.*;

class DutyLedgerTest
{
    @Test void mysqlLocalDateTimeIsSerializedWithStationTimezone()
    {
        DutyLedgerService service=new DutyLedgerService(); JdbcTemplate jdbc=mock(JdbcTemplate.class);
        ReflectionTestUtils.setField(service,"jdbc",jdbc);
        Map<String,Object> row=new HashMap<>();row.put("id",1L);row.put("user_id",1L);row.put("user_name","admin");row.put("nick_name","管理员");
        row.put("started_at",LocalDateTime.of(2026,9,21,8,0));row.put("ended_at",LocalDateTime.of(2026,9,21,10,30));row.put("change_type","handover");
        when(jdbc.queryForList(anyString(),eq(1L))).thenReturn(Collections.singletonList(row));
        Map<String,Object> result=service.current(1L);
        assertEquals("2026-09-21T08:00:00+08:00",result.get("startedAt"));assertEquals(9000L,result.get("durationSeconds"));
        row.put("change_type","legacy_incomplete");row.put("ended_at",null);
        result=service.current(1L);assertNull(result.get("durationSeconds"));assertEquals(true,result.get("endUnknown"));
    }
    @Test void auditSupportsDriverLocalDateTime()
    {
        DutyLedgerService service=new DutyLedgerService();JdbcTemplate jdbc=mock(JdbcTemplate.class);ReflectionTestUtils.setField(service,"jdbc",jdbc);
        Map<String,Object> row=new HashMap<>();row.put("acted_at",LocalDateTime.of(2026,9,21,14,0));row.put("action","cancel");row.put("reason","调整");
        when(jdbc.queryForList(anyString(),eq(8L))).thenReturn(Collections.singletonList(row));
        assertEquals("2026-09-21T14:00:00+08:00",service.auditOf(8L).get("actedAt"));
    }
}
