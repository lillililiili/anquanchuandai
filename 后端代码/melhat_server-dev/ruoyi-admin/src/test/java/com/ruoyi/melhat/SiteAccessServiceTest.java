package com.ruoyi.melhat;

import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.entity.SysRole;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.site.domain.WearSite;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
import com.ruoyi.wear.site.mapper.WearSiteMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SiteAccessServiceTest {

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void readonlyCannotWriteHatAndCannotReadOtherSite() {
        SiteAccessService service = serviceWithGrant(10L, WearRoleKeysDuty());
        login(20L, "siteA_readonly", "wear_readonly", false);
        ServiceException write = assertThrows(ServiceException.class, service::assertCanWriteHat);
        assertEquals(HttpStatus.FORBIDDEN, write.getCode());

        SafetyHatInfo other = new SafetyHatInfo();
        other.setId(2L);
        other.setSiteId(99L);
        ServiceException read = assertThrows(ServiceException.class, () -> service.assertHatReadable(other));
        assertEquals(HttpStatus.FORBIDDEN, read.getCode());
    }

    @Test
    void dutyCanReadOwnSiteHat() {
        SiteAccessService service = serviceWithGrant(10L, "wear_duty");
        login(21L, "siteA_duty", "wear_duty", false);
        SafetyHatInfo own = new SafetyHatInfo();
        own.setId(1L);
        own.setSiteId(10L);
        service.assertHatReadable(own);
        assertTrue(service.authorizedSiteIds().contains(10L));
    }

    private SiteAccessService serviceWithGrant(Long siteId, String roleKey) {
        WearSiteMapper sites = mock(WearSiteMapper.class);
        WearSiteAccountMapper accounts = mock(WearSiteAccountMapper.class);
        WearSite site = new WearSite();
        site.setId(siteId);
        site.setSiteCode("SITE-DEMO-A");
        site.setStatus("0");
        WearSiteAccount grant = new WearSiteAccount();
        grant.setSiteId(siteId);
        grant.setUserId(21L);
        grant.setStatus("0");
        when(accounts.selectList(any())).thenReturn(Collections.singletonList(grant));
        when(sites.selectList(any())).thenReturn(Collections.singletonList(site));
        SiteAccessService service = new SiteAccessService();
        ReflectionTestUtils.setField(service, "wearSiteMapper", sites);
        ReflectionTestUtils.setField(service, "wearSiteAccountMapper", accounts);
        return service;
    }

    private void login(Long userId, String username, String roleKey, boolean admin) {
        SysUser user = new SysUser();
        user.setUserId(admin ? 1L : userId);
        user.setUserName(username);
        user.setStatus("0");
        SysRole role = new SysRole();
        role.setRoleKey(roleKey);
        user.setRoles(Arrays.asList(role));
        LoginUser loginUser = new LoginUser(user.getUserId(), null, user, Collections.emptySet());
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(loginUser, null, Collections.emptyList()));
    }

    private String WearRoleKeysDuty() {
        return "wear_readonly";
    }
}
