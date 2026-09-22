package com.ruoyi.melhat;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.system.service.ISysUserService;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.person.AccountRecoveryService;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class AccountRecoveryTest {
    private final AccountRecoveryService service = new AccountRecoveryService();
    private final JdbcTemplate db = mock(JdbcTemplate.class);
    private final SiteAccessService access = mock(SiteAccessService.class);
    private final ISysUserService users = mock(ISysUserService.class);
    private final RedisCache redis = mock(RedisCache.class);
    private final LoginUser admin = new LoginUser();
    @BeforeEach void setup() {
        ReflectionTestUtils.setField(service,"db",db); ReflectionTestUtils.setField(service,"access",access);
        ReflectionTestUtils.setField(service,"users",users); ReflectionTestUtils.setField(service,"redis",redis);
        admin.setUserId(1L); when(access.requireLogin()).thenReturn(admin); when(access.isPlatformAdmin(admin)).thenReturn(true);
        when(db.queryForList(contains("FOR UPDATE"), eq("ticket"))).thenReturn(Collections.singletonList(Collections.singletonMap("status","pending")));
    }
    @Test void nonAdminCannotReadOrDecide() {
        when(access.isPlatformAdmin(admin)).thenReturn(false);
        assertThrows(ServiceException.class, () -> service.page(1,20,"pending"));
        assertThrows(ServiceException.class, () -> service.review("ticket",false,Collections.singletonMap("reason","reject")));
        verifyNoInteractions(db,users,redis);
    }
    @Test void alreadyReviewedCannotResetAgain() {
        when(db.queryForList(contains("FOR UPDATE"), eq("ticket"))).thenReturn(Collections.singletonList(Collections.singletonMap("status","approved")));
        assertThrows(ServiceException.class, () -> service.review("ticket",true,approval()));
        verifyNoInteractions(users,redis);
    }
    @Test void rejectNeverChangesPassword() {
        service.review("ticket",false,Collections.singletonMap("reason","身份无法核实"));
        verify(db).update(contains("UPDATE wear_account_recovery"), eq("rejected"), isNull(), eq(1L), eq("身份无法核实"), eq("ticket"));
        verifyNoInteractions(users,redis);
    }
    @Test void rootAccountCannotBeResetThroughRecovery() {
        SysUser root = new SysUser(); root.setUserId(1L); when(users.selectUserById(10L)).thenReturn(root);
        assertThrows(ServiceException.class, () -> service.review("ticket",true,approval()));
        verify(users,never()).resetUserPwd(anyString(),anyString());
    }
    @Test void approvalHashesAndRevokesOnlyTargetSessionsAfterCommit() {
        SysUser target = new SysUser(); target.setUserId(10L); target.setUserName("test"); target.setStatus("0"); target.setDelFlag("0");
        when(users.selectUserById(10L)).thenReturn(target);
        when(users.resetUserPwd(eq("test"), anyString())).thenAnswer(call -> { assertTrue(SecurityUtils.matchesPassword("NewTest123",call.getArgument(1))); return 1; });
        when(redis.keys(anyString())).thenReturn(Arrays.asList("own","other"));
        LoginUser own = new LoginUser(); own.setUserId(10L);
        when(redis.getCacheObject("own")).thenReturn(own); when(redis.getCacheObject("other")).thenReturn(admin);
        TransactionSynchronizationManager.initSynchronization();
        try {
            service.review("ticket",true,approval()); verifyNoInteractions(redis);
            TransactionSynchronizationManager.getSynchronizations().forEach(s -> s.afterCommit());
            verify(redis).deleteObject("own"); verify(redis,never()).deleteObject("other");
        } finally { TransactionSynchronizationManager.clearSynchronization(); }
    }
    private Map<String,Object> approval() {
        Map<String,Object> body = new HashMap<>(); body.put("reason","verified"); body.put("targetUserId",10L); body.put("newPassword","NewTest123"); return body;
    }
}
