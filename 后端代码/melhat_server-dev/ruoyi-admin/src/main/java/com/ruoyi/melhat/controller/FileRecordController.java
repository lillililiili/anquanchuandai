package com.ruoyi.melhat.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.R;
import com.ruoyi.common.utils.SecurityUtils;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.service.IFileRecordService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.stereotype.Controller;

import java.util.Date;

/**
 * <p>
 * 文件记录表 前端控制器
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@RestController
@RequestMapping("/hat/file/record")
@Api(tags = "文件记录接口")
public class FileRecordController extends BaseController {
    @Autowired
    private IFileRecordService fileRecordService;

    /**
     * 分页查询文件记录（支持多条件过滤）
     */
    @GetMapping("/page")
    @ApiOperation(value = "分页查询文件记录")
    public R<IPage<FileRecord>> getPage(
            @RequestParam(defaultValue = "1") int current,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String fileType,
            @RequestParam(required = false) Long hatId,
            @RequestParam(required = false) String userName,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date uploadTimeFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Date uploadTimeTo
    ) {
        return R.ok(fileRecordService.pageWithFilter(current, size, fileType, hatId, userName, uploadTimeFrom, uploadTimeTo));
    }

    /**
     * 根据ID获取文件记录详情
     */
    @GetMapping("/{id}")
    @ApiOperation(value = "根据ID获取文件记录详情")
    public R<FileRecord> getById(@PathVariable Long id) {
        return R.ok(fileRecordService.getById(id));
    }

    /**
     * 下载文件（后端代理下载）
     */
    @GetMapping("/download/{id}")
    @ApiOperation(value = "下载文件")
    public ResponseEntity<byte[]> download(@PathVariable Long id) {
        byte[] fileData = fileRecordService.downloadFile(id);
        FileRecord record = fileRecordService.getById(id);
        String fileName = record != null ? record.getFileName() : "文件名";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
        headers.setContentDispositionFormData("attachment", fileName);

        return ResponseEntity.ok()
                .headers(headers)
                .body(fileData);
    }

    /**
     * 获取文件播放/预览URL（直接返回file_url，前端自行处理）
     */
    @GetMapping("/play/{id}")
    @ApiOperation(value = "获取文件播放/预览URL")
    public R<String> play(@PathVariable Long id) {
        FileRecord record = fileRecordService.getById(id);
        if (record == null || record.getFileUrl() == null) {
            throw new RuntimeException("文件不存在或无播放地址");
        }
        return R.ok(record.getFileUrl());
    }

    /**
     * 逻辑删除文件记录
     */
    @DeleteMapping("/{id}")
    @ApiOperation(value = "逻辑删除文件记录")
    public R delete(@PathVariable Long id) {
        fileRecordService.deleteById(id);
        return R.ok();
    }

    /**
     * 上传文件记录（模拟，实际上传应由文件服务处理）
     */
    @PostMapping
    @ApiOperation(value = "上传文件记录")
    public R upload(@RequestBody FileRecord record) {
        record.setDelFlag("0");
        Date date = new Date();
        record.setUploadTime(date);
        record.setCreateTime(date);
        record.setCreateBy(SecurityUtils.getUsername());
        fileRecordService.save(record);
        return R.ok();
    }
}
