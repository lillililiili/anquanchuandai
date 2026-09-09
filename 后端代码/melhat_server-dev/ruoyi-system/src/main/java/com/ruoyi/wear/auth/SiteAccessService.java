package com.ruoyi.wear.auth;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import javax.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.constant.WearRoleKeys;
import com.ruoyi.common.core.domain.entity.SysRole;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.ServletUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.site.domain.WearSite;
import com.ruoyi.wear.site.domain.WearSiteAccount;
import com.ruoyi.wear.site.mapper.WearSiteAccountMapper;
import com.ruoyi.wear.site.mapper.WearSiteMapper;

/**
 * Shared site/object checks for list, detail, write, download and later comms.
 */
@Service
public class SiteAccessService
{
    public static final String SITE_HEADER = "X-Site-Id";

    @Autowired
    private WearSiteMapper wearSiteMapper;

    @Autowired
    private WearSiteAccountMapper wearSiteAccountMapper;

    public LoginUser requireLogin()
    {
        try
        {
            return SecurityUtils.getLoginUser();
        }
        catch (Exception ex)
        {
            throw new ServiceException("未登录或登录已过期，请重新登录", HttpStatus.UNAUTHORIZED);
        }
    }

    public Set<String> roleKeys(LoginUser user)
    {
        Set<String> keys = new HashSet<String>();
        SysUser sysUser = user.getUser();
        if (sysUser != null && sysUser.getRoles() != null)
        {
            for (SysRole role : sysUser.getRoles())
            {
                if (role != null && StringUtils.isNotEmpty(role.getRoleKey()))
                {
                    keys.add(role.getRoleKey());
                }
            }
        }
        return keys;
    }

    public boolean isPlatformAdmin(LoginUser user)
    {
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.seesAllSites(roleKeys(user), ruoyiAdmin);
    }

    public boolean canWriteHat()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canWriteHat(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanWriteHat()
    {
        if (!canWriteHat())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canWritePerson()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canWritePerson(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanWritePerson()
    {
        if (!canWritePerson())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canWriteDevice()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canWriteDevice(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanWriteDevice()
    {
        if (!canWriteDevice())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canClaimEvent()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canClaimEvent(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanClaimEvent()
    {
        if (!canClaimEvent())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canReviewEvent()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canReviewEvent(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanReviewEvent()
    {
        if (!canReviewEvent())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canSimulateEvent()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canSimulateEvent(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanSimulateEvent()
    {
        if (!canSimulateEvent())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canStartCall()
    {
        return canClaimEvent();
    }

    public void assertCanStartCall()
    {
        if (!canStartCall())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canSendTts()
    {
        LoginUser user = requireLogin();
        boolean ruoyiAdmin = user.getUser() != null && user.getUser().isAdmin();
        return WearRoleKeys.canSendTts(roleKeys(user), ruoyiAdmin);
    }

    public void assertCanSendTts()
    {
        if (!canSendTts())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public boolean canEditTask()
    {
        return canClaimEvent();
    }

    public void assertCanEditTask()
    {
        if (!canEditTask())
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public List<WearSite> authorizedSites()
    {
        LoginUser user = requireLogin();
        LambdaQueryWrapper<WearSite> query = new LambdaQueryWrapper<WearSite>()
                .eq(WearSite::getStatus, "0")
                .orderByAsc(WearSite::getId);
        if (isPlatformAdmin(user))
        {
            return wearSiteMapper.selectList(query);
        }
        List<WearSiteAccount> grants = wearSiteAccountMapper.selectList(new LambdaQueryWrapper<WearSiteAccount>()
                .eq(WearSiteAccount::getUserId, user.getUserId())
                .eq(WearSiteAccount::getStatus, "0"));
        if (grants.isEmpty())
        {
            return Collections.emptyList();
        }
        List<Long> ids = grants.stream().map(WearSiteAccount::getSiteId).collect(Collectors.toList());
        query.in(WearSite::getId, ids);
        return wearSiteMapper.selectList(query);
    }

    public List<Long> authorizedSiteIds()
    {
        List<Long> ids = new ArrayList<Long>();
        for (WearSite site : authorizedSites())
        {
            ids.add(site.getId());
        }
        return ids;
    }

    public void assertAuthorized(Long siteId)
    {
        if (siteId == null || !authorizedSiteIds().contains(siteId))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public Long resolveRequestSiteId()
    {
        LoginUser user = requireLogin();
        List<Long> allowed = authorizedSiteIds();
        Long headerId = headerSiteId();
        if (headerId != null)
        {
            if (!allowed.contains(headerId))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            return headerId;
        }
        if (user.getCurrentSiteId() != null)
        {
            if (!allowed.contains(user.getCurrentSiteId()))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            return user.getCurrentSiteId();
        }
        if (allowed.size() == 1)
        {
            return allowed.get(0);
        }
        return null;
    }

    public Long requireCurrentSiteForWrite()
    {
        Long siteId = resolveRequestSiteId();
        if (siteId == null)
        {
            throw new ServiceException("请选择厂站", HttpStatus.BAD_REQUEST);
        }
        return siteId;
    }

    public List<Long> listScopeSiteIds()
    {
        Long current = resolveRequestSiteId();
        if (current != null)
        {
            return Collections.singletonList(current);
        }
        return authorizedSiteIds();
    }

    public void assertHatReadable(SafetyHatInfo hat)
    {
        if (hat == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        LoginUser user = requireLogin();
        if (hat.getSiteId() == null)
        {
            if (!isPlatformAdmin(user))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            return;
        }
        if (!listScopeSiteIds().contains(hat.getSiteId()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public void assertDeviceReadable(WearDevice device)
    {
        if (device == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        LoginUser user = requireLogin();
        if (device.getSiteId() == null)
        {
            if (!isPlatformAdmin(user))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            return;
        }
        if (!listScopeSiteIds().contains(device.getSiteId()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    public Set<String> permissions()
    {
        Set<String> perms = new LinkedHashSet<String>();
        perms.add(WearRoleKeys.PERM_SITE_LIST);
        perms.add(WearRoleKeys.PERM_SITE_SELECT);
        perms.add(WearRoleKeys.PERM_HAT_LIST);
        perms.add(WearRoleKeys.PERM_HAT_QUERY);
        perms.add(WearRoleKeys.PERM_PERSON_LIST);
        perms.add(WearRoleKeys.PERM_PERSON_QUERY);
        perms.add(WearRoleKeys.PERM_SPACE_LIST);
        perms.add(WearRoleKeys.PERM_DEVICE_LIST);
        perms.add(WearRoleKeys.PERM_DEVICE_QUERY);
        perms.add(WearRoleKeys.PERM_MODEL_LIST);
        perms.add(WearRoleKeys.PERM_ASSIGNMENT_LIST);
        perms.add(WearRoleKeys.PERM_ASSIGNMENT_QUERY);
        perms.add(WearRoleKeys.PERM_EVENT_LIST);
        perms.add(WearRoleKeys.PERM_EVENT_QUERY);
        perms.add(WearRoleKeys.PERM_CALL_LIST);
        perms.add(WearRoleKeys.PERM_CALL_QUERY);
        perms.add(WearRoleKeys.PERM_TASK_LIST);
        perms.add(WearRoleKeys.PERM_TASK_QUERY);
        perms.add(WearRoleKeys.PERM_DUTY_QUERY);
        perms.add(WearRoleKeys.PERM_LOCATION_LIST);
        perms.add(WearRoleKeys.PERM_LOCATION_QUERY);
        perms.add(WearRoleKeys.PERM_FENCE_LIST);
        perms.add(WearRoleKeys.PERM_FENCE_QUERY);
        if (canClaimEvent())
        {
            perms.add(WearRoleKeys.PERM_EVENT_CLAIM);
            perms.add(WearRoleKeys.PERM_CALL_START);
            perms.add(WearRoleKeys.PERM_TASK_EDIT);
            perms.add(WearRoleKeys.PERM_DUTY_HANDOVER);
        }
        if (canReviewEvent())
        {
            perms.add(WearRoleKeys.PERM_EVENT_REVIEW);
        }
        if (canWriteHat())
        {
            perms.add(WearRoleKeys.PERM_HAT_EDIT);
        }
        if (canWritePerson())
        {
            perms.add(WearRoleKeys.PERM_PERSON_EDIT);
            perms.add(WearRoleKeys.PERM_SPACE_EDIT);
            perms.add(WearRoleKeys.PERM_TEAM_EDIT);
            perms.add(WearRoleKeys.PERM_CONTRACTOR_EDIT);
        }
        if (canWriteDevice())
        {
            perms.add(WearRoleKeys.PERM_DEVICE_EDIT);
            perms.add(WearRoleKeys.PERM_MODEL_EDIT);
            perms.add(WearRoleKeys.PERM_ASSIGNMENT_ISSUE);
            perms.add(WearRoleKeys.PERM_FENCE_EDIT);
        }
        if (canSendTts())
        {
            perms.add(WearRoleKeys.PERM_COMMAND_TTS);
        }
        return perms;
    }

    public Long parseSiteId(String raw)
    {
        if (StringUtils.isEmpty(raw))
        {
            throw new ServiceException("请选择厂站", HttpStatus.BAD_REQUEST);
        }
        try
        {
            return Long.valueOf(raw.trim());
        }
        catch (NumberFormatException ex)
        {
            throw new ServiceException("请选择厂站", HttpStatus.BAD_REQUEST);
        }
    }

    private Long headerSiteId()
    {
        try
        {
            HttpServletRequest request = ServletUtils.getRequest();
            if (request == null)
            {
                return null;
            }
            String raw = request.getHeader(SITE_HEADER);
            if (StringUtils.isEmpty(raw))
            {
                return null;
            }
            return parseSiteId(raw);
        }
        catch (ServiceException ex)
        {
            throw ex;
        }
        catch (Exception ex)
        {
            return null;
        }
    }
}
