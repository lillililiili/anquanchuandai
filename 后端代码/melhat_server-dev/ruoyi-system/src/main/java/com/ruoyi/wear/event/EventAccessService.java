package com.ruoyi.wear.event;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.event.domain.WearSafetyEvent;
import com.ruoyi.wear.event.mapper.WearSafetyEventMapper;

/** One scope for lists, details, commands, counters and notification recipients. */
@Service
public class EventAccessService {
    @Autowired private SiteAccessService sites;
    @Autowired private WearSafetyEventMapper events;
    @Autowired private JdbcTemplate db;

    public LambdaQueryWrapper<WearSafetyEvent> scope(LambdaQueryWrapper<WearSafetyEvent> query) {
        return scope(query, sites.requireLogin().getUserId(), sites.isPlatformAdmin(sites.requireLogin()));
    }

    public LambdaQueryWrapper<WearSafetyEvent> actionable(LambdaQueryWrapper<WearSafetyEvent> query) {
        query.ne(WearSafetyEvent::getStatus, EventStateMachine.CLOSED);
        // Pending emergency approval remains visible to its group until the workflow ends.
        return query;
    }

    private LambdaQueryWrapper<WearSafetyEvent> scope(LambdaQueryWrapper<WearSafetyEvent> query,
            Long userId, boolean admin) {
        String reminder = EventReminderPolicy.SQL;
        String own = "person_id IN (SELECT p.id FROM wear_person p WHERE p.account_user_id={0} "
                + "AND p.status='0' AND p.del_flag='0')";
        // Only currently running groups grant access to their members' safety events.
        // An event's task match may be missing or refer to another task; it does not grant access.
        String group = "EXISTS (SELECT 1 FROM wear_work_task t "
                + "JOIN wear_work_task_member visible_member ON visible_member.task_id=t.id "
                + "WHERE t.site_id=wear_safety_event.site_id "
                + "AND t.status='in_progress' "
                // Inspection completion can precede the work task's explicit end action.
                + "AND (COALESCE(t.work_type,'')<>'patrol' "
                + "OR NOT EXISTS (SELECT 1 FROM wear_inspection_item i WHERE i.task_id=t.id) "
                + "OR EXISTS (SELECT 1 FROM wear_inspection_item i WHERE i.task_id=t.id "
                + "AND NOT EXISTS (SELECT 1 FROM wear_inspection_record r "
                + "WHERE r.task_id=i.task_id AND r.item_id=i.id))) "
                + "AND visible_member.person_id=wear_safety_event.person_id AND (t.owner_user_id={0} OR "
                + "t.guardian_person_id IN (SELECT p.id FROM wear_person p WHERE p.account_user_id={0} "
                + "AND p.status='0' AND p.del_flag='0') OR t.id IN (SELECT m.task_id FROM wear_work_task_member m "
                + "JOIN wear_person p ON p.id=m.person_id WHERE p.account_user_id={0} "
                + "AND p.status='0' AND p.del_flag='0')))";
        query.apply("(TRIM(COALESCE(alarm_name,''))<>'' OR TRIM(COALESCE(alarm_code,''))<>'') AND COALESCE(alarm_name,'')<>'告警名称未提供'");
        String manual = "(COALESCE(source,'')='manual_sos' AND event_type='sos')";
        return query.apply("((" + manual + (admin ? "" : " AND reporter_user_id={0}")
                + ") OR (NOT " + manual + " AND ((" + reminder + " AND " + own + ") OR (NOT " + reminder
                + (admin ? "" : " AND " + group) + "))))", userId);
    }

    public void assertReadable(WearSafetyEvent event) {
        if (!sites.listScopeSiteIds().contains(event.getSiteId())
                || events.selectCount(scope(new LambdaQueryWrapper<WearSafetyEvent>()
                        .eq(WearSafetyEvent::getId, event.getId()))) == 0) {
            throw new ServiceException("只能查看所属作业组内人员的告警和本人的设备提醒", HttpStatus.FORBIDDEN);
        }
    }

    public List<Long> recipients(WearSafetyEvent event) {
        if (EventStateMachine.CLOSED.equals(event.getStatus())) return new java.util.ArrayList<>();
        List<Long> users = db.queryForList("SELECT DISTINCT u.user_id FROM sys_user u WHERE u.status='0' "
                + "AND u.del_flag='0' AND (u.user_id=1 OR u.user_id IN (SELECT a.user_id FROM wear_site_account a "
                + "WHERE a.site_id=? AND a.status='0') OR u.user_id IN (SELECT ur.user_id FROM sys_user_role ur "
                + "JOIN sys_role r ON r.role_id=ur.role_id WHERE r.status='0' AND r.role_key IN ('admin','wear_platform_admin'))) ",
                Long.class, event.getSiteId());
        users.removeIf(userId -> {
            Integer admins = db.queryForObject("SELECT COUNT(*) FROM sys_user_role ur JOIN sys_role r "
                    + "ON r.role_id=ur.role_id WHERE ur.user_id=? AND r.status='0' "
                    + "AND r.role_key IN ('admin','wear_platform_admin')", Integer.class, userId);
            boolean admin = userId == 1L || (admins != null && admins > 0);
            if(admin && !EventSeverityPolicy.isEmergency(event) && !EventReminderPolicy.isReminder(event)) return true;
            // Group submission is stage one; approval notifications go to administrators.
            if (EventStateMachine.PENDING_REVIEW.equals(event.getStatus()) && !admin
                    && !(ManualSosService.isManual(event) && userId.equals(event.getReporterUserId()))) return true;
            return events.selectCount(scope(new LambdaQueryWrapper<WearSafetyEvent>()
                    .eq(WearSafetyEvent::getId, event.getId()), userId, admin)) == 0;
        });
        return users;
    }
}
