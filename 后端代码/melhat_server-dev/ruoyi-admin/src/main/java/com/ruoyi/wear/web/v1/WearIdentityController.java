package com.ruoyi.wear.web.v1;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.framework.web.service.TokenService;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.auth.dto.MeDto;
import com.ruoyi.wear.auth.dto.SelectSiteRequest;
import com.ruoyi.wear.auth.dto.SiteDto;
import com.ruoyi.wear.site.domain.WearSite;

@RestController
@RequestMapping("/api/v1")
public class WearIdentityController
{
    @Autowired
    private SiteAccessService siteAccessService;

    @Autowired
    private TokenService tokenService;

    @GetMapping("/me")
    public R<MeDto> me()
    {
        LoginUser loginUser = siteAccessService.requireLogin();
        SysUser sysUser = loginUser.getUser();
        MeDto dto = new MeDto();
        dto.setUserId(loginUser.getUserId() == null ? null : String.valueOf(loginUser.getUserId()));
        dto.setUserName(sysUser == null ? null : sysUser.getUserName());
        dto.setNickName(sysUser == null ? null : sysUser.getNickName());
        dto.setStatus(sysUser == null ? null : sysUser.getStatus());
        dto.setAdmin(siteAccessService.isPlatformAdmin(loginUser));
        dto.setRoles(siteAccessService.roleKeys(loginUser));
        dto.setPermissions(siteAccessService.permissions());
        List<SiteDto> sites = toDtos(siteAccessService.authorizedSites());
        dto.setAuthorizedSites(sites);
        Long current = siteAccessService.resolveRequestSiteId();
        dto.setCurrentSiteId(current == null ? null : String.valueOf(current));
        return R.ok(dto);
    }

    @GetMapping("/sites")
    public R<List<SiteDto>> sites()
    {
        return R.ok(toDtos(siteAccessService.authorizedSites()));
    }

    @PutMapping("/me/current-site")
    public R<Map<String, String>> selectCurrentSite(@RequestBody SelectSiteRequest request)
    {
        Long siteId = siteAccessService.parseSiteId(request == null ? null : request.getSiteId());
        siteAccessService.assertAuthorized(siteId);
        LoginUser loginUser = siteAccessService.requireLogin();
        loginUser.setCurrentSiteId(siteId);
        loginUser.setAuthorizedSiteIds(siteAccessService.authorizedSiteIds());
        tokenService.setLoginUser(loginUser);
        Map<String, String> data = new HashMap<String, String>();
        data.put("currentSiteId", String.valueOf(siteId));
        return R.ok(data);
    }

    private List<SiteDto> toDtos(List<WearSite> sites)
    {
        List<SiteDto> result = new ArrayList<SiteDto>();
        for (WearSite site : sites)
        {
            result.add(SiteDto.from(site));
        }
        return result;
    }
}
