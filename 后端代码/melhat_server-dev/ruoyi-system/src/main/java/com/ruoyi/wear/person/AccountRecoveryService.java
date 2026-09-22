package com.ruoyi.wear.person;

import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import com.ruoyi.common.constant.CacheConstants;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.system.service.ISysUserService;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;

@Service
public class AccountRecoveryService {
    @Autowired private JdbcTemplate db;
    @Autowired private SiteAccessService access;
    @Autowired private ISysUserService users;
    @Autowired private RedisCache redis;
    private static final String COLUMNS = "id,identifier,real_name AS realName,contact,reason,status,"
        + "target_user_id AS targetUserId,reviewed_by AS reviewedBy,review_reason AS reviewReason,"
        + "DATE_FORMAT(created_at,'%Y-%m-%d %H:%i:%s') AS createdAt,"
        + "DATE_FORMAT(reviewed_at,'%Y-%m-%d %H:%i:%s') AS reviewedAt";

    public Map<String,Object> submit(Map<String,Object> body) {
        String identifier = required(body, "identifier", 100);
        String name = required(body, "realName", 80);
        String contact = required(body, "contact", 100);
        String reason = required(body, "reason", 500);
        String id = UUID.randomUUID().toString();
        db.update("INSERT INTO wear_account_recovery(id,identifier,real_name,contact,reason) VALUES(?,?,?,?,?)",
            id, identifier, name, contact, reason);
        // Deliberately identical for known and unknown identifiers.
        Map<String,Object> result = new LinkedHashMap<>();
        result.put("id", id); result.put("status", "pending");
        return result;
    }

    public WearPage<Map<String,Object>> page(int current, int size, String status) {
        requireAdmin();
        int page = Math.max(1, current), limit = Math.max(1, Math.min(size, 100));
        String value = Arrays.asList("pending", "approved", "rejected").contains(status) ? status : "pending";
        Long total = db.queryForObject("SELECT COUNT(*) FROM wear_account_recovery WHERE status=?", Long.class, value);
        List<Map<String,Object>> rows = db.queryForList("SELECT " + COLUMNS
            + " FROM wear_account_recovery WHERE status=? ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?", value, limit, (page-1)*limit);
        return WearPage.of(rows, total == null ? 0 : total, page, limit);
    }

    public List<Map<String,Object>> accounts(String query) {
        requireAdmin();
        String q = query == null ? "" : query.trim();
        if (q.length() > 100) throw new ServiceException("搜索内容过长", 400);
        return db.queryForList("SELECT u.user_id AS id,u.user_name AS userName,u.nick_name AS nickName,"
            + "p.person_code AS personCode,p.name AS personName FROM sys_user u LEFT JOIN wear_person p "
            + "ON p.account_user_id=u.user_id AND p.del_flag='0' WHERE u.del_flag='0' AND u.status='0' AND u.user_id<>1 "
            + "AND (u.user_name LIKE ? OR u.nick_name LIKE ? OR p.person_code LIKE ?) ORDER BY u.user_id LIMIT 50",
            "%"+q+"%", "%"+q+"%", "%"+q+"%");
    }

    @Transactional(rollbackFor=Exception.class)
    public void review(String id, boolean approve, Map<String,Object> body) {
        LoginUser actor = requireAdmin();
        String reason = required(body, "reason", 500);
        List<Map<String,Object>> rows = db.queryForList("SELECT status FROM wear_account_recovery WHERE id=? FOR UPDATE", id);
        if (rows.isEmpty()) throw new ServiceException("申请不存在", 404);
        if (!"pending".equals(rows.get(0).get("status"))) throw new ServiceException("该申请已处理，请刷新", 409);
        Long target = null;
        if (approve) {
            try { target = Long.valueOf(String.valueOf(body.get("targetUserId"))); }
            catch (RuntimeException ex) { throw new ServiceException("请选择核实后的账号", 400); }
            String password = body.get("newPassword") == null ? "" : String.valueOf(body.get("newPassword"));
            if (password.length() < 8 || password.length() > 20 || !password.matches(".*[A-Za-z].*") || !password.matches(".*[0-9].*"))
                throw new ServiceException("新密码须为 8–20 位，并包含字母和数字", 400);
            SysUser user = users.selectUserById(target);
            if (user == null || user.isAdmin() || !"0".equals(user.getStatus()) || !"0".equals(user.getDelFlag()))
                throw new ServiceException("此账号不支持人员找回重置", 400);
            if (users.resetUserPwd(user.getUserName(), SecurityUtils.encryptPassword(password)) != 1)
                throw new ServiceException("账号已变化，请刷新", 409);
            final Long userId = target;
            // Revoke old sessions only after the password and decision commit together.
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() {
                    for (String key : redis.keys(CacheConstants.LOGIN_TOKEN_KEY + "*")) {
                        LoginUser login = redis.getCacheObject(key);
                        if (login != null && userId.equals(login.getUserId())) redis.deleteObject(key);
                    }
                }
            });
        }
        db.update("UPDATE wear_account_recovery SET status=?,target_user_id=?,reviewed_by=?,review_reason=?,reviewed_at=NOW() WHERE id=?",
            approve ? "approved" : "rejected", target, actor.getUserId(), reason, id);
    }

    private LoginUser requireAdmin() {
        LoginUser user = access.requireLogin();
        if (!access.isPlatformAdmin(user)) throw new ServiceException("仅管理员可审批账号重置", 403);
        return user;
    }
    static String required(Map<String,Object> body, String field, int max) {
        String value = body.get(field) == null ? "" : String.valueOf(body.get(field)).trim();
        if (value.isEmpty() || value.length() > max) throw new ServiceException("请完整填写申请或审批信息，且勿超出长度限制", 400);
        return value;
    }
}
