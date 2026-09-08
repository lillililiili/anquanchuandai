package com.ruoyi.helmet.pojo.po;

import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import com.baomidou.mybatisplus.extension.activerecord.Model;
import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.util.Date;

/**
 * 电子围栏经纬度表
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Data
@TableName("electronic_fence_latitude")
@EqualsAndHashCode(callSuper = true)
@ApiModel(value = "电子围栏坐标信息", description = "电子围栏坐标信息")
public class ElectronicFenceLatitude extends Model<ElectronicFenceLatitude> {

    private static final long serialVersionUID = 1L;

    /**
     * 主键id
     */
    @ApiModelProperty(value = "电子围栏坐标主键id")
    private Long id;
    /**
     * 电子围栏id
     */
    @ApiModelProperty(value = "电子围栏id")
    private Long fenceId;
    /**
     * 经度
     */
    @ApiModelProperty(value = "电子围栏经度")
    private Double longitude;
    /**
     * 纬度
     */
    @ApiModelProperty(value = "电子围栏纬度")
    private Double latitude;
    /**
     * 创建时间
     */
    private Date createTime;
    /**
     * 更新时间
     */
    private Date updateTime;
    /**
     * 删除标志（0代表存在 2代表删除）
     */
    @TableLogic
    private Integer delFlag;
    /**
     * 创建者
     */
    private String createBy;
    /**
     * 更新者
     */
    private String updateBy;

}
