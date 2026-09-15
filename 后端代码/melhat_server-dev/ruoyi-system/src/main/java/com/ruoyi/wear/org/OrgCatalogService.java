package com.ruoyi.wear.org;

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
import com.ruoyi.wear.org.domain.WearContractor;
import com.ruoyi.wear.org.domain.WearTeam;
import com.ruoyi.wear.org.mapper.WearContractorMapper;
import com.ruoyi.wear.org.mapper.WearTeamMapper;

@Service
public class OrgCatalogService
{
    @Autowired
    private WearTeamMapper teamMapper;
    @Autowired
    private WearContractorMapper contractorMapper;
    @Autowired
    private SiteAccessService siteAccessService;

    public List<Map<String, String>> listTeams(String status)
    {
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty())
        {
            return new ArrayList<Map<String, String>>();
        }
        LambdaQueryWrapper<WearTeam> query = new LambdaQueryWrapper<WearTeam>()
                .in(WearTeam::getSiteId, scope).orderByAsc(WearTeam::getId);
        if (!"all".equals(status)) query.eq(WearTeam::getStatus, StringUtils.isEmpty(status) ? "0" : status);
        List<WearTeam> teams = teamMapper.selectList(query);
        List<Map<String, String>> result = new ArrayList<Map<String, String>>();
        for (WearTeam team : teams)
        {
            result.add(teamMap(team));
        }
        return result;
    }

    public Map<String, String> createTeam(String name, String siteId)
    {
        siteAccessService.assertCanWritePerson();
        if (StringUtils.isEmpty(name))
        {
            throw new ServiceException("班组名称不能为空", HttpStatus.BAD_REQUEST);
        }
        Long sid = siteId == null ? siteAccessService.requireCurrentSiteForWrite() : siteAccessService.parseSiteId(siteId);
        siteAccessService.assertAuthorized(sid);
        WearTeam team = new WearTeam();
        team.setName(name.trim());
        team.setSiteId(sid);
        team.setStatus("0");
        team.setDelFlag("0");
        team.setCreateBy(SecurityUtils.getUsername());
        team.setCreateTime(new Date());
        teamMapper.insert(team);
        return teamMap(team);
    }

    public Map<String, String> updateTeam(Long id, String name, String status)
    {
        siteAccessService.assertCanWritePerson();
        WearTeam team = teamMapper.selectById(id);
        if (team == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        siteAccessService.assertAuthorized(team.getSiteId());
        if (StringUtils.isNotEmpty(name))
        {
            team.setName(name.trim());
        }
        if (StringUtils.isNotEmpty(status))
        {
            if (!"0".equals(status) && !"1".equals(status))
            {
                throw new ServiceException("状态无效", HttpStatus.BAD_REQUEST);
            }
            team.setStatus(status);
        }
        team.setUpdateBy(SecurityUtils.getUsername());
        team.setUpdateTime(new Date());
        teamMapper.updateById(team);
        return teamMap(team);
    }

    public List<Map<String, String>> listContractors(String status)
    {
        siteAccessService.requireLogin();
        LambdaQueryWrapper<WearContractor> query = new LambdaQueryWrapper<WearContractor>().orderByAsc(WearContractor::getId);
        if (!"all".equals(status)) query.eq(WearContractor::getStatus, StringUtils.isEmpty(status) ? "0" : status);
        List<WearContractor> rows = contractorMapper.selectList(query);
        List<Map<String, String>> result = new ArrayList<Map<String, String>>();
        for (WearContractor row : rows)
        {
            result.add(contractorMap(row));
        }
        return result;
    }

    public Map<String, String> createContractor(String name)
    {
        siteAccessService.assertCanWritePerson();
        if (StringUtils.isEmpty(name))
        {
            throw new ServiceException("承包商名称不能为空", HttpStatus.BAD_REQUEST);
        }
        WearContractor row = new WearContractor();
        row.setName(name.trim());
        row.setStatus("0");
        row.setDelFlag("0");
        row.setCreateBy(SecurityUtils.getUsername());
        row.setCreateTime(new Date());
        contractorMapper.insert(row);
        return contractorMap(row);
    }

    public Map<String, String> updateContractor(Long id, String name, String status)
    {
        siteAccessService.assertCanWritePerson();
        WearContractor row = contractorMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        if (StringUtils.isNotEmpty(name))
        {
            row.setName(name.trim());
        }
        if (StringUtils.isNotEmpty(status))
        {
            if (!"0".equals(status) && !"1".equals(status))
            {
                throw new ServiceException("状态无效", HttpStatus.BAD_REQUEST);
            }
            row.setStatus(status);
        }
        row.setUpdateBy(SecurityUtils.getUsername());
        row.setUpdateTime(new Date());
        contractorMapper.updateById(row);
        return contractorMap(row);
    }

    private Map<String, String> teamMap(WearTeam team)
    {
        Map<String, String> map = new LinkedHashMap<String, String>();
        map.put("id", String.valueOf(team.getId()));
        map.put("siteId", String.valueOf(team.getSiteId()));
        map.put("name", team.getName());
        map.put("status", team.getStatus());
        return map;
    }

    private Map<String, String> contractorMap(WearContractor row)
    {
        Map<String, String> map = new LinkedHashMap<String, String>();
        map.put("id", String.valueOf(row.getId()));
        map.put("name", row.getName());
        map.put("status", row.getStatus());
        return map;
    }
}
