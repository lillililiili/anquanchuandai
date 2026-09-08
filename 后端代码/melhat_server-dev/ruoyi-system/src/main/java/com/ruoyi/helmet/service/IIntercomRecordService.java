package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import com.ruoyi.helmet.pojo.po.IntercomRecord;
import com.ruoyi.helmet.pojo.po.IntercomRecordRequest;

import java.util.Date;

/**
 * <p>
 * 对讲记录表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface IIntercomRecordService extends IService<IntercomRecord> {
    /**
     * 分页查询对讲记录（支持条件过滤）
     */
    IPage<IntercomRecord> pageWithFilter(
            int current,
            int size,
            String intercomType,
            Date startTimeFrom,
            Date startTimeTo
    );

    /**
     * 创建新的对讲记录
     */
    ResponseVO createIntercom(IntercomRecord record, IntercomRecordRequest request) throws Exception;

    /**
     * 结束正在进行的对讲（设置 endTime 和 duration）
     */
    boolean endIntercom(Long id) throws Exception;

    ResponseVO endIntercom(String channelName) throws Exception;
    /**
     * 根据ID获取对讲记录
     */
    IntercomRecord getById(Long id);

    /**
     * 逻辑删除对讲记录
     */
    boolean deleteById(Long id);
}
