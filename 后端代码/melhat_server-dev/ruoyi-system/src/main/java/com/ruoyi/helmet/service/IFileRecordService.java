package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;

import java.util.Date;
import java.util.List;

/**
 * <p>
 * 文件记录表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface IFileRecordService extends IService<FileRecord> {
    /**
     * 分页查询文件记录（支持多条件过滤 + 关联设备人员信息）
     */
    IPage<FileRecord> pageWithFilter(
            int current,
            int size,
            String fileType,
            Long hatId,
            String userName,
            Date uploadTimeFrom,
            Date uploadTimeTo
    );

    /**
     * 根据ID获取文件记录
     */
    FileRecord getById(Long id);

    /**
     * 逻辑删除文件记录
     */
    boolean deleteById(Long id);

    /**
     * 获取文件下载流（可选，如需后端代理下载）
     */
    byte[] downloadFile(Long id);

    List<FileRecord> getRelatedFiles(String hatNumber, String fileType, String startTime, String endTime);

}
