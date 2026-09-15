package com.ruoyi.wear.web.v1;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.wear.common.WearPage;
import com.ruoyi.wear.file.FileAuditService;
import com.ruoyi.wear.file.FileAuditDto;

@RestController
@RequestMapping("/api/v1/files")
public class WearFileController
{
    @Autowired private FileAuditService fileAuditService;

    @GetMapping
    public R<WearPage<FileAuditDto>> page(@RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String fileName,
            @RequestParam(required = false) String fileType,
            @RequestParam(required = false) String device,
            @RequestParam(required = false) String userName,
            @RequestParam(required = false) String uploadTimeFrom,
            @RequestParam(required = false) String uploadTimeTo)
    {
        return R.ok(fileAuditService.page(current, size, fileName, fileType, device, userName, uploadTimeFrom, uploadTimeTo));
    }

    @GetMapping("/{id}")
    public R<FileAuditDto> detail(@PathVariable Long id) { return R.ok(fileAuditService.detail(id)); }

    @GetMapping("/{id}/download")
    public ResponseEntity<byte[]> download(@PathVariable Long id)
    {
        FileRecord row = fileAuditService.requireReadable(id);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
        headers.setContentDispositionFormData("attachment", row.getFileName());
        return ResponseEntity.ok().headers(headers).body(fileAuditService.download(id));
    }
}
