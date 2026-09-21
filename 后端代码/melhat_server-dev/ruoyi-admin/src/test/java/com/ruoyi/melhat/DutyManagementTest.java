package com.ruoyi.melhat;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import org.apache.ibatis.builder.MapperBuilderAssistant;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.system.service.*;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
import com.ruoyi.wear.work.*;
import com.ruoyi.wear.work.domain.WearDutyHandover;
import com.ruoyi.wear.work.mapper.WearDutyHandoverMapper;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.junit.jupiter.api.Assertions.*;

class DutyManagementTest
{
    DutyService service = new DutyService();
    SiteAccessService access = mock(SiteAccessService.class);
    DutyLedgerService ledger = mock(DutyLedgerService.class);
    WearDutyHandoverMapper handovers = mock(WearDutyHandoverMapper.class);
    WearSiteAccountMapper grants = mock(WearSiteAccountMapper.class);
    ISysUserService users = mock(ISysUserService.class);
    ISysRoleService roles = mock(ISysRoleService.class);
    LoginUser actor;
    WearDutyHandover row;

    @BeforeEach void setup()
    {
        for (Class<?> type : Arrays.asList(WearDutyHandover.class, WearSiteAccount.class))
            TableInfoHelper.initTableInfo(new MapperBuilderAssistant(new MybatisConfiguration(), ""), type);
        ReflectionTestUtils.setField(service,"siteAccessService",access);
        ReflectionTestUtils.setField(service,"ledger",ledger);
        ReflectionTestUtils.setField(service,"handoverMapper",handovers);
        ReflectionTestUtils.setField(service,"siteAccountMapper",grants);
        ReflectionTestUtils.setField(service,"userService",users);
        ReflectionTestUtils.setField(service,"roleService",roles);
        SysUser user = user(12L); actor = new LoginUser(12L,null,user,Collections.emptySet());
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(actor,null,Collections.emptyList()));
        when(access.requireLogin()).thenReturn(actor); when(access.requireCurrentSiteForWrite()).thenReturn(1L);
        row = new WearDutyHandover(); row.setId(9L); row.setSiteId(1L); row.setFromUserId(12L); row.setToUserId(13L); row.setStatus("pending");
        when(handovers.selectById(9L)).thenReturn(row); when(handovers.selectOne(any())).thenReturn(row);
        when(users.selectUserById(anyLong())).thenAnswer(i -> user(i.getArgument(0)));
        when(roles.selectRolePermissionByUserId(anyLong())).thenReturn(Collections.emptySet());
    }
    @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }
    SysUser user(Long id) { SysUser u=new SysUser();u.setUserId(id);u.setUserName(id==1L?"admin":"user"+id);u.setNickName(u.getUserName());u.setStatus("0");u.setDelFlag("0");return u; }
    Map<String,Object> reason() { return Collections.singletonMap("reason","测试取消"); }
    @Test void adminIsCandidateWithoutDutyRoleOrSiteGrant()
    {
        when(grants.selectList(any())).thenReturn(Collections.emptyList());
        assertEquals("admin",service.operators().get(0).get("userName"));
    }
    @Test void disabledAdminIsNotCandidate()
    {
        SysUser disabled=user(1L);disabled.setStatus("1");when(users.selectUserById(1L)).thenReturn(disabled);
        when(grants.selectList(any())).thenReturn(Collections.emptyList());assertTrue(service.operators().isEmpty());
    }
    @Test void senderCanCancelAndAuditWithoutChangingDuty()
    {
        when(handovers.cancelIfPending(9L,"user12")).thenReturn(1);
        service.cancel(9L,reason());verify(ledger).audit(9L,"cancel",12L,"测试取消");
        verify(ledger,never()).change(any(),any(),any(),any(),any(),any(),any());
    }
    @Test void recipientCannotCancelOthersHandover()
    {
        row.setFromUserId(77L);row.setToUserId(12L);
        assertEquals(403,assertThrows(ServiceException.class,()->service.cancel(9L,reason())).getCode());
        verify(handovers,never()).cancelIfPending(any(),any());
    }
    @Test void administratorCanCancelOtherSenders()
    {
        row.setFromUserId(77L);when(access.isPlatformAdmin(actor)).thenReturn(true);
        when(handovers.cancelIfPending(any(),any())).thenReturn(1);service.cancel(9L,reason());verify(ledger).audit(9L,"cancel",12L,"测试取消");
    }
    @Test void confirmedOrConcurrentCancellationReturnsConflict()
    {
        when(handovers.cancelIfPending(any(),any())).thenReturn(0);
        assertEquals(409,assertThrows(ServiceException.class,()->service.cancel(9L,reason())).getCode());
        verify(ledger,never()).audit(any(),any(),any(),any());
    }
    @Test void otherSiteCancellationRejectedBeforeMutation()
    {
        doThrow(new ServiceException("forbidden",403)).when(access).assertAuthorized(1L);
        assertThrows(ServiceException.class,()->service.cancel(9L,reason()));verifyNoInteractions(ledger);
    }
    @Test void takeoverRequiresAdministrator()
    {
        assertEquals(403,assertThrows(ServiceException.class,()->service.takeover(reason())).getCode());verifyNoInteractions(ledger);
    }
    @Test void staleTakeoverCannotOverwriteNewDuty()
    {
        when(access.isPlatformAdmin(actor)).thenReturn(true);when(ledger.lock(1L)).thenReturn(88L);
        Map<String,Object> body=new HashMap<>(reason());body.put("expectedShiftId",87L);
        assertEquals(409,assertThrows(ServiceException.class,()->service.takeover(body)).getCode());verify(handovers,never()).insert(any());
    }
    @Test void oldSenderCannotConfirmAfterTakeover()
    {
        row.setFromUserId(77L);row.setToUserId(12L);when(grants.selectCount(any())).thenReturn(1);
        when(roles.selectRolePermissionByUserId(12L)).thenReturn(Collections.singleton("wear_duty"));
        when(ledger.currentLocked(1L)).thenReturn(Collections.singletonMap("userId","1"));
        assertEquals(409,assertThrows(ServiceException.class,()->service.confirm(9L)).getCode());
        verify(handovers,never()).confirmIfPending(any(),any(),any());
    }
}
