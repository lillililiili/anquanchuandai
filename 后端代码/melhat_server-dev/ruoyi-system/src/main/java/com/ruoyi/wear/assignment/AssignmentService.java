package com.ruoyi.wear.assignment;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.assignment.domain.WearAssetAudit;
import com.ruoyi.wear.assignment.domain.WearAssignment;
import com.ruoyi.wear.assignment.domain.WearIdempotency;
import com.ruoyi.wear.assignment.dto.AssignmentDto;
import com.ruoyi.wear.assignment.dto.IssueRequest;
import com.ruoyi.wear.assignment.mapper.WearAssetAuditMapper;
import com.ruoyi.wear.assignment.mapper.WearAssignmentMapper;
import com.ruoyi.wear.assignment.mapper.WearIdempotencyMapper;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.person.PersonEligibility;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.domain.WearPersonSite;
import com.ruoyi.wear.person.mapper.WearPersonMapper;
import com.ruoyi.wear.person.mapper.WearPersonSiteMapper;

@Service
public class AssignmentService
{
    @Autowired
    private WearAssignmentMapper assignmentMapper;
    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private WearPersonMapper personMapper;
    @Autowired
    private WearPersonSiteMapper personSiteMapper;
    @Autowired
    private WearAssetAuditMapper auditMapper;
    @Autowired
    private WearIdempotencyMapper idempotencyMapper;
    @Autowired
    private SiteAccessService siteAccessService;

    @Transactional(rollbackFor = Exception.class)
    public AssignmentDto issue(IssueRequest request, String headerIdemKey)
    {
        siteAccessService.assertCanWriteDevice();
        if (request == null || StringUtils.isEmpty(request.getDeviceId()) || StringUtils.isEmpty(request.getPersonId()))
        {
            throw new ServiceException("设备和人员不能为空", HttpStatus.BAD_REQUEST);
        }
        String idemKey = firstKey(request.getIdempotencyKey(), headerIdemKey);
        AssignmentDto replayed = replay("assignment.issue", idemKey);
        if (replayed != null)
        {
            return replayed;
        }
        Long deviceId = parseId(request.getDeviceId(), "设备标识无效");
        Long personId = parseId(request.getPersonId(), "人员标识无效");
        WearPerson person = personMapper.selectByIdForUpdate(personId);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        WearDevice device = deviceMapper.selectByIdForUpdate(deviceId);
        siteAccessService.assertDeviceReadable(device);
        if (device.getSiteId() == null || !"in_stock".equals(device.getAssetStatus()) || device.getCurrentAssignmentId() != null)
        {
            throw new ServiceException(issueBlockedReason(device), HttpStatus.CONFLICT);
        }
        boolean grant = hasActiveGrant(personId, device.getSiteId());
        if (!PersonEligibility.selectableForNewWork(person, grant, new Date()))
        {
            throw new ServiceException("人员当前不可领用", HttpStatus.CONFLICT);
        }
        String typeCode = typeOf(device);
        WearAssignment sameType = activeOfType(personId, typeCode);
        if (sameType != null)
        {
            WearDevice held = deviceMapper.selectById(sameType.getDeviceId());
            String sn = held == null ? "" : held.getSn();
            throw new ServiceException("该人员已有同类装备 " + sn, HttpStatus.CONFLICT);
        }
        Date now = new Date();
        String user = SecurityUtils.getUsername();
        WearAssignment row = new WearAssignment();
        row.setDeviceId(deviceId);
        row.setPersonId(personId);
        row.setSiteId(device.getSiteId());
        row.setIssuedAt(now);
        row.setIssuedBy(user);
        row.setVersion(1);
        row.setCreateBy(user);
        row.setCreateTime(now);
        assignmentMapper.insert(row);
        device.setAssetStatus("issued");
        device.setCurrentAssignmentId(row.getId());
        device.setVersion(device.getVersion() == null ? 1 : device.getVersion() + 1);
        device.setUpdateBy(user);
        device.setUpdateTime(now);
        deviceMapper.updateById(device);
        audit("issue", deviceId, row.getId(), personId, user, "领用 " + device.getSn());
        remember("assignment.issue", idemKey, row.getId());
        return toDto(row);
    }

    @Transactional(rollbackFor = Exception.class)
    public AssignmentDto giveBack(Long id, String reason, String idemKey)
    {
        return close(id, reason, "normal", "in_stock", idemKey, "assignment.return");
    }

    @Transactional(rollbackFor = Exception.class)
    public AssignmentDto recover(Long id, String reason, String assetStatus, String idemKey)
    {
        if (StringUtils.isEmpty(reason))
        {
            throw new ServiceException("异常回收必须填写原因", HttpStatus.BAD_REQUEST);
        }
        String status = StringUtils.isEmpty(assetStatus) ? "in_stock" : assetStatus.trim();
        if (!"in_stock".equals(status) && !"maintenance".equals(status))
        {
            throw new ServiceException("回收后资产状态无效", HttpStatus.BAD_REQUEST);
        }
        return close(id, reason, "recover", status, idemKey, "assignment.recover");
    }

    public AssignmentDto detail(Long id)
    {
        WearAssignment row = assignmentMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        assertAssignmentReadable(row);
        return toDto(row);
    }

    public AssignmentDto currentForDevice(Long deviceId)
    {
        WearDevice device = deviceMapper.selectById(deviceId);
        siteAccessService.assertDeviceReadable(device);
        if (device.getCurrentAssignmentId() == null)
        {
            return null;
        }
        WearAssignment row = assignmentMapper.selectById(device.getCurrentAssignmentId());
        return row == null ? null : toDto(row);
    }

    public List<AssignmentDto> equipmentForPerson(Long personId)
    {
        WearPerson person = personMapper.selectById(personId);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        assertPersonReadable(person);
        return mapList(assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getPersonId, personId).isNull(WearAssignment::getReturnedAt)
                .orderByDesc(WearAssignment::getId)));
    }

    public List<AssignmentDto> myEquipment()
    {
        siteAccessService.requireLogin();
        Long userId = SecurityUtils.getUserId();
        WearPerson person = personMapper.selectOne(new LambdaQueryWrapper<WearPerson>()
                .eq(WearPerson::getAccountUserId, userId).last("LIMIT 1"));
        if (person == null)
        {
            return new ArrayList<AssignmentDto>();
        }
        return equipmentForPerson(person.getId());
    }

    public List<AssignmentDto> historyForDevice(Long deviceId)
    {
        WearDevice device = deviceMapper.selectById(deviceId);
        siteAccessService.assertDeviceReadable(device);
        return mapList(assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getDeviceId, deviceId).orderByDesc(WearAssignment::getId)));
    }

    public List<AssignmentDto> historyForPerson(Long personId)
    {
        WearPerson person = personMapper.selectById(personId);
        if (person == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        assertPersonReadable(person);
        return mapList(assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getPersonId, personId).orderByDesc(WearAssignment::getId)));
    }

    private AssignmentDto close(Long id, String reason, String kind, String deviceStatus, String idemKey, String scope)
    {
        siteAccessService.assertCanWriteDevice();
        AssignmentDto replayed = replay(scope, idemKey);
        if (replayed != null)
        {
            return replayed;
        }
        WearAssignment row = assignmentMapper.selectById(id);
        if (row == null)
        {
            throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        }
        WearDevice device = deviceMapper.selectByIdForUpdate(row.getDeviceId());
        siteAccessService.assertDeviceReadable(device);
        if (row.getReturnedAt() != null)
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
        Date now = new Date();
        String user = SecurityUtils.getUsername();
        row.setReturnedAt(now);
        row.setReturnedBy(user);
        row.setReturnReason(reason);
        row.setReturnKind(kind);
        row.setVersion(row.getVersion() == null ? 1 : row.getVersion() + 1);
        row.setUpdateBy(user);
        row.setUpdateTime(now);
        assignmentMapper.updateById(row);
        if (row.getId().equals(device.getCurrentAssignmentId()))
        {
            device.setCurrentAssignmentId(null);
        }
        device.setAssetStatus(deviceStatus);
        device.setVersion(device.getVersion() == null ? 1 : device.getVersion() + 1);
        device.setUpdateBy(user);
        device.setUpdateTime(now);
        deviceMapper.updateById(device);
        audit(kind, device.getId(), row.getId(), row.getPersonId(), user, kind + " " + device.getSn());
        remember(scope, idemKey, row.getId());
        return toDto(row);
    }

    private void assertPersonReadable(WearPerson person)
    {
        List<Long> scope = siteAccessService.listScopeSiteIds();
        List<WearPersonSite> grants = personSiteMapper.selectList(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, person.getId()).eq(WearPersonSite::getStatus, "0"));
        for (WearPersonSite grant : grants)
        {
            if (scope.contains(grant.getSiteId()))
            {
                return;
            }
        }
        throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
    }

    private void assertAssignmentReadable(WearAssignment row)
    {
        List<Long> scope = siteAccessService.listScopeSiteIds();
        if (siteAccessService.isPlatformAdmin(siteAccessService.requireLogin()))
        {
            return;
        }
        if (scope.contains(row.getSiteId()))
        {
            return;
        }
        WearDevice device = deviceMapper.selectById(row.getDeviceId());
        if (device != null && device.getSiteId() != null && scope.contains(device.getSiteId()))
        {
            return;
        }
        throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
    }

    private boolean hasActiveGrant(Long personId, Long siteId)
    {
        return personSiteMapper.selectCount(new LambdaQueryWrapper<WearPersonSite>()
                .eq(WearPersonSite::getPersonId, personId)
                .eq(WearPersonSite::getSiteId, siteId)
                .eq(WearPersonSite::getStatus, "0")) > 0;
    }

    private String typeOf(WearDevice device)
    {
        if (device.getModelId() == null)
        {
            return null;
        }
        WearProductModel model = modelMapper.selectById(device.getModelId());
        return model == null ? null : model.getTypeCode();
    }

    private WearAssignment activeOfType(Long personId, String typeCode)
    {
        if (StringUtils.isEmpty(typeCode))
        {
            return null;
        }
        List<WearAssignment> active = assignmentMapper.selectList(new LambdaQueryWrapper<WearAssignment>()
                .eq(WearAssignment::getPersonId, personId).isNull(WearAssignment::getReturnedAt));
        for (WearAssignment item : active)
        {
            WearDevice held = deviceMapper.selectById(item.getDeviceId());
            if (held != null && typeCode.equals(typeOf(held)))
            {
                return item;
            }
        }
        return null;
    }

    private String issueBlockedReason(WearDevice device)
    {
        if (device.getSiteId() == null)
        {
            return "未分配厂站的设备不能领用";
        }
        if ("maintenance".equals(device.getAssetStatus()))
        {
            return "设备维修中";
        }
        if ("disabled".equals(device.getAssetStatus()))
        {
            return "设备已停用";
        }
        if ("scrapped".equals(device.getAssetStatus()))
        {
            return "设备已报废";
        }
        if ("issued".equals(device.getAssetStatus()) || device.getCurrentAssignmentId() != null)
        {
            return "设备已有有效领用";
        }
        return "设备当前不可领用";
    }

    private AssignmentDto replay(String scope, String idemKey)
    {
        if (StringUtils.isEmpty(idemKey))
        {
            return null;
        }
        WearIdempotency row = idempotencyMapper.selectOne(new LambdaQueryWrapper<WearIdempotency>()
                .eq(WearIdempotency::getScope, scope).eq(WearIdempotency::getIdemKey, idemKey.trim()).last("LIMIT 1"));
        if (row == null)
        {
            return null;
        }
        WearAssignment asg = assignmentMapper.selectById(row.getResourceId());
        return asg == null ? null : toDto(asg);
    }

    private void remember(String scope, String idemKey, Long resourceId)
    {
        if (StringUtils.isEmpty(idemKey))
        {
            return;
        }
        WearIdempotency row = new WearIdempotency();
        row.setScope(scope);
        row.setIdemKey(idemKey.trim());
        row.setResourceId(resourceId);
        row.setCreateTime(new Date());
        try
        {
            idempotencyMapper.insert(row);
        }
        catch (DataIntegrityViolationException ex)
        {
            // concurrent same key; the other transaction owns the row
        }
    }

    private void audit(String action, Long deviceId, Long assignmentId, Long personId, String operator, String summary)
    {
        WearAssetAudit audit = new WearAssetAudit();
        audit.setAction(action);
        audit.setDeviceId(deviceId);
        audit.setAssignmentId(assignmentId);
        audit.setPersonId(personId);
        audit.setOperator(operator);
        audit.setSummary(summary);
        audit.setCreateTime(new Date());
        auditMapper.insert(audit);
    }

    private List<AssignmentDto> mapList(List<WearAssignment> rows)
    {
        List<AssignmentDto> result = new ArrayList<AssignmentDto>();
        for (WearAssignment row : rows)
        {
            result.add(toDto(row));
        }
        return result;
    }

    public AssignmentDto toDto(WearAssignment row)
    {
        AssignmentDto dto = new AssignmentDto();
        dto.setId(String.valueOf(row.getId()));
        dto.setDeviceId(String.valueOf(row.getDeviceId()));
        dto.setPersonId(String.valueOf(row.getPersonId()));
        dto.setSiteId(row.getSiteId() == null ? null : String.valueOf(row.getSiteId()));
        dto.setIssuedAt(row.getIssuedAt());
        dto.setReturnedAt(row.getReturnedAt());
        dto.setIssuedBy(row.getIssuedBy());
        dto.setReturnedBy(row.getReturnedBy());
        dto.setReturnReason(row.getReturnReason());
        dto.setReturnKind(row.getReturnKind());
        dto.setVersion(row.getVersion());
        WearDevice device = deviceMapper.selectById(row.getDeviceId());
        if (device != null)
        {
            dto.setSn(device.getSn());
            dto.setTypeCode(typeOf(device));
        }
        WearPerson person = personMapper.selectById(row.getPersonId());
        if (person != null)
        {
            dto.setPersonCode(person.getPersonCode());
            dto.setPersonName(person.getName());
        }
        return dto;
    }

    private String firstKey(String body, String header)
    {
        if (StringUtils.isNotEmpty(body))
        {
            return body.trim();
        }
        if (StringUtils.isNotEmpty(header))
        {
            return header.trim();
        }
        return null;
    }

    private Long parseId(String raw, String message)
    {
        try
        {
            return Long.valueOf(raw.trim());
        }
        catch (Exception ex)
        {
            throw new ServiceException(message, HttpStatus.BAD_REQUEST);
        }
    }
}
