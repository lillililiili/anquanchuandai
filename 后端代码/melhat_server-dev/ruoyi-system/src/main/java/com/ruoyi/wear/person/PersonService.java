package com.ruoyi.wear.person;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.assignment.AssignmentService;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.org.domain.WearContractor;
import com.ruoyi.wear.org.domain.WearTeam;
import com.ruoyi.wear.org.mapper.WearContractorMapper;
import com.ruoyi.wear.org.mapper.WearTeamMapper;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.domain.WearPersonSite;
import com.ruoyi.wear.person.dto.PersonDto;
import com.ruoyi.wear.person.dto.PersonWriteRequest;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.person.mapper.WearPersonSiteMapper;

@Service
public class PersonService
{
    @Autowired
    private WearPersonMapper personMapper;
    @Autowired
    private WearPersonSiteMapper personSiteMapper;
    @Autowired
    private WearTeamMapper teamMapper;
    @Autowired
    private WearContractorMapper contractorMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    @Lazy
    private AssignmentService assignmentService;

    public WearPage<PersonDto> page(int current, int size, String name, String personCode, String status,
                                    String teamId, String contractorId)
    {
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (scope.isEmpty())
        {
            return WearPage.of(Collections.<PersonDto>emptyList(), 0, current, size);
        }
        Set<Long> personIds = personIdsInScope(scope);
        if (personIds.isEmpty())
        {
            return WearPage.of(Collections.<PersonDto>emptyList(), 0, current, size);
        }
        LambdaQueryWrapper<WearPerson> query = new LambdaQueryWrapper<WearPerson>().in(WearPerson::getId, personIds);
        if (StringUtils.isNotEmpty(name))
        {
            query.like(WearPerson::getName, name);
        }
        if (StringUtils.isNotEmpty(personCode))
        {
            query.like(WearPerson::getPersonCode, personCode);
        }
        if (StringUtils.isNotEmpty(status))
        {
            query.eq(WearPerson::getStatus, status);
        }
        if (StringUtils.isNotEmpty(teamId))
        {
            query.eq(WearPerson::getTeamId, Long.valueOf(teamId));
        }
        if (StringUtils.isNotEmpty(contractorId))
        {
            query.eq(WearPerson::getContractorId, Long.valueOf(contractorId));
        }
        query.orderByAsc(WearPerson::getId);
        IPage<WearPerson> page = personMapper.selectPage(new Page<WearPerson>(current, size), query);
        List<PersonDto> records = new ArrayList<PersonDto>();
        Long currentSite = siteAccessService.resolveRequestSiteId();
        for (WearPerson person : page.getRecords())
        {
            records.add(toDto(person, currentSite == null ? scope.get(0) : currentSite));
        }
        return WearPage.of(records, page.getTotal(), current, size);
    }

    public List<PersonDto> options(String name)
    {
        WearPage<PersonDto> page = page(1, 200, name, null, "0", null, null);
        List<PersonDto> selected = new ArrayList<PersonDto>();
        for (PersonDto dto : page.getRecords())
        {
            if (dto.isSelectable())
            {
                selected.add(dto);
            }
        }
        return selected;
    }

    public PersonDto detail(Long id)
    {
        WearPerson person = personMapper.selectById(id);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        assertPersonInScope(person);
        Long currentSite = siteAccessService.resolveRequestSiteId();
        List<Long> scope = siteAccessService.listScopeSiteIds();
        PersonDto dto = toDto(person, currentSite == null && !scope.isEmpty() ? scope.get(0) : currentSite);
        dto.setEquipment(assignmentService.equipmentForPerson(id));
        return dto;
    }

    @Transactional(rollbackFor = Exception.class)
    public PersonDto create(PersonWriteRequest request)
    {
        siteAccessService.assertCanWritePerson();
        if (request == null || StringUtils.isEmpty(request.getPersonCode()) || StringUtils.isEmpty(request.getName()))
        {
            throw new ServiceException("人员标识和姓名不能为空", HttpStatus.BAD_REQUEST);
        }
        if (personMapper.selectCount(new LambdaQueryWrapper<WearPerson>().eq(WearPerson::getPersonCode, request.getPersonCode())) > 0)
        {
            throw new ServiceException("人员标识已存在", HttpStatus.CONFLICT);
        }
        Long accountId = parseOptionalId(request.getAccountUserId());
        if (accountId != null && personMapper.selectCount(new LambdaQueryWrapper<WearPerson>().eq(WearPerson::getAccountUserId, accountId)) > 0)
        {
            throw new ServiceException("该登录账号已关联人员", HttpStatus.CONFLICT);
        }
        List<Long> siteIds = resolveWriteSiteIds(request.getSiteIds());
        assertTeamInSites(parseOptionalId(request.getTeamId()), siteIds);
        WearPerson person = new WearPerson();
        applyWrite(person, request, accountId);
        person.setStatus("0");
        person.setVersion(1);
        person.setDelFlag("0");
        person.setCreateBy(SecurityUtils.getUsername());
        person.setCreateTime(new Date());
        personMapper.insert(person);
        replaceGrants(person.getId(), siteIds);
        return detail(person.getId());
    }

    @Transactional(rollbackFor = Exception.class)
    public PersonDto update(Long id, PersonWriteRequest request)
    {
        siteAccessService.assertCanWritePerson();
        WearPerson person = personMapper.selectById(id);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        assertPersonInScope(person);
        if (request.getVersion() == null || !request.getVersion().equals(person.getVersion()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (StringUtils.isNotEmpty(request.getPersonCode()) && !request.getPersonCode().equals(person.getPersonCode()))
        {
            if (personMapper.selectCount(new LambdaQueryWrapper<WearPerson>()
                    .eq(WearPerson::getPersonCode, request.getPersonCode()).ne(WearPerson::getId, id)) > 0)
            {
                throw new ServiceException("人员标识已存在", HttpStatus.CONFLICT);
            }
        }
        Long accountId = parseOptionalId(request.getAccountUserId());
        if (accountId != null && personMapper.selectCount(new LambdaQueryWrapper<WearPerson>()
                .eq(WearPerson::getAccountUserId, accountId).ne(WearPerson::getId, id)) > 0)
        {
            throw new ServiceException("该登录账号已关联人员", HttpStatus.CONFLICT);
        }
        List<Long> siteIds = request.getSiteIds() != null
                ? resolveWriteSiteIds(request.getSiteIds())
                : grantedSiteIds(id);
        assertTeamInSites(parseOptionalId(request.getTeamId()), siteIds);
        applyWrite(person, request, accountId);
        person.setVersion(person.getVersion() + 1);
        person.setUpdateBy(SecurityUtils.getUsername());
        person.setUpdateTime(new Date());
        personMapper.updateById(person);
        if (request.getSiteIds() != null)
        {
            replaceGrants(id, siteIds);
        }
        return detail(id);
    }

    @Transactional(rollbackFor = Exception.class)
    public PersonDto changeStatus(Long id, String status, Integer version)
    {
        siteAccessService.assertCanWritePerson();
        WearPerson person = personMapper.selectById(id);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        assertPersonInScope(person);
        if (version == null || !version.equals(person.getVersion()))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        if (!"0".equals(status) && !"1".equals(status))
        {
            throw new ServiceException("状态无效", HttpStatus.BAD_REQUEST);
        }
        person.setStatus(status);
        person.setVersion(person.getVersion() + 1);
        person.setUpdateBy(SecurityUtils.getUsername());
        person.setUpdateTime(new Date());
        personMapper.updateById(person);
        return detail(id);
    }

    public void assertPersonInScope(WearPerson person)
    {
        List<Long> scope = siteAccessService.listScopeSiteIds();
        List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, person.getId()).eq(WearPersonSite::getStatus, "0"));
        boolean hit = false;
        for (WearPersonSite grant : grants)
        {
            if (scope.contains(grant.getSiteId()))
            {
                hit = true;
                break;
            }
        }
        if (!hit)
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
    }

    private Set<Long> personIdsInScope(List<Long> scope)
    {
        List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .in(WearPersonSite::getSiteId, scope).eq(WearPersonSite::getStatus, "0"));
        Set<Long> ids = new HashSet<Long>();
        for (WearPersonSite grant : grants)
        {
            ids.add(grant.getPersonId());
        }
        return ids;
    }

    private List<Long> grantedSiteIds(Long personId)
    {
        List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, personId).eq(WearPersonSite::getStatus, "0"));
        List<Long> ids = new ArrayList<Long>();
        for (WearPersonSite grant : grants)
        {
            ids.add(grant.getSiteId());
        }
        return ids;
    }

    private void assertTeamInSites(Long teamId, List<Long> siteIds)
    {
        if (teamId == null)
        {
            return;
        }
        WearTeam team = teamMapper.selectById(teamId);
        if (team == null)
        {
            throw new ServiceException("班组不存在", HttpStatus.BAD_REQUEST);
        }
        if (siteIds == null || !siteIds.contains(team.getSiteId()))
        {
            throw new ServiceException("班组不属于授权厂站", HttpStatus.FORBIDDEN);
        }
    }

    private List<Long> resolveWriteSiteIds(List<String> raw)
    {
        List<Long> allowed = siteAccessService.authorizedSiteIds();
        List<Long> ids = new ArrayList<Long>();
        if (raw == null || raw.isEmpty())
        {
            Long current = siteAccessService.requireCurrentSiteForWrite();
            ids.add(current);
            return ids;
        }
        for (String item : raw)
        {
            Long id = siteAccessService.parseSiteId(item);
            if (!allowed.contains(id))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            ids.add(id);
        }
        return ids;
    }

    private void replaceGrants(Long personId, List<Long> siteIds)
    {
        Date now = new Date();
        String user = SecurityUtils.getUsername();
        Set<Long> wanted = new HashSet<Long>(siteIds);
        List<WearPersonSite> existing = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, personId));
        for (WearPersonSite grant : existing)
        {
            if (wanted.contains(grant.getSiteId()))
            {
                grant.setStatus("0");
                wanted.remove(grant.getSiteId());
            }
            else
            {
                grant.setStatus("1");
            }
            grant.setUpdateBy(user);
            grant.setUpdateTime(now);
            personSiteMapper.updateById(grant);
        }
        for (Long siteId : wanted)
        {
            WearPersonSite grant = new WearPersonSite();
            grant.setPersonId(personId);
            grant.setSiteId(siteId);
            grant.setStatus("0");
            grant.setCreateBy(user);
            grant.setCreateTime(now);
            personSiteMapper.insert(grant);
        }
    }

    private void applyWrite(WearPerson person, PersonWriteRequest request, Long accountId)
    {
        if (StringUtils.isNotEmpty(request.getPersonCode()))
        {
            person.setPersonCode(request.getPersonCode().trim());
        }
        if (StringUtils.isNotEmpty(request.getName()))
        {
            person.setName(request.getName().trim());
        }
        person.setOrgDeptId(parseOptionalId(request.getOrgDeptId()));
        person.setTeamId(parseOptionalId(request.getTeamId()));
        person.setContractorId(parseOptionalId(request.getContractorId()));
        person.setAccountUserId(accountId);
        person.setValidFrom(request.getValidFrom());
        person.setValidTo(request.getValidTo());
    }

    private PersonDto toDto(WearPerson person, Long selectableSiteId)
    {
        PersonDto dto = new PersonDto();
        dto.setId(String.valueOf(person.getId()));
        dto.setPersonCode(person.getPersonCode());
        dto.setName(person.getName());
        dto.setOrgDeptId(person.getOrgDeptId() == null ? null : String.valueOf(person.getOrgDeptId()));
        dto.setTeamId(person.getTeamId() == null ? null : String.valueOf(person.getTeamId()));
        dto.setContractorId(person.getContractorId() == null ? null : String.valueOf(person.getContractorId()));
        dto.setAccountUserId(person.getAccountUserId() == null ? null : String.valueOf(person.getAccountUserId()));
        dto.setStatus(person.getStatus());
        dto.setValidFrom(person.getValidFrom());
        dto.setValidTo(person.getValidTo());
        dto.setVersion(person.getVersion());
        if (person.getTeamId() != null)
        {
            WearTeam team = teamMapper.selectById(person.getTeamId());
            if (team != null)
            {
                dto.setTeamName(team.getName());
            }
        }
        if (person.getContractorId() != null)
        {
            WearContractor contractor = contractorMapper.selectById(person.getContractorId());
            if (contractor != null)
            {
                dto.setContractorName(contractor.getName());
            }
        }
        List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, person.getId()).eq(WearPersonSite::getStatus, "0"));
        List<String> siteIds = new ArrayList<String>();
        boolean grantOnSelectableSite = false;
        for (WearPersonSite grant : grants)
        {
            siteIds.add(String.valueOf(grant.getSiteId()));
            if (selectableSiteId != null && selectableSiteId.equals(grant.getSiteId()))
            {
                grantOnSelectableSite = true;
            }
        }
        dto.setSiteIds(siteIds);
        dto.setSelectable(PersonEligibility.selectableForNewWork(person, grantOnSelectableSite, new Date()));
        return dto;
    }

    private Long parseOptionalId(String raw)
    {
        if (StringUtils.isEmpty(raw))
        {
            return null;
        }
        try
        {
            return Long.valueOf(raw.trim());
        }
        catch (NumberFormatException ex)
        {
            throw new ServiceException("标识无效", HttpStatus.BAD_REQUEST);
        }
    }
}
