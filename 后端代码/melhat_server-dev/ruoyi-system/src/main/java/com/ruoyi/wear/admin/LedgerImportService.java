package com.ruoyi.wear.admin;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.wear.admin.dto.DeviceLedgerRow;
import com.ruoyi.wear.admin.dto.LedgerImportError;
import com.ruoyi.wear.admin.dto.LedgerImportResult;
import com.ruoyi.wear.admin.dto.PersonLedgerRow;
import com.ruoyi.wear.admin.dto.ProductModelLedgerRow;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.device.DeviceService;
import com.ruoyi.wear.device.ProductModelService;
import com.ruoyi.wear.device.domain.WearDevice;
import com.ruoyi.wear.device.domain.WearProductModel;
import com.ruoyi.wear.device.dto.CapabilityDto;
import com.ruoyi.wear.device.dto.DeviceDto;
import com.ruoyi.wear.device.dto.DeviceWriteRequest;
import com.ruoyi.wear.device.dto.ProductModelDto;
import com.ruoyi.wear.device.mapper.WearDeviceMapper;
import com.ruoyi.wear.device.mapper.WearProductModelMapper;
import com.ruoyi.wear.person.PersonService;
import com.ruoyi.wear.person.domain.WearPerson;
import com.ruoyi.wear.person.dto.PersonDto;
import com.ruoyi.wear.person.dto.PersonWriteRequest;
import com.ruoyi.wear.person.mapper.WearPersonMapper;

@Service
public class LedgerImportService
{
    private static final int MAX_ROWS = 5000;
    private static final Set<String> DEVICE_STATUSES = new HashSet<String>(Arrays.asList(
            "unassigned", "in_stock", "issued", "maintenance", "disabled", "scrapped"));

    @Autowired private PersonService personService;
    @Autowired private DeviceService deviceService;
    @Autowired private ProductModelService productModelService;
    @Autowired private SiteAccessService siteAccessService;
    @Autowired private WearPersonMapper personMapper;
    @Autowired private WearDeviceMapper deviceMapper;
    @Autowired private WearProductModelMapper modelMapper;

    @Transactional(rollbackFor = Exception.class)
    public LedgerImportResult importPeople(List<PersonLedgerRow> rows, boolean updateExisting)
    {
        siteAccessService.assertCanWritePerson();
        LedgerImportResult result = begin(rows == null ? 0 : rows.size());
        if (rows == null || result.hasErrors()) return result;
        Set<String> seen = new HashSet<String>();
        List<Long> authorized = siteAccessService.authorizedSiteIds();
        for (int i = 0; i < rows.size(); i++)
        {
            PersonLedgerRow row = rows.get(i);
            int excelRow = i + 2;
            String code = trim(row.getPersonCode());
            if (blank(code)) error(result, excelRow, "personCode", "人员编码不能为空");
            else if (!seen.add(code)) error(result, excelRow, "personCode", "导入文件内人员编码重复");
            if (blank(row.getName())) error(result, excelRow, "name", "姓名不能为空");
            validateBinaryStatus(result, excelRow, row.getStatus());
            if (row.getValidFrom() != null && row.getValidTo() != null && row.getValidFrom().after(row.getValidTo()))
                error(result, excelRow, "validTo", "有效期结束不能早于开始日期");
            validateSiteIds(result, excelRow, row.getSiteIds(), authorized);
            validateOptionalId(result, excelRow, "teamId", row.getTeamId());
            validateOptionalId(result, excelRow, "contractorId", row.getContractorId());
            WearPerson existing = blank(code) ? null : personMapper.selectOne(new LambdaQueryWrapper<WearPerson>()
                    .eq(WearPerson::getPersonCode, code).last("LIMIT 1"));
            if (existing != null)
            {
                try { personService.detail(existing.getId()); }
                catch (ServiceException ex) { error(result, excelRow, "personCode", "人员不在当前厂站权限范围"); }
                if (!updateExisting) result.setSkipped(result.getSkipped() + 1);
            }
        }
        if (result.hasErrors()) return result;
        for (PersonLedgerRow row : rows)
        {
            String code = trim(row.getPersonCode());
            WearPerson existing = personMapper.selectOne(new LambdaQueryWrapper<WearPerson>()
                    .eq(WearPerson::getPersonCode, code).last("LIMIT 1"));
            if (existing != null && !updateExisting) continue;
            PersonWriteRequest request = new PersonWriteRequest();
            request.setPersonCode(code);
            request.setName(trim(row.getName()));
            request.setTeamId(trimToNull(row.getTeamId()));
            request.setContractorId(trimToNull(row.getContractorId()));
            request.setValidFrom(row.getValidFrom());
            request.setValidTo(row.getValidTo());
            request.setSiteIds(split(row.getSiteIds()));
            String wantedStatus = normalizeBinaryStatus(row.getStatus());
            PersonDto saved;
            if (existing == null)
            {
                saved = personService.create(request);
                result.setCreated(result.getCreated() + 1);
            }
            else
            {
                PersonDto current = personService.detail(existing.getId());
                request.setVersion(current.getVersion());
                if (request.getSiteIds().isEmpty()) request.setSiteIds(current.getSiteIds());
                saved = personService.update(existing.getId(), request);
                result.setUpdated(result.getUpdated() + 1);
            }
            if (wantedStatus != null && !wantedStatus.equals(saved.getStatus()))
                personService.changeStatus(Long.valueOf(saved.getId()), wantedStatus, saved.getVersion());
        }
        return result;
    }

    @Transactional(rollbackFor = Exception.class)
    public LedgerImportResult importDevices(List<DeviceLedgerRow> rows, boolean updateExisting)
    {
        siteAccessService.assertCanWriteDevice();
        LedgerImportResult result = begin(rows == null ? 0 : rows.size());
        if (rows == null || result.hasErrors()) return result;
        Set<String> seen = new HashSet<String>();
        List<Long> authorized = siteAccessService.authorizedSiteIds();
        for (int i = 0; i < rows.size(); i++)
        {
            DeviceLedgerRow row = rows.get(i);
            int excelRow = i + 2;
            String manufacturer = trim(row.getManufacturerCode());
            String sn = trim(row.getSn());
            String key = manufacturer + "\u0000" + sn;
            if (blank(manufacturer)) error(result, excelRow, "manufacturerCode", "厂商编码不能为空");
            if (blank(sn)) error(result, excelRow, "sn", "设备序列号不能为空");
            if (!blank(manufacturer) && !blank(sn) && !seen.add(key))
                error(result, excelRow, "sn", "导入文件内厂商编码与序列号重复");
            WearProductModel model = findModel(row.getModelCode());
            if (model == null) error(result, excelRow, "modelCode", "型号编码不存在");
            else if (!"0".equals(model.getStatus())) error(result, excelRow, "modelCode", "型号已停用，不能用于新建或更新设备");
            validateSingleSite(result, excelRow, row.getSiteId(), authorized);
            if (!blank(row.getAssetStatus()) && !DEVICE_STATUSES.contains(trim(row.getAssetStatus())))
                error(result, excelRow, "assetStatus", "资产状态无效");
            WearDevice existing = blank(manufacturer) || blank(sn) ? null : findDevice(manufacturer, sn);
            if ("issued".equals(trim(row.getAssetStatus()))
                    && (existing == null || !"issued".equals(existing.getAssetStatus())))
                error(result, excelRow, "assetStatus", "已领用状态只能通过资产领用产生");
            if (existing != null)
            {
                try { deviceService.detail(existing.getId()); }
                catch (ServiceException ex) { error(result, excelRow, "sn", "设备不在当前厂站权限范围"); }
                if (!blank(row.getSiteId()) && existing.getSiteId() != null
                        && !row.getSiteId().trim().equals(String.valueOf(existing.getSiteId())))
                    error(result, excelRow, "siteId", "导入不能变更已有设备厂站，请使用资产流转功能");
                if (!updateExisting) result.setSkipped(result.getSkipped() + 1);
            }
        }
        if (result.hasErrors()) return result;
        for (DeviceLedgerRow row : rows)
        {
            String manufacturer = trim(row.getManufacturerCode());
            String sn = trim(row.getSn());
            WearDevice existing = findDevice(manufacturer, sn);
            if (existing != null && !updateExisting) continue;
            WearProductModel model = findModel(row.getModelCode());
            DeviceWriteRequest request = new DeviceWriteRequest();
            request.setManufacturerCode(manufacturer);
            request.setSn(sn);
            request.setModelId(String.valueOf(model.getId()));
            request.setExternalCode(trimToNull(row.getExternalCode()));
            request.setSiteId(trimToNull(row.getSiteId()));
            DeviceDto saved;
            if (existing == null)
            {
                saved = deviceService.create(request);
                result.setCreated(result.getCreated() + 1);
            }
            else
            {
                DeviceDto current = deviceService.detail(existing.getId());
                request.setVersion(current.getVersion());
                saved = deviceService.update(existing.getId(), request);
                result.setUpdated(result.getUpdated() + 1);
            }
            String status = trimToNull(row.getAssetStatus());
            if (status != null && !"issued".equals(status) && !status.equals(saved.getAssetStatus()))
                deviceService.changeAssetStatus(Long.valueOf(saved.getId()), status, saved.getVersion());
        }
        return result;
    }

    @Transactional(rollbackFor = Exception.class)
    public LedgerImportResult importProductModels(List<ProductModelLedgerRow> rows, boolean updateExisting)
    {
        siteAccessService.assertCanWriteDevice();
        LedgerImportResult result = begin(rows == null ? 0 : rows.size());
        if (rows == null || result.hasErrors()) return result;
        Set<String> seen = new HashSet<String>();
        for (int i = 0; i < rows.size(); i++)
        {
            ProductModelLedgerRow row = rows.get(i);
            int excelRow = i + 2;
            String code = trim(row.getModelCode());
            if (blank(code)) error(result, excelRow, "modelCode", "型号编码不能为空");
            else if (!seen.add(code)) error(result, excelRow, "modelCode", "导入文件内型号编码重复");
            if (blank(row.getName())) error(result, excelRow, "name", "型号名称不能为空");
            if (blank(row.getManufacturerCode())) error(result, excelRow, "manufacturerCode", "厂商编码不能为空");
            if (!"helmet".equals(trim(row.getTypeCode())) && !"belt".equals(trim(row.getTypeCode())))
                error(result, excelRow, "typeCode", "产品类型只能是 helmet 或 belt");
            validateBinaryStatus(result, excelRow, row.getStatus());
            if (findModel(code) != null && !updateExisting) result.setSkipped(result.getSkipped() + 1);
        }
        if (result.hasErrors()) return result;
        for (ProductModelLedgerRow row : rows)
        {
            WearProductModel existing = findModel(row.getModelCode());
            if (existing != null && !updateExisting) continue;
            ProductModelDto request = new ProductModelDto();
            request.setTypeCode(trim(row.getTypeCode()));
            request.setModelCode(trim(row.getModelCode()));
            request.setManufacturerCode(trim(row.getManufacturerCode()));
            request.setName(trim(row.getName()));
            request.setProtocolVersion(trimToNull(row.getProtocolVersion()));
            CapabilityDto capabilities = new CapabilityDto();
            capabilities.setProtocolVersion(trimToNull(row.getProtocolVersion()));
            capabilities.setAttributes(split(row.getAttributes()));
            capabilities.setEvents(split(row.getEvents()));
            capabilities.setActions(split(row.getActions()));
            request.setCapabilities(capabilities);
            String wantedStatus = normalizeBinaryStatus(row.getStatus());
            ProductModelDto saved;
            if (existing == null)
            {
                saved = productModelService.create(request);
                result.setCreated(result.getCreated() + 1);
            }
            else
            {
                request.setVersion(existing.getVersion());
                saved = productModelService.update(existing.getId(), request);
                result.setUpdated(result.getUpdated() + 1);
            }
            if (wantedStatus != null && !wantedStatus.equals(saved.getStatus()))
                productModelService.changeStatus(Long.valueOf(saved.getId()), wantedStatus, saved.getVersion());
        }
        return result;
    }

    private LedgerImportResult begin(int total)
    {
        LedgerImportResult result = new LedgerImportResult();
        result.setTotal(total);
        if (total == 0) error(result, 0, "file", "导入文件没有数据");
        if (total > MAX_ROWS) error(result, 0, "file", "单次导入最多 5000 行");
        return result;
    }

    private WearProductModel findModel(String code)
    {
        if (blank(code)) return null;
        return modelMapper.selectOne(new LambdaQueryWrapper<WearProductModel>()
                .eq(WearProductModel::getModelCode, trim(code)).last("LIMIT 1"));
    }

    private WearDevice findDevice(String manufacturer, String sn)
    {
        return deviceMapper.selectOne(new LambdaQueryWrapper<WearDevice>()
                .eq(WearDevice::getManufacturerCode, manufacturer)
                .eq(WearDevice::getSn, sn).last("LIMIT 1"));
    }

    private void validateSiteIds(LedgerImportResult result, int row, String raw, List<Long> authorized)
    {
        for (String item : split(raw)) validateSite(result, row, item, authorized);
    }

    private void validateSingleSite(LedgerImportResult result, int row, String raw, List<Long> authorized)
    {
        if (!blank(raw)) validateSite(result, row, trim(raw), authorized);
    }

    private void validateSite(LedgerImportResult result, int row, String raw, List<Long> authorized)
    {
        try
        {
            Long id = Long.valueOf(raw);
            if (!authorized.contains(id)) error(result, row, "siteId", "厂站不在当前账号权限范围");
        }
        catch (NumberFormatException ex) { error(result, row, "siteId", "厂站ID必须是数字"); }
    }

    private void validateOptionalId(LedgerImportResult result, int row, String field, String raw)
    {
        if (blank(raw)) return;
        try { Long.valueOf(raw.trim()); }
        catch (NumberFormatException ex) { error(result, row, field, "ID必须是数字"); }
    }

    private void validateBinaryStatus(LedgerImportResult result, int row, String raw)
    {
        String status = normalizeBinaryStatus(raw);
        if (!blank(raw) && status == null) error(result, row, "status", "状态只能是启用/停用或 0/1");
    }

    private String normalizeBinaryStatus(String raw)
    {
        String value = trim(raw);
        if (blank(value)) return null;
        if ("0".equals(value) || "启用".equals(value)) return "0";
        if ("1".equals(value) || "停用".equals(value)) return "1";
        return null;
    }

    private void error(LedgerImportResult result, int row, String field, String reason)
    {
        result.getErrors().add(new LedgerImportError(row, field, reason));
    }

    private static List<String> split(String raw)
    {
        if (blank(raw)) return new ArrayList<String>();
        List<String> values = new ArrayList<String>();
        for (String item : raw.split("[,，]")) if (!blank(item)) values.add(item.trim());
        return values;
    }

    private static boolean blank(String value) { return StringUtils.isEmpty(value) || value.trim().isEmpty(); }
    private static String trim(String value) { return value == null ? null : value.trim(); }
    private static String trimToNull(String value) { return blank(value) ? null : value.trim(); }
}
