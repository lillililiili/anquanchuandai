package com.ruoyi.wear.file;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.ruoyi.common.constant.HttpStatus;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.StringUtils;
import com.ruoyi.helmet.mapper.FileRecordMapper;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.service.IFileRecordService;
import com.ruoyi.wear.auth.SiteAccessService;
import com.ruoyi.wear.common.WearPage;

@Service
public class FileAuditService
{
    @Autowired private FileRecordMapper fileRecordMapper;
    @Autowired private IFileRecordService fileRecordService;
    @Autowired private SiteAccessService siteAccessService;

    public WearPage<FileAuditDto> page(int current, int size, String fileName, String fileType,
            String device, String userName, String uploadTimeFrom, String uploadTimeTo)
    {
        int safeCurrent = current < 1 ? 1 : current;
        int safeSize = size < 1 ? 10 : Math.min(size, 100);
        List<Long> siteIds = siteAccessService.listScopeSiteIds();
        if (siteIds.isEmpty()) return WearPage.of(new ArrayList<FileAuditDto>(), 0, safeCurrent, safeSize);
        List<FileRecord> rows = fileRecordMapper.selectAuditRecords(siteIds, fileName, fileType, device, userName,
                parseDate(uploadTimeFrom, false), parseDate(uploadTimeTo, true));
        int from = Math.min((safeCurrent - 1) * safeSize, rows.size());
        int to = Math.min(from + safeSize, rows.size());
        List<FileAuditDto> records = new ArrayList<FileAuditDto>();
        for (FileRecord row : rows.subList(from, to)) records.add(toDto(row));
        return WearPage.of(records, rows.size(), safeCurrent, safeSize);
    }

    public FileAuditDto detail(Long id)
    {
        return toDto(requireReadable(id));
    }

    public FileRecord requireReadable(Long id)
    {
        FileRecord row = fileRecordService.getById(id);
        if (row == null) throw new ServiceException("访问资源不存在", HttpStatus.NOT_FOUND);
        List<Long> siteIds = siteAccessService.listScopeSiteIds();
        if (siteIds.isEmpty()) throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
        List<FileRecord> allowed = fileRecordMapper.selectAuditRecords(siteIds,
                null, null, null, null, null, null);
        for (FileRecord item : allowed) if (id.equals(item.getId())) return item;
        throw new ServiceException("没有权限执行该操作", HttpStatus.FORBIDDEN);
    }

    public byte[] download(Long id)
    {
        requireReadable(id);
        return fileRecordService.downloadFile(id);
    }

    private FileAuditDto toDto(FileRecord row)
    {
        FileAuditDto dto = new FileAuditDto();
        dto.setId(String.valueOf(row.getId())); dto.setFileName(row.getFileName()); dto.setFileType(row.getFileType());
        dto.setHatNumber(row.getHatNumber()); dto.setUserName(row.getUserName()); dto.setFileSize(row.getFileSize());
        dto.setUploadTime(row.getUploadTime()); dto.setDeviceInfo(row.getDeviceInfo());
        return dto;
    }

    private Date parseDate(String raw, boolean endOfDay)
    {
        if (StringUtils.isEmpty(raw)) return null;
        try
        {
            Date parsed = new SimpleDateFormat("yyyy-MM-dd").parse(raw.trim());
            return endOfDay ? new Date(parsed.getTime() + 86399999L) : parsed;
        }
        catch (ParseException ex)
        {
            throw new ServiceException("日期格式无效", HttpStatus.BAD_REQUEST);
        }
    }
}
