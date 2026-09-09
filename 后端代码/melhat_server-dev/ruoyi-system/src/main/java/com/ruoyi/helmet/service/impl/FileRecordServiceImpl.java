package com.ruoyi.helmet.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.ruoyi.common.utils.file.SafeRemoteFileFetcher;
import com.ruoyi.helmet.mapper.FileRecordMapper;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.service.IFileRecordService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;

/**
 * <p>
 * 文件记录表 服务实现类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
@Service
public class FileRecordServiceImpl extends ServiceImpl<FileRecordMapper, FileRecord> implements IFileRecordService {

    @Autowired
    private FileRecordMapper fileRecordMapper;

    @Value("${melhat.download.connect-timeout-ms:5000}")
    private int downloadConnectTimeoutMs;

    @Value("${melhat.download.read-timeout-ms:15000}")
    private int downloadReadTimeoutMs;

    @Value("${melhat.download.max-bytes:20971520}")
    private int downloadMaxBytes;

    @Value("${melhat.download.max-redirects:3}")
    private int downloadMaxRedirects;

    @Value("${melhat.download.allow-private-network:false}")
    private boolean downloadAllowPrivateNetwork;

    @Override
    public IPage<FileRecord> pageWithFilter(int current, int size, String fileType, Long hatId, String userName,
                                            Date uploadTimeFrom, Date uploadTimeTo) {
        // 使用自定义SQL查询（带设备人员信息）
        List<FileRecord> list = fileRecordMapper.selectWithDeviceInfo(
                null, // fileName 暂不支持模糊搜，可按需扩展
                fileType,
                hatId,
                userName,
                uploadTimeFrom,
                uploadTimeTo
        );

        // 手动分页（因为自定义SQL无法直接用MP分页插件）
        int total = list.size();
        int fromIndex = (current - 1) * size;
        int toIndex = Math.min(fromIndex + size, total);
        List<FileRecord> pageList = fromIndex < total ? list.subList(fromIndex, toIndex) : new ArrayList<>();

        IPage<FileRecord> page = new Page<>(current, size, total);
        page.setRecords(pageList);

        // 组装 deviceInfo 字段
        for (FileRecord record : pageList) {
            if (record.getHatId() != null) {
                // 这里假设你已经通过SQL关联了 hat_number 和 bind_user_name
                // 实际项目中建议在SQL中直接拼接成 deviceInfo 字段
                String hatNumber = record.getHatNumber();
                String userNameVal = record.getUserName();
                record.setDeviceInfo(hatNumber + " - " + userNameVal);
            } else {
                record.setDeviceInfo("未知设备");
            }
        }

        return page;
    }

    @Override
    public FileRecord getById(Long id) {
        return fileRecordMapper.selectById(id);
    }

    @Override
    public boolean deleteById(Long id) {
        return this.update(null,new LambdaUpdateWrapper<FileRecord>()
                .eq(FileRecord::getId, id)
                .set(FileRecord::getDelFlag,"2")
                .set(FileRecord::getUpdateTime,new Date()));
    }

    @Override
    public byte[] downloadFile(Long id) {
        FileRecord record = this.getById(id);
        if (record == null || record.getFileUrl() == null) {
            throw new RuntimeException("文件不存在或无下载地址");
        }
        return new SafeRemoteFileFetcher(downloadConnectTimeoutMs, downloadReadTimeoutMs,
                downloadMaxBytes, downloadMaxRedirects, downloadAllowPrivateNetwork)
                .fetch(record.getFileUrl());
    }

    @Override
    public List<FileRecord> getRelatedFiles(String hatNumber, String fileType, String startTime, String endTime) {
        // 使用自定义SQL查询关联的轨迹点
        return fileRecordMapper.selectRelatedFiles(hatNumber, fileType, startTime, endTime);
    }

}
