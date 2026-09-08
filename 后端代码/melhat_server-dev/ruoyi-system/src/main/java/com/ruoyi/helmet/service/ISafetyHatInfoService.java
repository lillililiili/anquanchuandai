package com.ruoyi.helmet.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import com.ruoyi.helmet.vo.SafetyHatListVO;
import com.ruoyi.helmet.vo.SafetyHatQueryVO;

import java.util.List;

/**
 * <p>
 * 安全帽信息表 服务类
 * </p>
 *
 * @author autoGennerate
 * @since 2026-03-12
 */
public interface ISafetyHatInfoService extends IService<SafetyHatInfo> {
    Page<SafetyHatListVO> pageQuery(SafetyHatQueryVO queryVO, int current, int size);

    List<SafetyHatListVO> listAll();

    SafetyHatInfo getById(Long id);

    boolean saveOrUpdate(SafetyHatInfo safetyHat);

    boolean deleteById(Long id);

    boolean batchDelete(List<Long> ids);

    boolean updateStatus(Long id, String status);

    /**
     * 根据安全帽编号查询
     */
    SafetyHatListVO getByHatNumber(String hatNumber);

    List<SafetyHatInfo> getHatNumbersByGroupNumber(Long groupId);

    SafetyHatInfo getHatByUserId(Long userId);
}
