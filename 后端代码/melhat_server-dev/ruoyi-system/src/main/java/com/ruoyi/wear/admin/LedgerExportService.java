package com.ruoyi.wear.admin;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.ruoyi.wear.admin.dto.DeviceLedgerRow;
import com.ruoyi.wear.admin.dto.GenericLedgerRow;
import com.ruoyi.wear.admin.dto.PersonLedgerRow;
import com.ruoyi.wear.admin.dto.ProductModelLedgerRow;
import com.ruoyi.wear.assignment.AssignmentService;
import com.ruoyi.wear.assignment.dto.AssignmentDto;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.device.DeviceService;
import com.ruoyi.wear.device.ProductModelService;
import com.ruoyi.wear.device.dto.CapabilityDto;
import com.ruoyi.wear.device.dto.DeviceDto;
import com.ruoyi.wear.device.dto.ProductModelDto;
import com.ruoyi.wear.event.EventQueryService;
import com.ruoyi.wear.event.dto.EventDto;
import com.ruoyi.wear.file.FileAuditService;
import com.ruoyi.wear.file.FileAuditDto;
import com.ruoyi.wear.location.FenceService;
import com.ruoyi.wear.location.dto.GeoFenceDto;
import com.ruoyi.wear.person.PersonService;
import com.ruoyi.wear.person.dto.PersonDto;
import com.ruoyi.wear.work.WorkTaskService;
import com.ruoyi.wear.work.dto.WorkTaskDto;

@Service
public class LedgerExportService
{
    @Autowired private PersonService personService;
    @Autowired private DeviceService deviceService;
    @Autowired private ProductModelService productModelService;
    @Autowired private AssignmentService assignmentService;
    @Autowired private WorkTaskService workTaskService;
    @Autowired private FenceService fenceService;
    @Autowired private EventQueryService eventQueryService;
    @Autowired private FileAuditService fileAuditService;
    @Autowired private SiteAccessService siteAccessService;

    public List<PersonLedgerRow> people(Map<String, Object> filters)
    {
        siteAccessService.assertCanWritePerson();
        List<PersonLedgerRow> rows = new ArrayList<PersonLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<PersonDto> result = personService.page(page, 100, f(filters, "name"), f(filters, "personCode"),
                    f(filters, "status"), f(filters, "teamId"), f(filters, "contractorId"));
            for (PersonDto item : result.getRecords())
            {
                PersonLedgerRow row = new PersonLedgerRow();
                row.setPersonCode(item.getPersonCode()); row.setName(item.getName()); row.setTeamId(item.getTeamId());
                row.setContractorId(item.getContractorId()); row.setSiteIds(join(item.getSiteIds()));
                row.setValidFrom(item.getValidFrom()); row.setValidTo(item.getValidTo()); row.setStatus(item.getStatus());
                rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    public List<DeviceLedgerRow> devices(Map<String, Object> filters)
    {
        siteAccessService.assertCanWriteDevice();
        List<DeviceLedgerRow> rows = new ArrayList<DeviceLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<DeviceDto> result = deviceService.page(page, 100, f(filters, "typeCode"), f(filters, "modelId"),
                    f(filters, "sn"), f(filters, "assetStatus"));
            for (DeviceDto item : result.getRecords())
            {
                DeviceLedgerRow row = new DeviceLedgerRow();
                row.setManufacturerCode(item.getManufacturerCode()); row.setSn(item.getSn());
                row.setModelCode(item.getModelCode()); row.setExternalCode(item.getExternalCode());
                row.setSiteId(item.getSiteId()); row.setAssetStatus(item.getAssetStatus()); rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    public List<ProductModelLedgerRow> productModels(Map<String, Object> filters)
    {
        siteAccessService.assertCanWriteDevice();
        List<ProductModelLedgerRow> rows = new ArrayList<ProductModelLedgerRow>();
        String keyword = f(filters, "keyword");
        for (ProductModelDto item : productModelService.list(f(filters, "typeCode"), valueOr(f(filters, "status"), "all")))
        {
            if (keyword != null && !contains(item.getModelCode(), keyword) && !contains(item.getName(), keyword)) continue;
            ProductModelLedgerRow row = new ProductModelLedgerRow();
            row.setTypeCode(item.getTypeCode()); row.setModelCode(item.getModelCode());
            row.setManufacturerCode(item.getManufacturerCode()); row.setName(item.getName());
            row.setProtocolVersion(item.getProtocolVersion()); row.setStatus(item.getStatus());
            CapabilityDto caps = item.getCapabilities();
            if (caps != null)
            {
                row.setAttributes(join(caps.getAttributes())); row.setEvents(join(caps.getEvents()));
                row.setActions(join(caps.getActions()));
            }
            rows.add(row);
        }
        return rows;
    }

    public List<GenericLedgerRow> assignments(Map<String, Object> filters)
    {
        siteAccessService.assertCanWriteDevice();
        List<GenericLedgerRow> rows = new ArrayList<GenericLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<AssignmentDto> result = assignmentService.page(page, 100, f(filters, "sn"),
                    f(filters, "personKeyword"), f(filters, "status"), f(filters, "issuedFrom"), f(filters, "issuedTo"));
            for (AssignmentDto item : result.getRecords())
            {
                GenericLedgerRow row = base(item.getId(), item.getSn(), item.getPersonName(), item.getTypeCode(),
                        item.getReturnedAt() == null ? "active" : "returned", item.getSiteId());
                row.setRelation(item.getPersonCode()); row.setStartTime(item.getIssuedAt()); row.setEndTime(item.getReturnedAt());
                row.setRemark(item.getReturnReason()); rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    public List<GenericLedgerRow> tasks(Map<String, Object> filters)
    {
        siteAccessService.assertCanEditTask();
        List<GenericLedgerRow> rows = new ArrayList<GenericLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<WorkTaskDto> result = workTaskService.page(page, 100, f(filters, "status"), f(filters, "workType"));
            for (WorkTaskDto item : result.getRecords())
            {
                GenericLedgerRow row = base(item.getId(), item.getTicketNo(), item.getTitle(), item.getWorkType(),
                        item.getStatus(), item.getSiteId());
                row.setRelation(item.getSpaceName()); row.setStartTime(item.getPlannedStart()); row.setEndTime(item.getPlannedEnd());
                row.setRemark(item.getTicketStatus()); rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    public List<GenericLedgerRow> fences(Map<String, Object> filters)
    {
        siteAccessService.assertCanWriteDevice();
        List<GenericLedgerRow> rows = new ArrayList<GenericLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<GeoFenceDto> result = fenceService.page(page, 100, f(filters, "name"), f(filters, "enabled"));
            for (GeoFenceDto item : result.getRecords())
            {
                GenericLedgerRow row = base(item.getId(), null, item.getName(), item.getApplyMode(),
                        Boolean.TRUE.equals(item.getEnabled()) ? "enabled" : "disabled", item.getSiteId());
                row.setRelation(item.getPersonIds() == null ? null : join(item.getPersonIds()));
                row.setRemark("时段 " + valueOr(item.getTimeStart(), "不限") + " - " + valueOr(item.getTimeEnd(), "不限")
                        + "；防抖 " + item.getDebounceSeconds() + " 秒");
                rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    public List<GenericLedgerRow> events(Map<String, Object> filters)
    {
        siteAccessService.requireLogin();
        List<GenericLedgerRow> rows = new ArrayList<GenericLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<EventDto> result = eventQueryService.page(page, 100, f(filters, "type"), f(filters, "status"),
                    f(filters, "personId"), f(filters, "severity"), f(filters, "updatedAfter"),
                    f(filters, "claimantUserId"), f(filters, "escalated"), f(filters, "personKeyword"),
                    f(filters, "sn"), f(filters, "taskId"), f(filters, "occurredFrom"), f(filters, "occurredTo"));
            for (EventDto item : result.getRecords())
            {
                GenericLedgerRow row = base(item.getId(), item.getSn(), item.getPersonName(), item.getType(),
                        item.getStatus(), item.getSiteId());
                row.setRelation("人员 " + valueOr(item.getPersonCode(), "-") + "；任务 " + valueOr(item.getTaskId(), "-"));
                row.setStartTime(item.getOccurredAt()); row.setEndTime(item.getReceivedAt());
                row.setRemark("等级 " + valueOr(item.getSeverity(), "-") + (Boolean.TRUE.equals(item.getEscalated()) ? "；已升级" : ""));
                rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    public List<GenericLedgerRow> files(Map<String, Object> filters)
    {
        siteAccessService.requireLogin();
        List<GenericLedgerRow> rows = new ArrayList<GenericLedgerRow>();
        for (int page = 1;; page++)
        {
            WearPage<FileAuditDto> result = fileAuditService.page(page, 100, f(filters, "fileName"), f(filters, "fileType"),
                    f(filters, "device"), f(filters, "userName"), f(filters, "uploadTimeFrom"), f(filters, "uploadTimeTo"));
            for (FileAuditDto item : result.getRecords())
            {
                GenericLedgerRow row = base(item.getId(), item.getHatNumber(), item.getFileName(),
                        item.getFileType(), "recorded", null);
                row.setRelation(item.getDeviceInfo()); row.setStartTime(item.getUploadTime());
                row.setRemark(item.getFileSize() == null ? null : item.getFileSize().toPlainString()); rows.add(row);
            }
            if (page * 100L >= result.getTotal()) break;
        }
        return rows;
    }

    private GenericLedgerRow base(String id, String code, String name, String type, String status, String siteId)
    {
        GenericLedgerRow row = new GenericLedgerRow();
        row.setId(id); row.setCode(code); row.setName(name); row.setType(type); row.setStatus(status); row.setSiteId(siteId);
        return row;
    }

    private String f(Map<String, Object> values, String key)
    {
        if (values == null || values.get(key) == null) return null;
        String value = String.valueOf(values.get(key)).trim();
        return value.isEmpty() || "null".equals(value) ? null : value;
    }

    private static String join(List<String> values) { return values == null ? null : String.join(",", values); }
    private static String valueOr(String value, String fallback) { return value == null || value.isEmpty() ? fallback : value; }
    private static boolean contains(String value, String keyword)
    {
        return value != null && value.toLowerCase().contains(keyword.toLowerCase());
    }
}
