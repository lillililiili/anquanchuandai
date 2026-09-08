package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.ElectronicFenceLatitude;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

/**
 * 电子围栏经纬度表Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface ElectronicFenceLatitudeMapper extends BaseMapper<ElectronicFenceLatitude> {
    @Select("SELECT * FROM electronic_fence_latitude WHERE fence_id = #{fenceId} AND del_flag = 0 ORDER BY id ASC")
    List<ElectronicFenceLatitude> selectByFenceId(@Param("fenceId") Long fenceId);


    @Delete("DELETE from electronic_fence_latitude where fence_id = #{fenceId} ")
    int deleteByFenceId(@Param("fenceId") Long fenceId);

}