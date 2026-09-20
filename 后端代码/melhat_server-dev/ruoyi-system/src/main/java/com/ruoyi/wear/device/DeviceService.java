package com.ruoyi.wear.device;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.helmet.mapper.SafetyHatInfoMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearDeviceLegacyHat;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.dto.DeviceDto;
import com.ruoyi.wear.device.dto.DeviceWriteRequest;
import com.ruoyi.wear.assignment.AssignmentService;
import com.ruoyi.wear.assignment.domain.WearDeviceSiteTransfer;
import com.ruoyi.wear.assignment.mapper.WearDeviceSiteTransferMapper;
import com.ruoyi.wear.device.mapper.WearDeviceLegacyHatMapper;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.helmet.TelemetryFreshness;
import com.ruoyi.wear.site.domain.WearSite;
import com.ruoyi.wear.site.mapper.WearSiteMapper;

@Service
public class DeviceService
{
    private static final Set<String> ASSET_STATUSES = new HashSet<String>();

    static
    {
        ASSET_STATUSES.add("unassigned");
        ASSET_STATUSES.add("in_stock");
        ASSET_STATUSES.add("issued");
        ASSET_STATUSES.add("maintenance");
        ASSET_STATUSES.add("disabled");
        ASSET_STATUSES.add("scrapped");
    }

    @Autowired
    private WearDeviceMapper deviceMapper;
    @Autowired
    private WearProductModelMapper modelMapper;
    @Autowired
    private WearDeviceLegacyHatMapper legacyHatMapper;
    @Autowired
    private WearSiteMapper siteMapper;
    @Autowired
    private SafetyHatInfoMapper hatMapper;
    @Autowired
    private SiteAccessService siteAccessService;
    @Autowired
    private WearDeviceSiteTransferMapper transferMapper;
    @Autowired
    @Lazy
    private AssignmentService assignmentService;
    @Value("${melhat.telemetry.stale-after-seconds:180}")
    private int staleAfterSeconds;
    @Autowired
    private DeviceSimulationStateService simulationStates;

    public WearPage<DeviceDto> page(int current, int size, String typeCode, String modelId, String sn, String assetStatus)
    {
        List<Long> scope = siteAccessService.listScopeSiteIds();
        boolean platform = siteAccessService.isPlatformAdmin(siteAccessService.requireLogin());
        Long currentSite = siteAccessService.resolveRequestSiteId();
        LambdaQueryWrapper<WearDevice> query = new LambdaQueryWrapper<WearDevice>();
        if (currentSite != null)
        {
            query.eq(WearDevice::getSiteId, currentSite);
        }
        else if (platform)
        {
            if (!scope.isEmpty())
            {
                query.and(w -> w.in(WearDevice::getSiteId, scope).or().isNull(WearDevice::getSiteId));
            }
        }
        else
        {
            if (scope.isEmpty())
            {
                return WearPage.of(Collections.<DeviceDto>emptyList(), 0, current, size);
            }
            query.in(WearDevice::getSiteId, scope);
        }
        if (StringUtils.isNotEmpty(sn))
        {
            query.like(WearDevice::getSn, sn.trim());
        }
        if (StringUtils.isNotEmpty(assetStatus))
        {
            query.eq(WearDevice::getAssetStatus, assetStatus);
        }
        if (StringUtils.isNotEmpty(modelId))
        {
            query.eq(WearDevice::getModelId, Long.valueOf(modelId));
        }
        else if (StringUtils.isNotEmpty(typeCode))
        {
            List<Long> modelIds = modelIdsOfType(typeCode);
            if (modelIds.isEmpty())
            {
                return WearPage.of(Collections.<DeviceDto>emptyList(), 0, current, size);
            }
            query.in(WearDevice::getModelId, modelIds);
        }
        query.orderByAsc(WearDevice::getId);
        IPage<WearDevice> page = deviceMapper.selectPage(new Page<WearDevice>(current, size), query);
        List<DeviceDto> records = new ArrayList<DeviceDto>();
        for (WearDevice device : page.getRecords())
        {
            records.add(toDto(device));
        }
        return WearPage.of(records, page.getTotal(), current, size);
    }

    public DeviceDto detail(Long id)
    {
        WearDevice device = deviceMapper.selectById(id);
        siteAccessService.assertDeviceReadable(device);
        DeviceDto dto = toDto(device);
        dto.setCurrentAssignment(assignmentService.currentForDevice(id));
        return dto;
    }

    @Transactional(rollbackFor = Exception.class)
    public DeviceDto create(DeviceWriteRequest request)
    {
        siteAccessService.assertCanWriteDevice();
        if (request == null || StringUtils.isEmpty(request.getManufacturerCode()) || StringUtils.isEmpty(request.getSn())
                || StringUtils.isEmpty(request.getModelId()))
        {
            throw new ServiceException("厂商、序列号和型号不能为空", HttpStatus.BAD_REQUEST);
        }
        WearProductModel model = modelMapper.selectById(parseId(request.getModelId(), "型号无效"));
        if (model == null)
        {
            throw new ServiceException("型号不存在", HttpStatus.BAD_REQUEST);
        }
        Long siteId = resolveCreateSiteId(request.getSiteId());
        WearDevice device = new WearDevice();
        device.setManufacturerCode(request.getManufacturerCode().trim());
        device.setSn(request.getSn().trim());
        device.setModelId(model.getId());
        device.setSiteId(siteId);
        device.setExternalCode(StringUtils.isEmpty(request.getExternalCode()) ? device.getSn() : request.getExternalCode().trim());
        device.setAssetStatus(siteId == null ? "unassigned" : "in_stock");
        device.setOnline(null);
        device.setBattery(null);
        device.setLastReportedAt(null);
        device.setVersion(1);
        device.setDelFlag("0");
        device.setCreateBy(SecurityUtils.getUsername());
        device.setCreateTime(new Date());
        try
        {
            deviceMapper.insert(device);
        }
        catch (DataIntegrityViolationException ex)
        {
            throw new ServiceException("设备序列号已存在", HttpStatus.CONFLICT);
        }
        return detail(device.getId());
    }

    @Transactional(rollbackFor = Exception.class)
    public DeviceDto update(Long id, DeviceWriteRequest request)
    {
        siteAccessService.assertCanWriteDevice();
        WearDevice device = deviceMapper.selectById(id);
        siteAccessService.assertDeviceReadable(device);
        assertVersion(request.getVersion(), device.getVersion());
        if (StringUtils.isNotEmpty(request.getSn()) || StringUtils.isNotEmpty(request.getManufacturerCode()))
        {
            String mfr = StringUtils.isNotEmpty(request.getManufacturerCode())
                    ? request.getManufacturerCode().trim() : device.getManufacturerCode();
            String sn = StringUtils.isNotEmpty(request.getSn()) ? request.getSn().trim() : device.getSn();
            if (deviceMapper.selectCount(new LambdaQueryWrapper<WearDevice>()
                    .eq(WearDevice::getManufacturerCode, mfr).eq(WearDevice::getSn, sn)
                    .ne(WearDevice::getId, id)) > 0)
            {
                throw new ServiceException("设备序列号已存在", HttpStatus.CONFLICT);
            }
            device.setManufacturerCode(mfr);
            device.setSn(sn);
        }
        if (StringUtils.isNotEmpty(request.getModelId()))
        {
            WearProductModel model = modelMapper.selectById(parseId(request.getModelId(), "型号无效"));
            if (model == null)
            {
                throw new ServiceException("型号不存在", HttpStatus.BAD_REQUEST);
            }
            device.setModelId(model.getId());
        }
        if (request.getExternalCode() != null)
        {
            device.setExternalCode(StringUtils.isEmpty(request.getExternalCode()) ? device.getSn() : request.getExternalCode().trim());
        }
        device.setOnline(device.getOnline());
        device.setVersion(device.getVersion() + 1);
        device.setUpdateBy(SecurityUtils.getUsername());
        device.setUpdateTime(new Date());
        try
        {
            deviceMapper.updateById(device);
        }
        catch (DataIntegrityViolationException ex)
        {
            throw new ServiceException("设备序列号已存在", HttpStatus.CONFLICT);
        }
        return detail(id);
    }

    @Transactional(rollbackFor = Exception.class)
    public DeviceDto assignSite(Long id, String siteId, Integer version)
    {
        siteAccessService.assertCanWriteDevice();
        WearDevice device = deviceMapper.selectById(id);
        siteAccessService.assertDeviceReadable(device);
        assertVersion(version, device.getVersion());
        if (device.getCurrentAssignmentId() != null)
        {
            throw new ServiceException("请先归还或走异常回收", HttpStatus.CONFLICT);
        }
        Long fromSite = device.getSiteId();
        if (StringUtils.isEmpty(siteId))
        {
            if (!siteAccessService.isPlatformAdmin(siteAccessService.requireLogin()))
            {
                throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
            }
            device.setSiteId(null);
            if ("in_stock".equals(device.getAssetStatus()))
            {
                device.setAssetStatus("unassigned");
            }
        }
        else
        {
            Long sid = siteAccessService.parseSiteId(siteId);
            siteAccessService.assertAuthorized(sid);
            device.setSiteId(sid);
            if ("unassigned".equals(device.getAssetStatus()))
            {
                device.setAssetStatus("in_stock");
            }
        }
        device.setVersion(device.getVersion() + 1);
        device.setUpdateBy(SecurityUtils.getUsername());
        device.setUpdateTime(new Date());
        deviceMapper.updateById(device);
        WearDeviceSiteTransfer transfer = new WearDeviceSiteTransfer();
        transfer.setDeviceId(id);
        transfer.setFromSiteId(fromSite);
        transfer.setToSiteId(device.getSiteId());
        transfer.setOperator(SecurityUtils.getUsername());
        transfer.setCreateTime(new Date());
        transferMapper.insert(transfer);
        return detail(id);
    }

    @Transactional(rollbackFor = Exception.class)
    public DeviceDto changeAssetStatus(Long id, String assetStatus, Integer version)
    {
        siteAccessService.assertCanWriteDevice();
        WearDevice device = deviceMapper.selectById(id);
        siteAccessService.assertDeviceReadable(device);
        assertVersion(version, device.getVersion());
        if (device.getCurrentAssignmentId() != null)
        {
            throw new ServiceException("请先归还或走异常回收", HttpStatus.CONFLICT);
        }
        if ("issued".equals(assetStatus))
        {
            throw new ServiceException("已领用状态只能通过领用产生", HttpStatus.BAD_REQUEST);
        }
        if (!ASSET_STATUSES.contains(assetStatus))
        {
            throw new ServiceException("资产状态无效", HttpStatus.BAD_REQUEST);
        }
        if ("unassigned".equals(assetStatus) && device.getSiteId() != null)
        {
            throw new ServiceException("已分配厂站的设备不能标为未分配", HttpStatus.BAD_REQUEST);
        }
        if (!"unassigned".equals(assetStatus) && device.getSiteId() == null && !"unassigned".equals(device.getAssetStatus()))
        {
            throw new ServiceException("请先分配厂站", HttpStatus.BAD_REQUEST);
        }
        device.setAssetStatus(assetStatus);
        device.setVersion(device.getVersion() + 1);
        device.setUpdateBy(SecurityUtils.getUsername());
        device.setUpdateTime(new Date());
        deviceMapper.updateById(device);
        return detail(id);
    }

    public List<Map<String, String>> legacyPreview()
    {
        if (!siteAccessService.isPlatformAdmin(siteAccessService.requireLogin()))
        {
            throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        }
        List<WearDeviceLegacyHat> mapped = legacyHatMapper.selectList(new LambdaQueryWrapper<WearDeviceLegacyHat>());
        Set<Long> hatIds = new HashSet<Long>();
        for (WearDeviceLegacyHat row : mapped)
        {
            hatIds.add(row.getHatId());
        }
        List<SafetyHatInfo> hats = hatMapper.selectList(new LambdaQueryWrapper<SafetyHatInfo>()
                .eq(SafetyHatInfo::getDelFlag, "0").orderByAsc(SafetyHatInfo::getId));
        List<Map<String, String>> result = new ArrayList<Map<String, String>>();
        for (SafetyHatInfo hat : hats)
        {
            if (hatIds.contains(hat.getId()))
            {
                continue;
            }
            Map<String, String> item = new HashMap<String, String>();
            item.put("hatId", String.valueOf(hat.getId()));
            item.put("hatNumber", hat.getHatNumber());
            item.put("siteId", hat.getSiteId() == null ? null : String.valueOf(hat.getSiteId()));
            result.add(item);
        }
        return result;
    }

    private Long resolveCreateSiteId(String raw)
    {
        if (StringUtils.isNotEmpty(raw))
        {
            Long sid = siteAccessService.parseSiteId(raw);
            siteAccessService.assertAuthorized(sid);
            return sid;
        }
        if (siteAccessService.isPlatformAdmin(siteAccessService.requireLogin()))
        {
            Long current = siteAccessService.resolveRequestSiteId();
            return current;
        }
        return siteAccessService.requireCurrentSiteForWrite();
    }

    private List<Long> modelIdsOfType(String typeCode)
    {
        List<WearProductModel> models = modelMapper.selectList(new LambdaQueryWrapper<WearProductModel>()
                .eq(WearProductModel::getTypeCode, typeCode));
        List<Long> ids = new ArrayList<Long>();
        for (WearProductModel model : models)
        {
            ids.add(model.getId());
        }
        return ids;
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

    private void assertVersion(Integer submitted, Integer current)
    {
        if (submitted == null || current == null || !submitted.equals(current))
        {
            throw new ServiceException("当前状态冲突，请刷新后重试", HttpStatus.CONFLICT);
        }
    }

    private DeviceDto toDto(WearDevice device)
    {
        DeviceDto dto = new DeviceDto();
        dto.setId(String.valueOf(device.getId()));
        dto.setManufacturerCode(device.getManufacturerCode());
        dto.setSn(device.getSn());
        dto.setExternalCode(device.getExternalCode());
        dto.setModelId(device.getModelId() == null ? null : String.valueOf(device.getModelId()));
        dto.setSiteId(device.getSiteId() == null ? null : String.valueOf(device.getSiteId()));
        dto.setAssetStatus(device.getAssetStatus());
        dto.setOnline(device.getOnline());
        dto.setBattery(device.getBattery());
        dto.setLastReportedAt(device.getLastReportedAt());
        dto.setLastTelemetryAt(device.getLastTelemetryAt());
        String quality = TelemetryFreshness.connectionQuality(device.getLastReportedAt(), new Date(), staleAfterSeconds);
        dto.setConnectionQuality(quality);
        dto.setLocationQuality(device.getLastReportedAt() == null ? TelemetryFreshness.UNKNOWN : quality);
        dto.setSource(device.getLastReportedAt() == null ? "db" : "live");
        dto.setDemo("demo".equals(device.getCreateBy()));
        dto.setVersion(device.getVersion());
        if (simulationStates != null) simulationStates.enrich(dto);
        if (device.getModelId() != null)
        {
            WearProductModel model = modelMapper.selectById(device.getModelId());
            if (model != null)
            {
                dto.setModelCode(model.getModelCode());
                dto.setModelName(model.getName());
                dto.setTypeCode(model.getTypeCode());
                dto.setCapabilities(DeviceCapability.parse(model.getCapabilities()));
            }
        }
        if (device.getSiteId() != null)
        {
            WearSite site = siteMapper.selectById(device.getSiteId());
            if (site != null)
            {
                dto.setSiteName(site.getName());
            }
        }
        WearDeviceLegacyHat map = legacyHatMapper.selectOne(new LambdaQueryWrapper<WearDeviceLegacyHat>()
                .eq(WearDeviceLegacyHat::getDeviceId, device.getId()).last("LIMIT 1"));
        if (map != null)
        {
            dto.setLegacyHatId(String.valueOf(map.getHatId()));
        }
        return dto;
    }
}
