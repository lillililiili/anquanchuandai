package com.ruoyi.wear.web.v1;

import java.util.List;
import java.util.Map;
import javax.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.poi.ExcelUtil;
import com.ruoyi.wear.admin.LedgerExportService;
import com.ruoyi.wear.admin.LedgerImportService;
import com.ruoyi.wear.admin.dto.DeviceLedgerRow;
import com.ruoyi.wear.admin.dto.GenericLedgerRow;
import com.ruoyi.wear.admin.dto.LedgerImportResult;
import com.ruoyi.wear.admin.dto.PersonLedgerRow;
import com.ruoyi.wear.admin.dto.ProductModelLedgerRow;
import com.ruoyi.wear.auth.SiteAccessService;

@RestController
@RequestMapping("/api/v1")
public class WearLedgerController
{
    @Autowired private LedgerImportService importService;
    @Autowired private LedgerExportService exportService;
    @Autowired private SiteAccessService siteAccessService;

    @GetMapping("/{resource:people|devices|product-models}/import-template")
    public void importTemplate(@PathVariable String resource, HttpServletResponse response)
    {
        assertCanImport(resource);
        if ("people".equals(resource)) new ExcelUtil<PersonLedgerRow>(PersonLedgerRow.class).importTemplateExcel(response, "人员导入模板");
        else if ("devices".equals(resource)) new ExcelUtil<DeviceLedgerRow>(DeviceLedgerRow.class).importTemplateExcel(response, "设备导入模板");
        else new ExcelUtil<ProductModelLedgerRow>(ProductModelLedgerRow.class).importTemplateExcel(response, "产品型号导入模板");
    }

    @PostMapping("/{resource:people|devices|product-models}/import")
    public R<LedgerImportResult> importData(@PathVariable String resource,
            @RequestParam("file") MultipartFile file,
            @RequestParam(defaultValue = "false") boolean updateExisting) throws Exception
    {
        assertXlsx(file);
        assertCanImport(resource);
        LedgerImportResult result;
        if ("people".equals(resource))
        {
            List<PersonLedgerRow> rows = new ExcelUtil<PersonLedgerRow>(PersonLedgerRow.class).importExcel(file.getInputStream());
            result = importService.importPeople(rows, updateExisting);
        }
        else if ("devices".equals(resource))
        {
            List<DeviceLedgerRow> rows = new ExcelUtil<DeviceLedgerRow>(DeviceLedgerRow.class).importExcel(file.getInputStream());
            result = importService.importDevices(rows, updateExisting);
        }
        else
        {
            List<ProductModelLedgerRow> rows = new ExcelUtil<ProductModelLedgerRow>(ProductModelLedgerRow.class).importExcel(file.getInputStream());
            result = importService.importProductModels(rows, updateExisting);
        }
        return R.ok(result);
    }

    @PostMapping("/{resource:people|devices|product-models|assignments|work-tasks|fences|events|files}/export")
    public void export(@PathVariable String resource,
            @RequestBody(required = false) Map<String, Object> filters,
            HttpServletResponse response)
    {
        if ("people".equals(resource))
        {
            new ExcelUtil<PersonLedgerRow>(PersonLedgerRow.class).exportExcel(response, exportService.people(filters), "人员台账");
        }
        else if ("devices".equals(resource))
        {
            new ExcelUtil<DeviceLedgerRow>(DeviceLedgerRow.class).exportExcel(response, exportService.devices(filters), "设备台账");
        }
        else if ("product-models".equals(resource))
        {
            new ExcelUtil<ProductModelLedgerRow>(ProductModelLedgerRow.class).exportExcel(response, exportService.productModels(filters), "产品型号");
        }
        else
        {
            List<GenericLedgerRow> rows;
            String title;
            if ("assignments".equals(resource)) { rows = exportService.assignments(filters); title = "领用归还记录"; }
            else if ("work-tasks".equals(resource)) { rows = exportService.tasks(filters); title = "作业任务"; }
            else if ("fences".equals(resource)) { rows = exportService.fences(filters); title = "电子围栏"; }
            else if ("events".equals(resource)) { rows = exportService.events(filters); title = "事件记录"; }
            else { rows = exportService.files(filters); title = "文件记录"; }
            new ExcelUtil<GenericLedgerRow>(GenericLedgerRow.class).exportExcel(response, rows, title);
        }
    }

    private void assertXlsx(MultipartFile file)
    {
        String name = file == null ? null : file.getOriginalFilename();
        if (file == null || file.isEmpty() || name == null || !name.toLowerCase().endsWith(".xlsx"))
            throw new ServiceException("仅支持 .xlsx 文件", HttpStatus.BAD_REQUEST);
    }

    private void assertCanImport(String resource)
    {
        if ("people".equals(resource)) siteAccessService.assertCanWritePerson();
        else siteAccessService.assertCanWriteDevice();
    }
}
