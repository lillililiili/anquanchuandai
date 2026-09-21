package com.ruoyi.wear.work;

import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;

/** Station lock serializes confirmation, cancellation and takeover in one transaction. */
@Service
public class DutyLedgerService
{
    @Autowired private JdbcTemplate jdbc;
    @Autowired private SiteAccessService access;

    public Long lock(Long siteId)
    {
        jdbc.update("INSERT IGNORE INTO wear_duty_station(site_id) VALUES (?)", siteId);
        return jdbc.queryForObject("SELECT current_shift_id FROM wear_duty_station WHERE site_id=? FOR UPDATE", Long.class, siteId);
    }

    public Map<String,Object> current(Long siteId)
    {
        return current(siteId, false);
    }

    public Map<String,Object> currentLocked(Long siteId)
    {
        return current(siteId, true);
    }

    private Map<String,Object> current(Long siteId, boolean locked)
    {
        List<Map<String,Object>> rows = jdbc.queryForList("SELECT d.*,u.nick_name,u.user_name FROM wear_duty_station s "
                + "JOIN wear_duty_shift d ON d.id=s.current_shift_id LEFT JOIN sys_user u ON u.user_id=d.user_id WHERE s.site_id=?" + (locked ? " FOR UPDATE" : ""), siteId);
        return rows.isEmpty() ? null : view(rows.get(0));
    }

    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    public Map<String,Object> page(int current, int size)
    {
        Long siteId = access.requireCurrentSiteForWrite();
        if (current < 1 || size < 1 || size > 100) throw new ServiceException("分页参数无效", HttpStatus.BAD_REQUEST);
        Map<String,Object> result = new LinkedHashMap<>();
        List<Map<String,Object>> rows = jdbc.queryForList("SELECT d.*,u.nick_name,u.user_name FROM wear_duty_shift d "
                + "LEFT JOIN sys_user u ON u.user_id=d.user_id WHERE d.site_id=? ORDER BY d.started_at DESC,d.id DESC LIMIT ? OFFSET ?",
                siteId, size, ((long) current-1)*size);
        List<Map<String,Object>> records = new ArrayList<>();
        for (Map<String,Object> row : rows) records.add(view(row));
        result.put("records", records);
        result.put("total", jdbc.queryForObject("SELECT COUNT(*) FROM wear_duty_shift WHERE site_id=?", Long.class, siteId));
        result.put("currentDuty", current(siteId));
        result.put("serverTime", iso(new Date()));
        result.put("canTakeover", access.isPlatformAdmin(access.requireLogin()));
        return result;
    }

    public void change(Long siteId, Long expectedShift, Long toUserId, Long handoverId, String type, Long actor, String reason)
    {
        Date now = new Date();
        if (expectedShift != null) jdbc.update("UPDATE wear_duty_shift SET ended_at=? WHERE id=? AND ended_at IS NULL", now, expectedShift);
        jdbc.update("INSERT INTO wear_duty_shift(site_id,user_id,started_at,source_handover_id,change_type,actor_user_id,reason) VALUES (?,?,?,?,?,?,?)",
                siteId, toUserId, now, handoverId, type, actor, reason);
        Long id = jdbc.queryForObject("SELECT id FROM wear_duty_shift WHERE source_handover_id=?", Long.class, handoverId);
        jdbc.update("UPDATE wear_duty_station SET current_shift_id=? WHERE site_id=?", id, siteId);
    }

    public void audit(Long handoverId, String action, Long actor, String reason)
    {
        jdbc.update("INSERT INTO wear_duty_handover_audit(handover_id,action,actor_user_id,acted_at,reason) VALUES (?,?,?,NOW(),?)",
                handoverId, action, actor, reason);
    }

    public Map<String,Object> auditOf(Long id)
    {
        List<Map<String,Object>> rows = jdbc.queryForList("SELECT a.*,u.nick_name,u.user_name FROM wear_duty_handover_audit a "
                + "LEFT JOIN sys_user u ON u.user_id=a.actor_user_id WHERE a.handover_id=?", id);
        if (rows.isEmpty()) return null;
        Map<String,Object> row = rows.get(0), out = new LinkedHashMap<>();
        out.put("action", row.get("action")); out.put("actorName", display(row));
        out.put("actedAt", iso(date(row.get("acted_at")))); out.put("reason", row.get("reason"));
        return out;
    }

    private Map<String,Object> view(Map<String,Object> row)
    {
        Map<String,Object> out = new LinkedHashMap<>();
        Date start = date(row.get("started_at")), end = date(row.get("ended_at"));
        out.put("id", String.valueOf(row.get("id"))); out.put("userId", String.valueOf(row.get("user_id")));
        out.put("userName", display(row)); out.put("startedAt", iso(start)); out.put("endedAt", iso(end));
        boolean incomplete = "legacy_incomplete".equals(row.get("change_type"));
        out.put("durationSeconds", incomplete ? null : Math.max(0, ((end == null ? System.currentTimeMillis() : end.getTime()) - start.getTime())/1000));
        out.put("endUnknown", incomplete);
        out.put("changeType", row.get("change_type")); out.put("reason", row.get("reason"));
        out.put("handoverId", String.valueOf(row.get("source_handover_id")));
        return out;
    }

    private String display(Map<String,Object> row)
    {
        Object nick = row.get("nick_name"), name = row.get("user_name");
        String label = nick == null || nick.toString().isEmpty() ? String.valueOf(name) : nick.toString();
        return "admin".equals(name) ? label + "（admin）" : label;
    }
    private String iso(Date date)
    {
        return date == null ? null : DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(date.toInstant().atZone(ZoneId.of("Asia/Shanghai")));
    }

    private Date date(Object value)
    {
        if (value == null) return null;
        if (value instanceof Date) return (Date) value;
        if (value instanceof java.time.LocalDateTime)
            return Date.from(((java.time.LocalDateTime) value).atZone(ZoneId.of("Asia/Shanghai")).toInstant());
        throw new IllegalArgumentException("不支持的值班时间格式");
    }
}
