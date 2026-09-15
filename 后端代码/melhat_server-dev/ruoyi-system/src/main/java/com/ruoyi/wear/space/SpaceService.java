package com.ruoyi.wear.space;

import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.space.domain.WearSpace;
import com.ruoyi.wear.space.mapper.WearSpaceMapper;

@Service
public class SpaceService
{
    @Autowired
    private WearSpaceMapper spaceMapper;
    @Autowired
    private SiteAccessService siteAccessService;

    public List<Map<String, String>> list(String siteId, String status)
    {
        Long sid = siteId == null ? siteAccessService.resolveRequestSiteId() : siteAccessService.parseSiteId(siteId);
        if (sid == null)
        {
            List<Long> scope = siteAccessService.listScopeSiteIds();
            if (scope.isEmpty())
            {
                return new ArrayList<Map<String, String>>();
            }
            sid = scope.get(0);
        }
        siteAccessService.assertAuthorized(sid);
        LambdaQueryWrapper<WearSpace> query = new LambdaQueryWrapper<WearSpace>()
                .eq(WearSpace::getSiteId, sid).orderByAsc(WearSpace::getId);
        if (!"all".equals(status)) query.eq(WearSpace::getStatus, StringUtils.isEmpty(status) ? "0" : status);
        List<WearSpace> rows = spaceMapper.selectList(query);
        List<Map<String, String>> result = new ArrayList<Map<String, String>>();
        for (WearSpace row : rows)
        {
            result.add(toMap(row));
        }
        return result;
    }

    public Map<String, String> create(String siteId, String parentId, String spaceType, String name)
    {
        siteAccessService.assertCanWritePerson();
        if (StringUtils.isEmpty(name) || StringUtils.isEmpty(spaceType))
        {
            throw new ServiceException("区域名称和类型不能为空", HttpStatus.BAD_REQUEST);
        }
        if (!"area".equals(spaceType) && !"facility".equals(spaceType) && !"floor".equals(spaceType))
        {
            throw new ServiceException("区域类型无效", HttpStatus.BAD_REQUEST);
        }
        Long sid = siteId == null ? siteAccessService.requireCurrentSiteForWrite() : siteAccessService.parseSiteId(siteId);
        siteAccessService.assertAuthorized(sid);
        WearSpace row = new WearSpace();
        row.setSiteId(sid);
        row.setParentId(StringUtils.isEmpty(parentId) ? null : Long.valueOf(parentId));
        row.setSpaceType(spaceType);
        row.setName(name.trim());
        row.setStatus("0");
        row.setVersion(1);
        row.setDelFlag("0");
        row.setCreateBy(SecurityUtils.getUsername());
        row.setCreateTime(new Date());
        spaceMapper.insert(row);
        return toMap(row);
    }

    public Map<String, String> update(Long id, String name, Integer version)
    {
        siteAccessService.assertCanWritePerson();
        WearSpace row = spaceMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(row.getSiteId());
        if (version == null || !version.equals(row.getVersion()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (StringUtils.isNotEmpty(name))
        {
            row.setName(name.trim());
        }
        row.setVersion(row.getVersion() + 1);
        row.setUpdateBy(SecurityUtils.getUsername());
        row.setUpdateTime(new Date());
        spaceMapper.updateById(row);
        return toMap(row);
    }

    public Map<String, String> changeStatus(Long id, String status, Integer version)
    {
        siteAccessService.assertCanWritePerson();
        WearSpace row = spaceMapper.selectById(id);
        if (row == null) throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        siteAccessService.assertAuthorized(row.getSiteId());
        if (version == null || !version.equals(row.getVersion())) throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        if (!"0".equals(status) && !"1".equals(status)) throw new ServiceException("状态无效", HttpStatus.BAD_REQUEST);
        row.setStatus(status);
        row.setVersion(row.getVersion() + 1);
        row.setUpdateBy(SecurityUtils.getUsername()); row.setUpdateTime(new Date());
        spaceMapper.updateById(row);
        return toMap(row);
    }

    private Map<String, String> toMap(WearSpace row)
    {
        Map<String, String> map = new LinkedHashMap<String, String>();
        map.put("id", String.valueOf(row.getId()));
        map.put("siteId", String.valueOf(row.getSiteId()));
        map.put("parentId", row.getParentId() == null ? null : String.valueOf(row.getParentId()));
        map.put("spaceType", row.getSpaceType());
        map.put("name", row.getName());
        map.put("status", row.getStatus());
        map.put("version", String.valueOf(row.getVersion()));
        return map;
    }
}
