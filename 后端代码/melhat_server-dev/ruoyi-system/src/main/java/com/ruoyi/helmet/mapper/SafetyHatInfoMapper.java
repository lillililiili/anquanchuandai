package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.SafetyHatInfo;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import java.math.BigDecimal;

/**
 * 安全帽信息表 Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface SafetyHatInfoMapper extends BaseMapper<SafetyHatInfo> {

    // 同步时识别已删除记录，不自动恢复用户删除的设备。
    @org.apache.ibatis.annotations.Select("SELECT * FROM safety_hat_info WHERE hat_number = #{sn}")
    java.util.List<SafetyHatInfo> findIncludingDeleted(@Param("sn") String sn);

    /**
     * 统计图片数量（根据文件类型 'image'）
     * @param hatId 帽子 ID，为 null 时统计所有
     * @return 图片总数
     */
    Integer countPhotoByHatId(@Param("hatId") Long hatId);
    
    /**
     * 统计在线人员数量
     * @return 在线人员数量
     */
    Integer countOnlineUsers();
    
    /**
     * 统计设备正常率
     * @return 设备正常率（百分比）
     */
    BigDecimal countDeviceNormalRate();

    /**
     * 更新安全帽信息，支持 null 值
     * @param safetyHat 安全帽信息
     * @return 影响行数
     */
    int updateSafetyHatInfo(SafetyHatInfo safetyHat);

}
