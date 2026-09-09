package com.ruoyi.melhat;

import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.framework.web.service.SysLoginService;
import com.ruoyi.framework.web.service.SysPermissionService;
import com.ruoyi.system.service.ISysMenuService;
import com.ruoyi.web.controller.system.SysLoginController;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Collections;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup;

@ExtendWith(MockitoExtension.class)
class SysLoginControllerGetInfoTest {

    private static final String SECRET = "hashed-secret-should-not-leak";

    @Mock
    private SysLoginService loginService;

    @Mock
    private ISysMenuService menuService;

    @Mock
    private SysPermissionService permissionService;

    @InjectMocks
    private SysLoginController controller;

    @AfterEach
    void clearSecurity() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void getInfoHttpBodyDoesNotContainPassword() throws Exception {
        SysUser user = new SysUser();
        user.setUserId(1L);
        user.setUserName("admin");
        user.setPassword(SECRET);
        LoginUser loginUser = new LoginUser(1L, 100L, user, Collections.singleton("system:user:list"));
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(loginUser, null, Collections.emptyList()));
        when(permissionService.getRolePermission(any(SysUser.class))).thenReturn(Collections.singleton("admin"));
        when(permissionService.getMenuPermission(any(SysUser.class))).thenReturn(Collections.singleton("system:user:list"));

        MockMvc mockMvc = standaloneSetup(controller).build();
        mockMvc.perform(get("/getInfo"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.userName").value("admin"))
                .andExpect(jsonPath("$.user.password").doesNotExist())
                .andExpect(content().string(not(containsString(SECRET))))
                .andExpect(content().string(not(containsString("\"password\""))));
    }
}
