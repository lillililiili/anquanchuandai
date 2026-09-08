package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.ElectronicFence;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Date;
import java.util.List;

/**
 * 电子围栏记录表Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface ElectronicFenceMapper extends BaseMapper<ElectronicFence> {
    /**
     * 查询围栏列表（带报警次数统计）
     */
    List<ElectronicFence> selectWithAlertCount(
            @Param("fenceName") String fenceName,
            @Param("fenceType") String fenceType,
            @Param("startTime") Date startTime,
            @Param("endTime") Date endTime
    );

    @Delete("DELETE from electronic_fence where id = #{id} ")
    int deleteById(@Param("id") Long id);


}